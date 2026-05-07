const std = @import("std");
const runtime_pkg = @import("../runtime/runtime.zig");
const transform = @import("transform.zig");
const quickjs = @import("quickjs");

const Allocator = std.mem.Allocator;
const Runtime = runtime_pkg.Runtime;
const Exception = runtime_pkg.Exception;
const ModuleContext = runtime_pkg.ModuleContext;
const ModuleDef = runtime_pkg.ModuleDef;

const harness_source = @embedFile("runner_harness.js");
const run_bootstrap_source =
    \\globalThis.__zigDone = false;
    \\globalThis.__zigRunError = "";
    \\Promise.resolve()
    \\  .then(() => globalThis.__zigRunner.run())
    \\  .then(() => {
    \\    globalThis.__zigDone = true;
    \\  })
    \\  .catch((error) => {
    \\    const details = error && error.stack ? String(error.stack) : String(error);
    \\    globalThis.__zigRunError = details;
    \\    globalThis.__zigDone = true;
    \\  });
;

const bun_test_specifier = "bun:test";
const react_specifier = "react";
const react_dom_client_specifier = "react-dom/client";
const testing_library_specifier = "@testing-library/react";
const vanilla_extract_css_specifier = "@vanilla-extract/css";

const bun_test_shim_source =
    \\export const test = globalThis.test;
    \\export const it = globalThis.it;
    \\export const describe = globalThis.describe;
    \\export const expect = globalThis.expect;
    \\export const beforeAll = globalThis.beforeAll;
    \\export const beforeEach = globalThis.beforeEach;
    \\export const afterEach = globalThis.afterEach;
    \\export const afterAll = globalThis.afterAll;
    \\const bunTest = { test, it, describe, expect, beforeAll, beforeEach, afterEach, afterAll };
    \\export default bunTest;
;

const react_shim_source =
    \\const React = globalThis.React;
    \\export const createElement = React.createElement;
    \\export const Fragment = React.Fragment;
    \\export default React;
;

const react_dom_client_shim_source =
    \\const Client = globalThis.ReactDOMClient;
    \\export const createRoot = Client.createRoot;
    \\export default Client;
;

const testing_library_shim_source =
    \\export const render = globalThis.render;
    \\export const screen = globalThis.screen;
    \\export const fireEvent = globalThis.fireEvent;
    \\const api = { render, screen, fireEvent };
    \\export default api;
;

const vanilla_extract_css_shim_source =
    \\let __zigStyleCounter = 0;
    \\export function style(_rules) {
    \\  __zigStyleCounter += 1;
    \\  return "ve-" + String(__zigStyleCounter);
    \\}
    \\export default { style };
;

const max_module_source_bytes = 4 * 1024 * 1024;

pub const FileResult = struct {
    path: []u8,
    passed: usize,
    failed: usize,
    skipped: usize,
    timed_out: usize,
    collection_errors: usize,
    failure_report: ?[]u8,
    collection_report: ?[]u8,

    pub fn deinit(self: *FileResult, allocator: Allocator) void {
        allocator.free(self.path);
        if (self.failure_report) |report| {
            allocator.free(report);
        }
        if (self.collection_report) |report| {
            allocator.free(report);
        }
    }
};

pub const Summary = struct {
    files: []FileResult,
    total_passed: usize,
    total_failed: usize,
    total_skipped: usize,
    total_timed_out: usize,
    total_collection_errors: usize,

    pub fn deinit(self: *Summary, allocator: Allocator) void {
        for (self.files) |*file| {
            file.deinit(allocator);
        }
        allocator.free(self.files);
    }

    pub fn hasFailures(self: Summary) bool {
        return self.total_failed > 0 or self.total_timed_out > 0 or self.total_collection_errors > 0;
    }
};

const ModuleLoaderState = struct {
    allocator: Allocator,
    io: std.Io,
    loaded_modules: std.StringHashMap(*ModuleDef),
    module_sources: std.StringHashMap([]u8),
    transformed_outputs: std.StringHashMap([]u8),

    fn init(allocator: Allocator, io: std.Io) ModuleLoaderState {
        return .{
            .allocator = allocator,
            .io = io,
            .loaded_modules = std.StringHashMap(*ModuleDef).init(allocator),
            .module_sources = std.StringHashMap([]u8).init(allocator),
            .transformed_outputs = std.StringHashMap([]u8).init(allocator),
        };
    }

    fn deinit(self: *ModuleLoaderState) void {
        var source_iterator = self.module_sources.iterator();
        while (source_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.module_sources.deinit();

        var output_iterator = self.transformed_outputs.iterator();
        while (output_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.transformed_outputs.deinit();

        var loaded_iterator = self.loaded_modules.iterator();
        while (loaded_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.loaded_modules.deinit();
    }

    fn normalizeSpecifier(self: *ModuleLoaderState, module_base_name: []const u8, module_name: []const u8) ![]u8 {
        if (shimModuleSource(module_name) != null) {
            return self.allocator.dupe(u8, module_name);
        }

        if (std.mem.startsWith(u8, module_name, "~/")) {
            return self.resolveProjectAlias(module_base_name, "src", module_name[2..]);
        }

        if (std.mem.startsWith(u8, module_name, "@/shared/")) {
            return self.resolveProjectAlias(module_base_name, "shared", module_name[9..]);
        }

        if (std.mem.startsWith(u8, module_name, "@/")) {
            return self.resolveProjectAlias(module_base_name, "", module_name[2..]);
        }

        if (std.fs.path.isAbsolute(module_name)) {
            return self.resolveAbsolutePath(module_name);
        }

        if (isRelativeSpecifier(module_name)) {
            return self.resolveRelativePath(module_base_name, module_name);
        }

        return error.UnsupportedExternalModule;
    }

    fn preloadEntryGraph(self: *ModuleLoaderState, entry_module_id: []const u8) !void {
        const graph = try self.discoverModuleGraph(entry_module_id);
        defer {
            for (graph) |module_id| {
                self.allocator.free(module_id);
            }
            self.allocator.free(graph);
        }

        var transform_targets: std.ArrayList([]const u8) = .empty;
        defer transform_targets.deinit(self.allocator);

        for (graph) |module_id| {
            if (transform.needsTransform(module_id)) {
                try transform_targets.append(self.allocator, module_id);
            }
        }

        if (transform_targets.items.len == 0) {
            return;
        }

        const prepared = try transform.prepareModuleTransforms(self.allocator, self.io, transform_targets.items);
        defer prepared.deinit(self.allocator);

        if (prepared.outputs.len != transform_targets.items.len) {
            return error.TransformCommandFailed;
        }

        for (transform_targets.items, prepared.outputs) |module_id, output_path| {
            const key = try self.allocator.dupe(u8, module_id);
            errdefer self.allocator.free(key);

            const value = try self.allocator.dupe(u8, output_path);
            errdefer self.allocator.free(value);

            try self.transformed_outputs.put(key, value);
        }
    }

    fn discoverModuleGraph(self: *ModuleLoaderState, entry_module_id: []const u8) ![]const []u8 {
        var queue: std.ArrayList([]u8) = .empty;
        errdefer {
            for (queue.items) |item| {
                self.allocator.free(item);
            }
            queue.deinit(self.allocator);
        }

        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();

        const entry = try self.allocator.dupe(u8, entry_module_id);
        queue.append(self.allocator, entry) catch |err| {
            self.allocator.free(entry);
            return err;
        };
        seen.put(entry, {}) catch |err| {
            _ = queue.pop();
            self.allocator.free(entry);
            return err;
        };

        var index: usize = 0;
        while (index < queue.items.len) : (index += 1) {
            const module_id = queue.items[index];

            const source = try std.Io.Dir.cwd().readFileAlloc(
                self.io,
                module_id,
                self.allocator,
                .limited(max_module_source_bytes),
            );
            defer self.allocator.free(source);

            const specifiers = try collectEsmSpecifiers(self.allocator, source);
            defer {
                for (specifiers) |specifier| {
                    self.allocator.free(specifier);
                }
                self.allocator.free(specifiers);
            }

            for (specifiers) |specifier| {
                const resolved = self.normalizeSpecifier(module_id, specifier) catch |err| switch (err) {
                    // External package specifiers may be type-only imports erased by transform.
                    error.UnsupportedExternalModule => continue,
                    else => return err,
                };
                if (shimModuleSource(resolved) != null) {
                    self.allocator.free(resolved);
                    continue;
                }

                if (seen.contains(resolved)) {
                    self.allocator.free(resolved);
                    continue;
                }

                try seen.put(resolved, {});
                try queue.append(self.allocator, resolved);
            }
        }

        return queue.toOwnedSlice(self.allocator);
    }

    fn loadModuleSource(self: *ModuleLoaderState, module_id: []const u8) ![]const u8 {
        if (shimModuleSource(module_id)) |shim_source| {
            return shim_source;
        }

        if (self.module_sources.get(module_id)) |cached| {
            return cached;
        }

        const loader = transform.loaderForPath(module_id) orelse return error.UnsupportedModuleExtension;
        if (std.mem.eql(u8, loader, "js")) {
            const source = try std.Io.Dir.cwd().readFileAlloc(
                self.io,
                module_id,
                self.allocator,
                .limited(max_module_source_bytes),
            );

            try self.cacheModuleSource(module_id, source);
            return self.module_sources.get(module_id).?;
        }

        const output_path = self.transformed_outputs.get(module_id) orelse return error.ModuleNotPrepared;
        const transformed = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            output_path,
            self.allocator,
            .limited(max_module_source_bytes),
        );

        try self.cacheModuleSource(module_id, transformed);
        return self.module_sources.get(module_id).?;
    }

    fn cacheModuleSource(self: *ModuleLoaderState, module_id: []const u8, source: []u8) !void {
        const key = try self.allocator.dupe(u8, module_id);
        errdefer self.allocator.free(key);

        try self.module_sources.put(key, source);
    }

    fn resolveRelativePath(self: *ModuleLoaderState, module_base_name: []const u8, specifier: []const u8) ![]u8 {
        if (!std.fs.path.isAbsolute(module_base_name)) {
            return error.ModuleNotFound;
        }

        const base_dir = std.fs.path.dirname(module_base_name) orelse return error.ModuleNotFound;
        const candidate = try std.fs.path.resolve(self.allocator, &.{ base_dir, specifier });
        errdefer self.allocator.free(candidate);

        return self.resolvePathWithProbing(candidate);
    }

    fn resolveAbsolutePath(self: *ModuleLoaderState, specifier: []const u8) ![]u8 {
        const candidate = try std.fs.path.resolve(self.allocator, &.{specifier});
        errdefer self.allocator.free(candidate);

        return self.resolvePathWithProbing(candidate);
    }

    fn resolvePathWithProbing(self: *ModuleLoaderState, candidate: []u8) ![]u8 {
        if (self.pathIsSupportedFile(candidate)) {
            return candidate;
        }

        if (std.mem.eql(u8, std.fs.path.extension(candidate), ".css")) {
            const css_ts_candidate = try std.fmt.allocPrint(self.allocator, "{s}.ts", .{candidate});
            if (self.pathIsSupportedFile(css_ts_candidate)) {
                self.allocator.free(candidate);
                return css_ts_candidate;
            }
            self.allocator.free(css_ts_candidate);
        }

        if (std.fs.path.extension(candidate).len > 0) {
            return error.ModuleNotFound;
        }

        if (try self.resolvePathWithoutExtension(candidate)) |resolved| {
            self.allocator.free(candidate);
            return resolved;
        }

        return error.ModuleNotFound;
    }

    fn resolvePathWithoutExtension(self: *ModuleLoaderState, base_path: []const u8) !?[]u8 {
        const extensions = [_][]const u8{ ".ts", ".tsx", ".jsx", ".js" };

        for (extensions) |extension| {
            const candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_path, extension });
            if (self.pathIsSupportedFile(candidate)) {
                return candidate;
            }
            self.allocator.free(candidate);
        }

        for (extensions) |extension| {
            const candidate = try std.fmt.allocPrint(self.allocator, "{s}/index{s}", .{ base_path, extension });
            if (self.pathIsSupportedFile(candidate)) {
                return candidate;
            }
            self.allocator.free(candidate);
        }

        return null;
    }

    fn resolveProjectAlias(
        self: *ModuleLoaderState,
        module_base_name: []const u8,
        project_subdir: []const u8,
        specifier_suffix: []const u8,
    ) ![]u8 {
        if (!std.fs.path.isAbsolute(module_base_name)) {
            return error.ModuleNotFound;
        }

        var current_dir = try self.allocator.dupe(u8, std.fs.path.dirname(module_base_name) orelse return error.ModuleNotFound);
        defer self.allocator.free(current_dir);

        while (true) {
            if (self.directoryContainsFile(current_dir, "tsconfig.json") or self.directoryContainsFile(current_dir, "package.json")) {
                const candidate = if (project_subdir.len > 0)
                    try std.fs.path.resolve(self.allocator, &.{ current_dir, project_subdir, specifier_suffix })
                else
                    try std.fs.path.resolve(self.allocator, &.{ current_dir, specifier_suffix });
                errdefer self.allocator.free(candidate);
                return self.resolvePathWithProbing(candidate);
            }

            const parent = std.fs.path.dirname(current_dir) orelse break;
            if (parent.len == current_dir.len) {
                break;
            }

            const next_dir = try self.allocator.dupe(u8, parent);
            self.allocator.free(current_dir);
            current_dir = next_dir;
        }

        return error.ModuleNotFound;
    }

    fn directoryContainsFile(self: *ModuleLoaderState, dir_path: []const u8, basename: []const u8) bool {
        const candidate = std.fs.path.resolve(self.allocator, &.{ dir_path, basename }) catch return false;
        defer self.allocator.free(candidate);

        const stat = std.Io.Dir.cwd().statFile(self.io, candidate, .{}) catch return false;
        return stat.kind == .file;
    }

    fn pathIsSupportedFile(self: *ModuleLoaderState, path: []const u8) bool {
        if (transform.loaderForPath(path) == null) {
            return false;
        }

        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return false;
        return stat.kind == .file;
    }
};

const ParsedLiteral = struct {
    specifier: []const u8,
    next_index: usize,
};

fn collectEsmSpecifiers(allocator: Allocator, source: []const u8) ![]const []u8 {
    var specifiers: std.ArrayList([]u8) = .empty;
    errdefer {
        for (specifiers.items) |specifier| {
            allocator.free(specifier);
        }
        specifiers.deinit(allocator);
    }

    var dedup = std.StringHashMap(void).init(allocator);
    defer dedup.deinit();

    var cursor: usize = 0;
    while (cursor < source.len) {
        const current = source[cursor];

        if (current == '/') {
            if (cursor + 1 < source.len and source[cursor + 1] == '/') {
                cursor = skipLineComment(source, cursor);
                continue;
            }
            if (cursor + 1 < source.len and source[cursor + 1] == '*') {
                cursor = skipBlockComment(source, cursor);
                continue;
            }
        }

        if (current == '\'' or current == '"' or current == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        if (hasWordAt(source, cursor, "import")) {
            cursor = try parseImportSpecifier(allocator, source, cursor, &specifiers, &dedup);
            continue;
        }

        if (hasWordAt(source, cursor, "export")) {
            cursor = try parseExportSpecifier(allocator, source, cursor, &specifiers, &dedup);
            continue;
        }

        cursor += 1;
    }

    return specifiers.toOwnedSlice(allocator);
}

fn parseImportSpecifier(
    allocator: Allocator,
    source: []const u8,
    start_index: usize,
    specifiers: *std.ArrayList([]u8),
    dedup: *std.StringHashMap(void),
) !usize {
    var cursor = start_index + "import".len;
    skipTrivia(source, &cursor);
    if (cursor >= source.len) {
        return cursor;
    }

    if (source[cursor] == '.') {
        return cursor + 1;
    }

    if (parseQuotedSpecifier(source, cursor)) |literal| {
        try appendSpecifier(allocator, specifiers, dedup, literal.specifier);
        return literal.next_index;
    }

    if (source[cursor] == '(') {
        cursor += 1;
        skipTrivia(source, &cursor);
        if (parseQuotedSpecifier(source, cursor)) |literal| {
            try appendSpecifier(allocator, specifiers, dedup, literal.specifier);
            return literal.next_index;
        }
        return cursor;
    }

    while (cursor < source.len) {
        const current = source[cursor];

        if (current == ';') {
            return cursor + 1;
        }

        if (current == '/') {
            if (cursor + 1 < source.len and source[cursor + 1] == '/') {
                cursor = skipLineComment(source, cursor);
                continue;
            }
            if (cursor + 1 < source.len and source[cursor + 1] == '*') {
                cursor = skipBlockComment(source, cursor);
                continue;
            }
        }

        if (current == '\'' or current == '"' or current == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        if (hasWordAt(source, cursor, "from")) {
            var value_index = cursor + "from".len;
            skipTrivia(source, &value_index);
            if (parseQuotedSpecifier(source, value_index)) |literal| {
                try appendSpecifier(allocator, specifiers, dedup, literal.specifier);
                return literal.next_index;
            }
        }

        cursor += 1;
    }

    return cursor;
}

fn parseExportSpecifier(
    allocator: Allocator,
    source: []const u8,
    start_index: usize,
    specifiers: *std.ArrayList([]u8),
    dedup: *std.StringHashMap(void),
) !usize {
    var cursor = start_index + "export".len;

    while (cursor < source.len) {
        const current = source[cursor];

        if (current == ';') {
            return cursor + 1;
        }

        if (current == '/') {
            if (cursor + 1 < source.len and source[cursor + 1] == '/') {
                cursor = skipLineComment(source, cursor);
                continue;
            }
            if (cursor + 1 < source.len and source[cursor + 1] == '*') {
                cursor = skipBlockComment(source, cursor);
                continue;
            }
        }

        if (current == '\'' or current == '"' or current == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        if (hasWordAt(source, cursor, "from")) {
            var value_index = cursor + "from".len;
            skipTrivia(source, &value_index);
            if (parseQuotedSpecifier(source, value_index)) |literal| {
                try appendSpecifier(allocator, specifiers, dedup, literal.specifier);
                return literal.next_index;
            }
        }

        cursor += 1;
    }

    return cursor;
}

fn appendSpecifier(
    allocator: Allocator,
    specifiers: *std.ArrayList([]u8),
    dedup: *std.StringHashMap(void),
    specifier: []const u8,
) !void {
    if (specifier.len == 0 or dedup.contains(specifier)) {
        return;
    }

    const owned = try allocator.dupe(u8, specifier);
    errdefer allocator.free(owned);

    try dedup.put(owned, {});
    try specifiers.append(allocator, owned);
}

fn parseQuotedSpecifier(source: []const u8, start_index: usize) ?ParsedLiteral {
    if (start_index >= source.len) {
        return null;
    }

    const quote = source[start_index];
    if (quote != '\'' and quote != '"') {
        return null;
    }

    var index = start_index + 1;
    while (index < source.len) {
        const current = source[index];
        if (current == '\\') {
            if (index + 1 >= source.len) {
                return null;
            }
            index += 2;
            continue;
        }

        if (current == quote) {
            return .{
                .specifier = source[start_index + 1 .. index],
                .next_index = index + 1,
            };
        }

        index += 1;
    }

    return null;
}

fn skipTrivia(source: []const u8, index: *usize) void {
    while (index.* < source.len) {
        const current = source[index.*];
        if (std.ascii.isWhitespace(current)) {
            index.* += 1;
            continue;
        }

        if (current == '/' and index.* + 1 < source.len and source[index.* + 1] == '/') {
            index.* = skipLineComment(source, index.*);
            continue;
        }

        if (current == '/' and index.* + 1 < source.len and source[index.* + 1] == '*') {
            index.* = skipBlockComment(source, index.*);
            continue;
        }

        break;
    }
}

fn skipLineComment(source: []const u8, start_index: usize) usize {
    var index = start_index + 2;
    while (index < source.len and source[index] != '\n') {
        index += 1;
    }
    return index;
}

fn skipBlockComment(source: []const u8, start_index: usize) usize {
    var index = start_index + 2;
    while (index + 1 < source.len) {
        if (source[index] == '*' and source[index + 1] == '/') {
            return index + 2;
        }
        index += 1;
    }
    return source.len;
}

fn skipQuotedLiteral(source: []const u8, start_index: usize) usize {
    const quote = source[start_index];
    var index = start_index + 1;
    while (index < source.len) {
        const current = source[index];
        if (current == '\\') {
            if (index + 1 >= source.len) {
                return source.len;
            }
            index += 2;
            continue;
        }

        if (current == quote) {
            return index + 1;
        }

        index += 1;
    }
    return source.len;
}

fn hasWordAt(source: []const u8, index: usize, word: []const u8) bool {
    if (index + word.len > source.len) {
        return false;
    }

    if (!std.mem.eql(u8, source[index .. index + word.len], word)) {
        return false;
    }

    if (index > 0 and isIdentifierChar(source[index - 1])) {
        return false;
    }

    const end_index = index + word.len;
    if (end_index < source.len and isIdentifierChar(source[end_index])) {
        return false;
    }

    return true;
}

fn isIdentifierChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$';
}

pub fn runFiles(allocator: Allocator, io: std.Io, paths: []const []u8, setup_paths: []const []const u8) !Summary {
    var results: std.ArrayList(FileResult) = .empty;
    errdefer {
        for (results.items) |*item| {
            item.deinit(allocator);
        }
        results.deinit(allocator);
    }

    var totals = Summary{
        .files = &.{},
        .total_passed = 0,
        .total_failed = 0,
        .total_skipped = 0,
        .total_timed_out = 0,
        .total_collection_errors = 0,
    };

    for (paths) |path| {
        var file_result = try runSingleFile(allocator, io, path, setup_paths);
        errdefer file_result.deinit(allocator);

        totals.total_passed += file_result.passed;
        totals.total_failed += file_result.failed;
        totals.total_skipped += file_result.skipped;
        totals.total_timed_out += file_result.timed_out;
        totals.total_collection_errors += file_result.collection_errors;

        try results.append(allocator, file_result);
    }

    totals.files = try results.toOwnedSlice(allocator);
    return totals;
}

fn runSingleFile(allocator: Allocator, io: std.Io, path: []const u8, setup_paths: []const []const u8) !FileResult {
    const entry_module_id = canonicalizePath(allocator, io, path) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };
    defer allocator.free(entry_module_id);

    var setup_module_ids: std.ArrayList([]u8) = .empty;
    defer {
        for (setup_module_ids.items) |setup_module_id| {
            allocator.free(setup_module_id);
        }
        setup_module_ids.deinit(allocator);
    }

    for (setup_paths) |setup_path| {
        const setup_module_id = canonicalizePath(allocator, io, setup_path) catch |err| {
            return collectionFailureFromError(allocator, path, "collection failed", err);
        };
        setup_module_ids.append(allocator, setup_module_id) catch |err| {
            allocator.free(setup_module_id);
            return err;
        };
    }

    var vm = try Runtime.init(allocator);
    defer vm.deinit();

    vm.evalScript("<zig-runner-harness>", harness_source) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to initialize runner harness", err, &vm);
    };

    var module_loader_state = ModuleLoaderState.init(allocator, io);
    defer module_loader_state.deinit();

    vm.setModuleLoaderFunc(ModuleLoaderState, &module_loader_state, moduleNormalize, moduleLoad);

    for (setup_module_ids.items) |setup_module_id| {
        module_loader_state.preloadEntryGraph(setup_module_id) catch |err| {
            return collectionFailureFromError(allocator, path, "collection failed", err);
        };
    }

    module_loader_state.preloadEntryGraph(entry_module_id) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };

    for (setup_module_ids.items) |setup_module_id| {
        const setup_source = module_loader_state.loadModuleSource(setup_module_id) catch |err| {
            return collectionFailureFromError(allocator, path, "collection failed", err);
        };

        vm.evalModule(setup_module_id, setup_source) catch |err| {
            return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
        };
    }

    const entry_source = module_loader_state.loadModuleSource(entry_module_id) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };

    vm.evalModule(entry_module_id, entry_source) catch |err| {
        return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
    };

    vm.evalScript("<zig-runner-bootstrap>", run_bootstrap_source) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to start file execution", err, &vm);
    };

    const run_timeout_ms: i64 = 30_000;
    const start_ts = std.Io.Clock.Timestamp.now(io, .awake);
    while (!(vm.getGlobalBool("__zigDone") catch false)) {
        const elapsed_ms = start_ts.untilNow(io).raw.toMilliseconds();
        if (elapsed_ms > run_timeout_ms) {
            return .{
                .path = try allocator.dupe(u8, path),
                .passed = 0,
                .failed = 0,
                .skipped = 0,
                .timed_out = 1,
                .collection_errors = 0,
                .failure_report = try allocator.dupe(u8, "Runner timed out while waiting for async jobs."),
                .collection_report = null,
            };
        }

        if (vm.isJobPending()) {
            _ = vm.executePendingJob() catch |err| {
                return failureFromRuntimeException(allocator, path, "job execution failed", err, &vm);
            };
            continue;
        }

        return .{
            .path = try allocator.dupe(u8, path),
            .passed = 0,
            .failed = 1,
            .skipped = 0,
            .timed_out = 0,
            .collection_errors = 0,
            .failure_report = try allocator.dupe(u8, "Runner stalled with unresolved async work."),
            .collection_report = null,
        };
    }

    const run_error = vm.getGlobalStringDup("__zigRunError") catch try allocator.dupe(u8, "");
    if (run_error.len > 0) {
        return .{
            .path = try allocator.dupe(u8, path),
            .passed = 0,
            .failed = 1,
            .skipped = 0,
            .timed_out = 0,
            .collection_errors = 0,
            .failure_report = run_error,
            .collection_report = null,
        };
    }
    allocator.free(run_error);

    const passed_i32 = vm.getGlobalInt32("__zigPassed") catch 0;
    const failed_i32 = vm.getGlobalInt32("__zigFailed") catch 0;
    const skipped_i32 = vm.getGlobalInt32("__zigSkipped") catch 0;
    const timed_out_i32 = vm.getGlobalInt32("__zigTimedOut") catch 0;
    const collection_errors_i32 = vm.getGlobalInt32("__zigCollectionErrors") catch 0;

    const failures_text = vm.getGlobalStringDup("__zigFailuresText") catch try allocator.dupe(u8, "");
    const collection_text = vm.getGlobalStringDup("__zigCollectionText") catch try allocator.dupe(u8, "");

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = @intCast(@max(passed_i32, 0)),
        .failed = @intCast(@max(failed_i32, 0)),
        .skipped = @intCast(@max(skipped_i32, 0)),
        .timed_out = @intCast(@max(timed_out_i32, 0)),
        .collection_errors = @intCast(@max(collection_errors_i32, 0)),
        .failure_report = if (failures_text.len > 0) failures_text else blk: {
            allocator.free(failures_text);
            break :blk null;
        },
        .collection_report = if (collection_text.len > 0) collection_text else blk: {
            allocator.free(collection_text);
            break :blk null;
        },
    };
}

fn moduleNormalize(
    state_opt: ?*ModuleLoaderState,
    ctx: *ModuleContext,
    module_base_name: [:0]const u8,
    module_name: [:0]const u8,
) ?[*:0]u8 {
    const state = state_opt orelse return null;

    const resolved = state.normalizeSpecifier(module_base_name, module_name) catch {
        _ = quickjs.c.JS_ThrowReferenceError(ctx.cval(), "module resolution failed");
        return null;
    };
    defer state.allocator.free(resolved);

    return allocJsCString(ctx, resolved) orelse blk: {
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        break :blk null;
    };
}

fn moduleLoad(
    state_opt: ?*ModuleLoaderState,
    ctx: *ModuleContext,
    module_name: [:0]const u8,
) ?*ModuleDef {
    const state = state_opt orelse return null;
    const module_id: []const u8 = module_name;

    if (state.loaded_modules.get(module_id)) |existing| {
        return existing;
    }

    const source = state.loadModuleSource(module_id) catch {
        _ = quickjs.c.JS_ThrowReferenceError(ctx.cval(), "module loading failed");
        return null;
    };

    const source_z = state.allocator.dupeZ(u8, source) catch {
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        return null;
    };
    defer state.allocator.free(source_z);

    const compiled = ctx.eval(source_z[0..source.len], module_name, .{ .type = .module, .compile_only = true });
    if (compiled.isException()) {
        return null;
    }
    defer compiled.deinit(ctx);

    const module_ptr_any = quickjs.c.JS_VALUE_GET_PTR(compiled.cval()) orelse {
        _ = quickjs.c.JS_ThrowReferenceError(ctx.cval(), "compiled module missing");
        return null;
    };
    const module_ptr: *ModuleDef = @ptrCast(@alignCast(module_ptr_any));

    const key = state.allocator.dupe(u8, module_id) catch {
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        return null;
    };

    state.loaded_modules.put(key, module_ptr) catch {
        state.allocator.free(key);
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        return null;
    };

    return module_ptr;
}

fn allocJsCString(ctx: *ModuleContext, text: []const u8) ?[*:0]u8 {
    const raw = quickjs.c.js_malloc(ctx.cval(), text.len + 1) orelse return null;
    const bytes: [*]u8 = @ptrCast(raw);
    @memcpy(bytes[0..text.len], text);
    bytes[text.len] = 0;
    return @ptrCast(bytes);
}

fn shimModuleSource(module_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, module_name, bun_test_specifier)) {
        return bun_test_shim_source;
    }

    if (std.mem.eql(u8, module_name, react_specifier)) {
        return react_shim_source;
    }

    if (std.mem.eql(u8, module_name, react_dom_client_specifier)) {
        return react_dom_client_shim_source;
    }

    if (std.mem.eql(u8, module_name, testing_library_specifier)) {
        return testing_library_shim_source;
    }

    if (std.mem.eql(u8, module_name, vanilla_extract_css_specifier)) {
        return vanilla_extract_css_shim_source;
    }

    return null;
}

fn isRelativeSpecifier(specifier: []const u8) bool {
    return std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../");
}

fn canonicalizePath(allocator: Allocator, io: std.Io, path: []const u8) ![]u8 {
    const resolved = try std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator);
    defer allocator.free(resolved);
    return allocator.dupe(u8, resolved[0..resolved.len]);
}

fn failureFromRuntimeException(
    allocator: Allocator,
    path: []const u8,
    context: []const u8,
    runtime_error: anyerror,
    vm: *Runtime,
) !FileResult {
    var exception: ?Exception = null;
    if (runtime_error == error.EvaluationFailed or runtime_error == error.JobExecutionFailed) {
        exception = vm.takeException() catch null;
    }
    defer if (exception) |exc| exc.deinit(allocator);

    const message = if (exception) |exc|
        try formatExceptionText(allocator, context, exc)
    else
        try std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, @errorName(runtime_error) });

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = 0,
        .failed = 1,
        .skipped = 0,
        .timed_out = 0,
        .collection_errors = 0,
        .failure_report = message,
        .collection_report = null,
    };
}

fn collectionFailureFromRuntimeException(
    allocator: Allocator,
    path: []const u8,
    context: []const u8,
    runtime_error: anyerror,
    vm: *Runtime,
) !FileResult {
    var exception: ?Exception = null;
    if (runtime_error == error.EvaluationFailed or runtime_error == error.JobExecutionFailed) {
        exception = vm.takeException() catch null;
    }
    defer if (exception) |exc| exc.deinit(allocator);

    const message = if (exception) |exc|
        try formatExceptionText(allocator, context, exc)
    else
        try std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, @errorName(runtime_error) });

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = 0,
        .failed = 0,
        .skipped = 0,
        .timed_out = 0,
        .collection_errors = 1,
        .failure_report = null,
        .collection_report = message,
    };
}

fn collectionFailureFromError(
    allocator: Allocator,
    path: []const u8,
    context: []const u8,
    err: anyerror,
) !FileResult {
    const message = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, @errorName(err) });

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = 0,
        .failed = 0,
        .skipped = 0,
        .timed_out = 0,
        .collection_errors = 1,
        .failure_report = null,
        .collection_report = message,
    };
}

fn formatExceptionText(allocator: Allocator, context: []const u8, exception: Exception) ![]u8 {
    if (exception.stack) |stack| {
        return std.fmt.allocPrint(allocator, "{s}: {s}\n{s}", .{ context, exception.message, stack });
    }

    return std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, exception.message });
}

test "isRelativeSpecifier detects relative paths" {
    try std.testing.expect(isRelativeSpecifier("./foo"));
    try std.testing.expect(isRelativeSpecifier("../foo"));
    try std.testing.expect(!isRelativeSpecifier("foo"));
}

test "shimModuleSource resolves known shims" {
    try std.testing.expect(shimModuleSource("bun:test") != null);
    try std.testing.expect(shimModuleSource("react") != null);
    try std.testing.expect(shimModuleSource("react-dom/client") != null);
    try std.testing.expect(shimModuleSource("@testing-library/react") != null);
    try std.testing.expect(shimModuleSource("@vanilla-extract/css") != null);
    try std.testing.expect(shimModuleSource("not-a-shim") == null);
}

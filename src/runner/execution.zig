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
    transformed_sources: std.StringHashMap([]u8),

    fn init(allocator: Allocator, io: std.Io) ModuleLoaderState {
        return .{
            .allocator = allocator,
            .io = io,
            .loaded_modules = std.StringHashMap(*ModuleDef).init(allocator),
            .transformed_sources = std.StringHashMap([]u8).init(allocator),
        };
    }

    fn deinit(self: *ModuleLoaderState) void {
        var source_iterator = self.transformed_sources.iterator();
        while (source_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.transformed_sources.deinit();

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

        if (std.fs.path.isAbsolute(module_name)) {
            return self.resolveAbsolutePath(module_name);
        }

        if (isRelativeSpecifier(module_name)) {
            return self.resolveRelativePath(module_base_name, module_name);
        }

        return error.UnsupportedExternalModule;
    }

    fn loadModuleSource(self: *ModuleLoaderState, module_id: []const u8) ![]const u8 {
        if (shimModuleSource(module_id)) |shim_source| {
            return shim_source;
        }

        if (self.transformed_sources.get(module_id)) |cached| {
            return cached;
        }

        _ = transform.loaderForPath(module_id) orelse return error.UnsupportedModuleExtension;

        const output_path = try transform.buildModuleOutputPath(self.allocator, module_id);
        defer self.allocator.free(output_path);

        try transform.transformModuleToPath(self.allocator, self.io, module_id, output_path);

        const transformed = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            output_path,
            self.allocator,
            .limited(4 * 1024 * 1024),
        );

        const key = try self.allocator.dupe(u8, module_id);
        errdefer self.allocator.free(key);

        try self.transformed_sources.put(key, transformed);
        return self.transformed_sources.get(module_id).?;
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

    fn pathIsSupportedFile(self: *ModuleLoaderState, path: []const u8) bool {
        if (transform.loaderForPath(path) == null) {
            return false;
        }

        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return false;
        return stat.kind == .file;
    }
};

pub fn runFiles(allocator: Allocator, io: std.Io, paths: []const []u8) !Summary {
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
        var file_result = try runSingleFile(allocator, io, path);
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

fn runSingleFile(allocator: Allocator, io: std.Io, path: []const u8) !FileResult {
    const entry_module_id = canonicalizePath(allocator, io, path) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };
    defer allocator.free(entry_module_id);

    var vm = try Runtime.init(allocator);
    defer vm.deinit();

    vm.evalScript("<zig-runner-harness>", harness_source) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to initialize runner harness", err, &vm);
    };

    var module_loader_state = ModuleLoaderState.init(allocator, io);
    defer module_loader_state.deinit();

    vm.setModuleLoaderFunc(ModuleLoaderState, &module_loader_state, moduleNormalize, moduleLoad);

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
    try std.testing.expect(shimModuleSource("not-a-shim") == null);
}

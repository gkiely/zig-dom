const std = @import("std");
const runtime_pkg = @import("../runtime/runtime.zig");
const transform = @import("transform.zig");

const Allocator = std.mem.Allocator;
const Runtime = runtime_pkg.Runtime;
const Exception = runtime_pkg.Exception;

const harness_source = @embedFile("runner_harness.js");
const module_runtime_source =
    \\globalThis.__zigModuleExports = Object.create(null);
    \\globalThis.__zigBuiltinModule = function(id) {
    \\  if (id === "shim:bun:test") {
    \\    const mod = {
    \\      test: globalThis.test,
    \\      it: globalThis.it,
    \\      describe: globalThis.describe,
    \\      expect: globalThis.expect,
    \\      beforeAll: globalThis.beforeAll,
    \\      beforeEach: globalThis.beforeEach,
    \\      afterEach: globalThis.afterEach,
    \\      afterAll: globalThis.afterAll,
    \\    };
    \\    mod.default = mod;
    \\    mod.__esModule = true;
    \\    return mod;
    \\  }
    \\
    \\  if (id === "shim:react") {
    \\    const react = globalThis.React;
    \\    return Object.assign({}, react, {
    \\      default: react,
    \\      __esModule: true,
    \\    });
    \\  }
    \\
    \\  if (id === "shim:react-dom/client") {
    \\    const client = globalThis.ReactDOMClient;
    \\    return Object.assign({}, client, {
    \\      default: client,
    \\      __esModule: true,
    \\    });
    \\  }
    \\
    \\  if (id === "shim:@testing-library/react") {
    \\    const api = {
    \\      render: globalThis.render,
    \\      screen: globalThis.screen,
    \\      fireEvent: globalThis.fireEvent,
    \\    };
    \\    api.default = api;
    \\    api.__esModule = true;
    \\    return api;
    \\  }
    \\
    \\  return null;
    \\};
    \\globalThis.__zigRegisterModule = function(id, exports) {
    \\  globalThis.__zigModuleExports[id] = exports;
    \\};
    \\globalThis.__zigRequire = function(id) {
    \\  if (Object.prototype.hasOwnProperty.call(globalThis.__zigModuleExports, id)) {
    \\    return globalThis.__zigModuleExports[id];
    \\  }
    \\
    \\  const builtin = globalThis.__zigBuiltinModule(id);
    \\  if (builtin !== null) {
    \\    return builtin;
    \\  }
    \\
    \\  throw new Error(`Cannot resolve module: ${id}`);
    \\};
;
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

const shim_bun_test_id = "shim:bun:test";
const shim_react_id = "shim:react";
const shim_react_dom_client_id = "shim:react-dom/client";
const shim_testing_library_id = "shim:@testing-library/react";

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

const RequireCall = struct {
    specifier_start: usize,
    specifier_end: usize,
    specifier: []const u8,
};

const CachedModule = struct {
    id: []u8,
    source: []u8,
    dependencies: []const []u8,

    fn deinit(self: *CachedModule, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.source);
        for (self.dependencies) |dependency| {
            allocator.free(dependency);
        }
        allocator.free(self.dependencies);
    }
};

const ModuleCache = struct {
    allocator: Allocator,
    io: std.Io,
    modules: std.StringHashMap(CachedModule),

    fn init(allocator: Allocator, io: std.Io) ModuleCache {
        return .{
            .allocator = allocator,
            .io = io,
            .modules = std.StringHashMap(CachedModule).init(allocator),
        };
    }

    fn deinit(self: *ModuleCache) void {
        var iterator = self.modules.iterator();
        while (iterator.next()) |entry| {
            var module = entry.value_ptr.*;
            module.deinit(self.allocator);
        }
        self.modules.deinit();
    }

    fn getOrLoad(self: *ModuleCache, module_id: []const u8) !*const CachedModule {
        if (self.modules.getPtr(module_id)) |existing| {
            return existing;
        }

        var loaded = try self.loadModule(module_id);
        errdefer loaded.deinit(self.allocator);

        try self.modules.put(loaded.id, loaded);
        return self.modules.getPtr(module_id).?;
    }

    fn loadModule(self: *ModuleCache, module_id: []const u8) !CachedModule {
        if (isShimModuleId(module_id)) {
            return .{
                .id = try self.allocator.dupe(u8, module_id),
                .source = try self.allocator.dupe(u8, ""),
                .dependencies = try self.allocator.alloc([]u8, 0),
            };
        }

        const loader = transform.loaderForPath(module_id) orelse return error.UnsupportedModuleExtension;
        _ = loader;

        const output_path = try transform.buildModuleOutputPath(self.allocator, module_id);
        defer self.allocator.free(output_path);

        try transform.transformModuleToPath(self.allocator, self.io, module_id, output_path);

        const transformed = try std.Io.Dir.cwd().readFileAlloc(self.io, output_path, self.allocator, .limited(4 * 1024 * 1024));
        defer self.allocator.free(transformed);

        return self.buildCachedModuleFromSource(module_id, transformed);
    }

    fn buildCachedModuleFromSource(self: *ModuleCache, module_id: []const u8, source: []const u8) !CachedModule {
        const require_calls = try collectRequireCalls(self.allocator, source);
        defer self.allocator.free(require_calls);

        var dependencies: std.ArrayList([]u8) = .empty;
        errdefer {
            for (dependencies.items) |dependency| {
                self.allocator.free(dependency);
            }
            dependencies.deinit(self.allocator);
        }

        var resolved_specs = try self.allocator.alloc([]const u8, require_calls.len);
        defer self.allocator.free(resolved_specs);

        for (require_calls, 0..) |call, index| {
            var resolved = try self.resolveImport(module_id, call.specifier);
            if (findDependency(dependencies.items, resolved)) |existing| {
                self.allocator.free(resolved);
                resolved = existing;
            } else {
                try dependencies.append(self.allocator, resolved);
            }

            resolved_specs[index] = resolved;
        }

        const rewritten_source = if (require_calls.len == 0)
            try self.allocator.dupe(u8, source)
        else
            try rewriteRequireSpecifiers(self.allocator, source, require_calls, resolved_specs);

        return .{
            .id = try self.allocator.dupe(u8, module_id),
            .source = rewritten_source,
            .dependencies = try dependencies.toOwnedSlice(self.allocator),
        };
    }

    fn resolveImport(self: *ModuleCache, module_id: []const u8, specifier: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(specifier)) {
            return self.resolveAbsolutePath(specifier);
        }

        if (isRelativeSpecifier(specifier)) {
            return self.resolveRelativePath(module_id, specifier);
        }

        if (shimIdForSpecifier(specifier)) |shim_id| {
            return self.allocator.dupe(u8, shim_id);
        }

        return error.UnsupportedExternalModule;
    }

    fn resolveRelativePath(self: *ModuleCache, importer_path: []const u8, specifier: []const u8) ![]u8 {
        const importer_dir = std.fs.path.dirname(importer_path) orelse ".";
        const candidate = try std.fs.path.resolve(self.allocator, &.{ importer_dir, specifier });
        errdefer self.allocator.free(candidate);

        if (self.pathIsFile(candidate)) {
            _ = transform.loaderForPath(candidate) orelse return error.UnsupportedModuleExtension;
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

    fn resolveAbsolutePath(self: *ModuleCache, specifier: []const u8) ![]u8 {
        const candidate = try std.fs.path.resolve(self.allocator, &.{specifier});
        errdefer self.allocator.free(candidate);

        if (self.pathIsFile(candidate)) {
            _ = transform.loaderForPath(candidate) orelse return error.UnsupportedModuleExtension;
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

    fn resolvePathWithoutExtension(self: *ModuleCache, base_path: []const u8) !?[]u8 {
        const extensions = [_][]const u8{ ".ts", ".tsx", ".jsx", ".js" };

        for (extensions) |extension| {
            const candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_path, extension });
            if (self.pathIsFile(candidate)) {
                return candidate;
            }
            self.allocator.free(candidate);
        }

        for (extensions) |extension| {
            const candidate = try std.fmt.allocPrint(self.allocator, "{s}/index{s}", .{ base_path, extension });
            if (self.pathIsFile(candidate)) {
                return candidate;
            }
            self.allocator.free(candidate);
        }

        return null;
    }

    fn pathIsFile(self: *ModuleCache, path: []const u8) bool {
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

    var module_cache = ModuleCache.init(allocator, io);
    defer module_cache.deinit();

    var totals = Summary{
        .files = &.{},
        .total_passed = 0,
        .total_failed = 0,
        .total_skipped = 0,
        .total_timed_out = 0,
        .total_collection_errors = 0,
    };

    for (paths) |path| {
        var file_result = try runSingleFile(allocator, io, path, &module_cache);
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

fn runSingleFile(allocator: Allocator, io: std.Io, path: []const u8, module_cache: *ModuleCache) !FileResult {
    const module_entry_id = canonicalizePath(allocator, path) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };
    defer allocator.free(module_entry_id);

    var vm = try Runtime.init(allocator);
    defer vm.deinit();

    vm.evalScript("<zig-runner-harness>", harness_source) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to initialize runner harness", err, &vm);
    };

    vm.evalScript("<zig-module-runtime>", module_runtime_source) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to initialize module runtime", err, &vm);
    };

    const module_order = buildEvaluationOrder(allocator, module_cache, module_entry_id) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };
    defer allocator.free(module_order);

    for (module_order) |module_id| {
        if (isShimModuleId(module_id)) {
            continue;
        }

        const module = module_cache.getOrLoad(module_id) catch |err| {
            return collectionFailureFromError(allocator, path, "collection failed", err);
        };

        const define_script = buildModuleDefineScript(allocator, module) catch |err| {
            return collectionFailureFromError(allocator, path, "collection failed", err);
        };
        defer allocator.free(define_script);

        vm.evalScript(module.id, define_script) catch |err| {
            return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
        };
    }

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

fn buildEvaluationOrder(
    allocator: Allocator,
    module_cache: *ModuleCache,
    entry_module_id: []const u8,
) ![]const []const u8 {
    var order: std.ArrayList([]const u8) = .empty;
    errdefer order.deinit(allocator);

    var visiting = std.StringHashMap(void).init(allocator);
    defer visiting.deinit();

    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    try visitModule(&order, &visiting, &visited, module_cache, entry_module_id);
    return order.toOwnedSlice(allocator);
}

fn visitModule(
    order: *std.ArrayList([]const u8),
    visiting: *std.StringHashMap(void),
    visited: *std.StringHashMap(void),
    module_cache: *ModuleCache,
    module_id: []const u8,
) !void {
    if (visited.contains(module_id)) {
        return;
    }

    if (visiting.contains(module_id)) {
        return error.CyclicModuleDependency;
    }

    try visiting.put(module_id, {});
    defer _ = visiting.remove(module_id);

    const module = try module_cache.getOrLoad(module_id);
    for (module.dependencies) |dependency| {
        try visitModule(order, visiting, visited, module_cache, dependency);
    }

    try visited.put(module.id, {});
    try order.append(module_cache.allocator, module.id);
}

fn collectRequireCalls(allocator: Allocator, source: []const u8) ![]RequireCall {
    var calls: std.ArrayList(RequireCall) = .empty;
    errdefer calls.deinit(allocator);

    const token = "require(";
    var cursor: usize = 0;

    while (cursor < source.len) {
        const start = std.mem.indexOfPos(u8, source, cursor, token) orelse break;
        var arg_start = start + token.len;
        while (arg_start < source.len and std.ascii.isWhitespace(source[arg_start])) {
            arg_start += 1;
        }

        if (arg_start >= source.len) {
            break;
        }

        const quote = source[arg_start];
        if (quote != '\'' and quote != '"') {
            cursor = start + token.len;
            continue;
        }

        const spec_start = arg_start + 1;
        var spec_end = spec_start;
        while (spec_end < source.len) {
            if (source[spec_end] == '\\') {
                spec_end += 2;
                continue;
            }

            if (source[spec_end] == quote) {
                break;
            }

            spec_end += 1;
        }

        if (spec_end >= source.len) {
            break;
        }

        var close_paren = spec_end + 1;
        while (close_paren < source.len and std.ascii.isWhitespace(source[close_paren])) {
            close_paren += 1;
        }

        if (close_paren >= source.len or source[close_paren] != ')') {
            cursor = spec_end + 1;
            continue;
        }

        try calls.append(allocator, .{
            .specifier_start = spec_start,
            .specifier_end = spec_end,
            .specifier = source[spec_start..spec_end],
        });

        cursor = close_paren + 1;
    }

    return calls.toOwnedSlice(allocator);
}

fn rewriteRequireSpecifiers(
    allocator: Allocator,
    source: []const u8,
    require_calls: []const RequireCall,
    resolved_specs: []const []const u8,
) ![]u8 {
    var rewritten: std.ArrayList(u8) = .empty;
    errdefer rewritten.deinit(allocator);

    var cursor: usize = 0;
    for (require_calls, 0..) |call, index| {
        try rewritten.appendSlice(allocator, source[cursor..call.specifier_start]);
        try rewritten.appendSlice(allocator, resolved_specs[index]);
        cursor = call.specifier_end;
    }
    try rewritten.appendSlice(allocator, source[cursor..]);

    return rewritten.toOwnedSlice(allocator);
}

fn findDependency(dependencies: []const []u8, candidate: []const u8) ?[]u8 {
    for (dependencies) |dependency| {
        if (std.mem.eql(u8, dependency, candidate)) {
            return dependency;
        }
    }

    return null;
}

fn isRelativeSpecifier(specifier: []const u8) bool {
    return std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../");
}

fn shimIdForSpecifier(specifier: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, specifier, "bun:test")) {
        return shim_bun_test_id;
    }

    if (std.mem.eql(u8, specifier, "react")) {
        return shim_react_id;
    }

    if (std.mem.eql(u8, specifier, "react-dom/client")) {
        return shim_react_dom_client_id;
    }

    if (std.mem.eql(u8, specifier, "@testing-library/react")) {
        return shim_testing_library_id;
    }

    return null;
}

fn isShimModuleId(module_id: []const u8) bool {
    if (std.mem.eql(u8, module_id, shim_bun_test_id)) {
        return true;
    }

    if (std.mem.eql(u8, module_id, shim_react_id)) {
        return true;
    }

    if (std.mem.eql(u8, module_id, shim_react_dom_client_id)) {
        return true;
    }

    if (std.mem.eql(u8, module_id, shim_testing_library_id)) {
        return true;
    }

    return false;
}

fn buildModuleDefineScript(allocator: Allocator, module: *const CachedModule) ![]u8 {
    const id_literal = try toJsStringLiteral(allocator, module.id);
    defer allocator.free(id_literal);

    return std.fmt.allocPrint(
        allocator,
        "(() => {{\nconst module = {{ exports: {{}} }};\nconst exports = module.exports;\nconst require = globalThis.__zigRequire;\n{s}\nglobalThis.__zigRegisterModule({s}, module.exports);\n}})();",
        .{ module.source, id_literal },
    );
}

fn toJsStringLiteral(allocator: Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.append(allocator, '"');
    for (input) |char| {
        switch (char) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, char),
        }
    }
    try out.append(allocator, '"');

    return out.toOwnedSlice(allocator);
}

fn canonicalizePath(allocator: Allocator, path: []const u8) ![]u8 {
    return std.fs.path.resolve(allocator, &.{path});
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

test "collectRequireCalls finds static requires" {
    const allocator = std.testing.allocator;
    const source =
        \\const a = require("./alpha");
        \\const b = require('@testing-library/react');
    ;

    const calls = try collectRequireCalls(allocator, source);
    defer allocator.free(calls);

    try std.testing.expectEqual(@as(usize, 2), calls.len);
    try std.testing.expectEqualStrings("./alpha", calls[0].specifier);
    try std.testing.expectEqualStrings("@testing-library/react", calls[1].specifier);
}

test "rewriteRequireSpecifiers updates module ids" {
    const allocator = std.testing.allocator;
    const source =
        \\const dep = require("./dep");
        \\const shim = require("bun:test");
    ;

    const calls = try collectRequireCalls(allocator, source);
    defer allocator.free(calls);

    const rewritten = try rewriteRequireSpecifiers(
        allocator,
        source,
        calls,
        &.{ "/abs/dep.ts", "shim:bun:test" },
    );
    defer allocator.free(rewritten);

    try std.testing.expect(std.mem.indexOf(u8, rewritten, "require(\"/abs/dep.ts\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "require(\"shim:bun:test\")") != null);
}

test "shimIdForSpecifier resolves known shims" {
    try std.testing.expectEqualStrings(shim_bun_test_id, shimIdForSpecifier("bun:test").?);
    try std.testing.expectEqualStrings(shim_react_dom_client_id, shimIdForSpecifier("react-dom/client").?);
    try std.testing.expectEqualStrings(shim_testing_library_id, shimIdForSpecifier("@testing-library/react").?);
    try std.testing.expect(shimIdForSpecifier("not-a-shim") == null);
}

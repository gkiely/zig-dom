const std = @import("std");
const quickjs = @import("quickjs");

const Allocator = std.mem.Allocator;
const DEFAULT_TIMEOUT_MS: i64 = 5000;

pub const HostRunnerError = error{ OutOfMemory, JSError };

var active_runner: ?*HostRunner = null;

const HookKind = enum { beforeAll, beforeEach, afterEach, afterAll };

const Hook = struct {
    callback: quickjs.Value,
    timeout_ms: i64,

    fn deinit(self: *Hook, rt: *quickjs.Runtime) void {
        self.callback.deinitRT(rt);
    }
};

const TestEntry = struct {
    name: []u8,
    callback: quickjs.Value,
    scope: *Scope,
    skip: bool,
    only: bool,
    todo: bool,
    timeout_ms: i64,

    fn deinit(self: *TestEntry, allocator: Allocator, rt: *quickjs.Runtime) void {
        allocator.free(self.name);
        if (!self.todo) self.callback.deinitRT(rt);
    }
};

const Entry = union(enum) {
    scope: *Scope,
    case: *TestEntry,
};

const Scope = struct {
    name: []u8,
    parent: ?*Scope,
    skip: bool,
    before_all: std.ArrayList(Hook) = .empty,
    before_each: std.ArrayList(Hook) = .empty,
    after_each: std.ArrayList(Hook) = .empty,
    after_all: std.ArrayList(Hook) = .empty,
    entries: std.ArrayList(Entry) = .empty,

    fn deinit(self: *Scope, allocator: Allocator, rt: *quickjs.Runtime) void {
        allocator.free(self.name);
        for (self.before_all.items) |*hook| hook.deinit(rt);
        for (self.before_each.items) |*hook| hook.deinit(rt);
        for (self.after_each.items) |*hook| hook.deinit(rt);
        for (self.after_all.items) |*hook| hook.deinit(rt);
        self.before_all.deinit(allocator);
        self.before_each.deinit(allocator);
        self.after_each.deinit(allocator);
        self.after_all.deinit(allocator);
        for (self.entries.items) |entry| switch (entry) {
            .scope => |scope| {
                scope.deinit(allocator, rt);
                allocator.destroy(scope);
            },
            .case => |test_entry| {
                test_entry.deinit(allocator, rt);
                allocator.destroy(test_entry);
            },
        };
        self.entries.deinit(allocator);
    }
};

const Failure = struct {
    name: []u8,
    message: []u8,
    timeout: bool,

    fn deinit(self: *Failure, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.message);
    }
};

const RunResult = struct {
    passed: i32 = 0,
    failed: i32 = 0,
    skipped: i32 = 0,
    timed_out: i32 = 0,
    failures: std.ArrayList(Failure) = .empty,
};

const CallbackOutcome = struct {
    ok: bool,
    timeout: bool = false,
    elapsed_ms: i64 = 0,
    error_text: ?[]u8 = null,
};

pub const HostRunner = struct {
    allocator: Allocator,
    rt: *quickjs.Runtime,
    ctx: *quickjs.Context,
    root_scope: *Scope,
    active_scope: *Scope,
    collection_errors: std.ArrayList([]u8) = .empty,
    registered_test_count: i32 = 0,

    pub fn init(allocator: Allocator, rt: *quickjs.Runtime, ctx: *quickjs.Context) HostRunnerError!*HostRunner {
        const runner = allocator.create(HostRunner) catch return error.OutOfMemory;
        errdefer allocator.destroy(runner);
        const root = allocator.create(Scope) catch return error.OutOfMemory;
        errdefer allocator.destroy(root);
        root.* = .{
            .name = allocator.dupe(u8, "<root>") catch return error.OutOfMemory,
            .parent = null,
            .skip = false,
        };
        runner.* = .{
            .allocator = allocator,
            .rt = rt,
            .ctx = ctx,
            .root_scope = root,
            .active_scope = root,
        };
        active_runner = runner;
        try runner.installGlobals();
        return runner;
    }

    pub fn deinit(self: *HostRunner) void {
        if (active_runner == self) active_runner = null;
        self.root_scope.deinit(self.allocator, self.rt);
        self.allocator.destroy(self.root_scope);
        for (self.collection_errors.items) |item| self.allocator.free(item);
        self.collection_errors.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn installGlobals(self: *HostRunner) HostRunnerError!void {
        const ctx = self.ctx;
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);

        const test_fn = quickjs.Value.initCFunction(ctx, jsTest, "test", 3);
        if (test_fn.isException()) return error.JSError;
        try setFunction(ctx, test_fn, "skip", jsTestSkip, 3);
        try setFunction(ctx, test_fn, "only", jsTestOnly, 3);
        try setFunction(ctx, test_fn, "todo", jsTestTodo, 1);

        const describe_fn = quickjs.Value.initCFunction(ctx, jsDescribe, "describe", 2);
        if (describe_fn.isException()) return error.JSError;
        try setFunction(ctx, describe_fn, "skip", jsDescribeSkip, 2);

        global.setPropertyStr(ctx, "test", test_fn.dup(ctx)) catch return error.JSError;
        global.setPropertyStr(ctx, "it", test_fn) catch return error.JSError;
        global.setPropertyStr(ctx, "describe", describe_fn) catch return error.JSError;
        try self.installEachHelpers();
        try setFunction(ctx, global, "beforeAll", jsBeforeAll, 1);
        try setFunction(ctx, global, "beforeEach", jsBeforeEach, 1);
        try setFunction(ctx, global, "afterEach", jsAfterEach, 1);
        try setFunction(ctx, global, "afterAll", jsAfterAll, 1);

        const runner_obj = quickjs.Value.initObject(ctx);
        if (runner_obj.isException()) return error.JSError;
        try setFunction(ctx, runner_obj, "run", jsRun, 0);
        global.setPropertyStr(ctx, "__zigRunner", runner_obj) catch return error.JSError;
    }

    fn installEachHelpers(self: *HostRunner) HostRunnerError!void {
        const source =
            \\(() => {
            \\  const formatName = (name, row, index) => {
            \\    if (typeof name !== "string") return String(name);
            \\    let out = name.replace(/%#/g, String(index));
            \\    if (Array.isArray(row)) {
            \\      for (const value of row) out = out.replace(/%[sdifoOj]/, String(value));
            \\    } else {
            \\      out = out.replace(/%[sdifoOj]/, String(row));
            \\    }
            \\    return out;
            \\  };
            \\  const install = (target) => {
            \\    target.each = (table) => (name, callback, timeout) => {
            \\      const rows = Array.from(table ?? []);
            \\      for (let index = 0; index < rows.length; index++) {
            \\        const row = rows[index];
            \\        target(formatName(name, row, index), () => Array.isArray(row) ? callback(...row) : callback(row), timeout);
            \\      }
            \\    };
            \\  };
            \\  install(globalThis.test);
            \\  install(globalThis.it);
            \\  install(globalThis.test.skip);
            \\  install(globalThis.test.only);
            \\  install(globalThis.it.skip);
            \\  install(globalThis.it.only);
            \\})();
        ;
        const result = self.ctx.eval(source, "<zig-runner-each>", .{});
        defer result.deinit(self.ctx);
        if (result.isException()) return error.JSError;
    }

    fn currentScopeName(self: *HostRunner) ![]u8 {
        return self.scopePath(self.active_scope);
    }

    fn scopePath(self: *HostRunner, scope: *Scope) ![]u8 {
        var parts: std.ArrayList([]const u8) = .empty;
        defer parts.deinit(self.allocator);
        var cursor: ?*Scope = scope;
        while (cursor) |item| {
            if (item.parent != null) try parts.append(self.allocator, item.name);
            cursor = item.parent;
        }
        if (parts.items.len == 0) return self.allocator.dupe(u8, "");
        var total: usize = 0;
        for (parts.items) |part| total += part.len;
        total += (parts.items.len - 1) * 3;
        var out = try self.allocator.alloc(u8, total);
        var offset: usize = 0;
        var index: usize = parts.items.len;
        while (index > 0) {
            index -= 1;
            const part = parts.items[index];
            if (offset > 0) {
                @memcpy(out[offset .. offset + 3], " > ");
                offset += 3;
            }
            @memcpy(out[offset .. offset + part.len], part);
            offset += part.len;
        }
        return out;
    }

    fn testPath(self: *HostRunner, test_entry: *TestEntry) ![]u8 {
        const scope_path = try self.scopePath(test_entry.scope);
        defer self.allocator.free(scope_path);
        if (scope_path.len == 0) return self.allocator.dupe(u8, test_entry.name);
        return std.fmt.allocPrint(self.allocator, "{s} > {s}", .{ scope_path, test_entry.name });
    }

    fn pushCollectionError(self: *HostRunner, context: []const u8, error_text: []const u8) void {
        const message = std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ context, error_text }) catch return;
        self.collection_errors.append(self.allocator, message) catch {
            self.allocator.free(message);
        };
    }

    fn registerHook(self: *HostRunner, kind: HookKind, args: []const quickjs.c.JSValue) void {
        const callback = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
        if (!callback.isFunction(self.ctx)) {
            const scope_name = self.currentScopeName() catch return;
            defer self.allocator.free(scope_name);
            self.pushCollectionError(scope_name, "Hook callback must be a function");
            return;
        }
        const hook = Hook{ .callback = callback.dup(self.ctx), .timeout_ms = DEFAULT_TIMEOUT_MS };
        switch (kind) {
            .beforeAll => self.active_scope.before_all.append(self.allocator, hook) catch {},
            .beforeEach => self.active_scope.before_each.append(self.allocator, hook) catch {},
            .afterEach => self.active_scope.after_each.append(self.allocator, hook) catch {},
            .afterAll => self.active_scope.after_all.append(self.allocator, hook) catch {},
        }
    }

    fn registerTest(self: *HostRunner, args: []const quickjs.c.JSValue, skip: bool, only: bool, todo: bool) void {
        const name_value = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
        const name = self.valueToOwnedString(name_value) catch {
            self.pushCollectionError("<root>", "Test name must be a non-empty string");
            return;
        };
        errdefer self.allocator.free(name);
        if (name.len == 0) {
            self.allocator.free(name);
            const scope_name = self.currentScopeName() catch return;
            defer self.allocator.free(scope_name);
            self.pushCollectionError(scope_name, "Test name must be a non-empty string");
            return;
        }

        const callback = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
        if (!todo and !callback.isFunction(self.ctx)) {
            const fake = TestEntry{ .name = name, .callback = quickjs.Value.undefined, .scope = self.active_scope, .skip = false, .only = false, .todo = true, .timeout_ms = DEFAULT_TIMEOUT_MS };
            const path = self.testPath(@constCast(&fake)) catch name;
            defer if (path.ptr != name.ptr) self.allocator.free(path);
            self.pushCollectionError(path, "Test callback must be a function");
            self.allocator.free(name);
            return;
        }

        const entry = self.allocator.create(TestEntry) catch {
            self.allocator.free(name);
            return;
        };
        entry.* = .{
            .name = name,
            .callback = if (todo) quickjs.Value.undefined else callback.dup(self.ctx),
            .scope = self.active_scope,
            .skip = self.active_scope.skip or skip or todo,
            .only = only,
            .todo = todo,
            .timeout_ms = self.readTimeout(args),
        };
        self.active_scope.entries.append(self.allocator, .{ .case = entry }) catch {
            entry.deinit(self.allocator, self.rt);
            self.allocator.destroy(entry);
            return;
        };
        self.registered_test_count += 1;
    }

    fn registerDescribe(self: *HostRunner, args: []const quickjs.c.JSValue, skip: bool) void {
        const name_value = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
        const name = self.valueToOwnedString(name_value) catch {
            self.pushCollectionError("<root>", "Describe name must be a non-empty string");
            return;
        };
        errdefer self.allocator.free(name);
        const callback = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
        if (!callback.isFunction(self.ctx)) {
            self.pushCollectionError(name, "Describe callback must be a function");
            self.allocator.free(name);
            return;
        }
        const child = self.allocator.create(Scope) catch {
            self.allocator.free(name);
            return;
        };
        child.* = .{ .name = name, .parent = self.active_scope, .skip = self.active_scope.skip or skip };
        self.active_scope.entries.append(self.allocator, .{ .scope = child }) catch {
            child.deinit(self.allocator, self.rt);
            self.allocator.destroy(child);
            return;
        };
        const previous = self.active_scope;
        self.active_scope = child;
        const result = callback.call(self.ctx, quickjs.Value.undefined, &.{});
        defer result.deinit(self.ctx);
        if (result.isException()) {
            const err = self.takeExceptionText();
            defer self.allocator.free(err);
            const path = self.scopePath(child) catch child.name;
            defer if (path.ptr != child.name.ptr) self.allocator.free(path);
            self.pushCollectionError(path, err);
        }
        self.active_scope = previous;
    }

    fn run(self: *HostRunner) !void {
        var result = RunResult{};
        defer {
            for (result.failures.items) |*failure| failure.deinit(self.allocator);
            result.failures.deinit(self.allocator);
        }

        const only_mode = self.hasOnly(self.root_scope);
        const has_runnable = self.hasRunnableTest(self.root_scope, only_mode);
        try self.runScope(self.root_scope, &result, only_mode);
        try self.publishResult(&result, only_mode, has_runnable);
    }

    fn hasOnly(self: *HostRunner, scope: *Scope) bool {
        for (scope.entries.items) |entry| switch (entry) {
            .case => |test_entry| if (test_entry.only) return true,
            .scope => |child| if (self.hasOnly(child)) return true,
        };
        return false;
    }

    fn hasRunnableTest(self: *HostRunner, scope: *Scope, only_mode: bool) bool {
        for (scope.entries.items) |entry| switch (entry) {
            .case => |test_entry| {
                if (test_entry.todo or test_entry.skip) continue;
                if (only_mode and !test_entry.only) continue;
                return true;
            },
            .scope => |child| if (self.hasRunnableTest(child, only_mode)) return true,
        };
        return false;
    }

    fn runScope(self: *HostRunner, scope: *Scope, result: *RunResult, only_mode: bool) !void {
        if (!self.hasRunnableTest(scope, only_mode)) return;
        const before_all = try self.runHookList(scope.before_all.items, DEFAULT_TIMEOUT_MS);
        defer if (before_all.error_text) |text| self.allocator.free(text);
        if (!before_all.ok) {
            try self.failScopeTree(scope, result, only_mode, before_all.error_text orelse "beforeAll failed");
            const after_all = try self.runHookList(scope.after_all.items, DEFAULT_TIMEOUT_MS);
            defer if (after_all.error_text) |text| self.allocator.free(text);
            if (!after_all.ok) {
                const scope_name = try self.scopePath(scope);
                defer self.allocator.free(scope_name);
                try self.addFailure(result, scope_name, after_all.error_text orelse "afterAll failed", after_all.timeout);
            }
            return;
        }
        for (scope.entries.items) |entry| switch (entry) {
            .case => |test_entry| try self.runTestEntry(test_entry, result, only_mode),
            .scope => |child| try self.runScope(child, result, only_mode),
        };
        const after_all = try self.runHookList(scope.after_all.items, DEFAULT_TIMEOUT_MS);
        defer if (after_all.error_text) |text| self.allocator.free(text);
        if (!after_all.ok) {
            const scope_name = try self.scopePath(scope);
            defer self.allocator.free(scope_name);
            try self.addFailure(result, scope_name, after_all.error_text orelse "afterAll failed", after_all.timeout);
        }
    }

    fn runTestEntry(self: *HostRunner, test_entry: *TestEntry, result: *RunResult, only_mode: bool) !void {
        const full_name = try self.testPath(test_entry);
        defer self.allocator.free(full_name);
        if (test_entry.todo or test_entry.skip or (only_mode and !test_entry.only)) {
            result.skipped += 1;
            return;
        }

        var before_each: std.ArrayList(Hook) = .empty;
        defer before_each.deinit(self.allocator);
        var after_each: std.ArrayList(Hook) = .empty;
        defer after_each.deinit(self.allocator);
        try self.collectBeforeEach(test_entry.scope, &before_each);
        try self.collectAfterEach(test_entry.scope, &after_each);

        const before_outcome = try self.runHookList(before_each.items, test_entry.timeout_ms);
        defer if (before_outcome.error_text) |text| self.allocator.free(text);
        if (!before_outcome.ok) {
            const name = try std.fmt.allocPrint(self.allocator, "{s} (beforeEach)", .{full_name});
            defer self.allocator.free(name);
            try self.addFailure(result, name, before_outcome.error_text orelse "beforeEach failed", before_outcome.timeout);
            _ = try self.runHookList(after_each.items, test_entry.timeout_ms);
            return;
        }

        const test_outcome = try self.invokeCallback(test_entry.callback, test_entry.timeout_ms);
        defer if (test_outcome.error_text) |text| self.allocator.free(text);
        const after_outcome = try self.runHookList(after_each.items, test_entry.timeout_ms);
        defer if (after_outcome.error_text) |text| self.allocator.free(text);

        if (!test_outcome.ok) {
            try self.addFailure(result, full_name, test_outcome.error_text orelse "Test failed", test_outcome.timeout);
            if (!after_outcome.ok) {
                const name = try std.fmt.allocPrint(self.allocator, "{s} (afterEach)", .{full_name});
                defer self.allocator.free(name);
                try self.addFailure(result, name, after_outcome.error_text orelse "afterEach failed", after_outcome.timeout);
            }
            return;
        }
        if (!after_outcome.ok) {
            const name = try std.fmt.allocPrint(self.allocator, "{s} (afterEach)", .{full_name});
            defer self.allocator.free(name);
            try self.addFailure(result, name, after_outcome.error_text orelse "afterEach failed", after_outcome.timeout);
            return;
        }
        result.passed += 1;
    }

    fn collectBeforeEach(self: *HostRunner, scope: *Scope, out: *std.ArrayList(Hook)) !void {
        if (scope.parent) |parent| try self.collectBeforeEach(parent, out);
        try out.appendSlice(self.allocator, scope.before_each.items);
    }

    fn collectAfterEach(self: *HostRunner, scope: *Scope, out: *std.ArrayList(Hook)) !void {
        try out.appendSlice(self.allocator, scope.after_each.items);
        if (scope.parent) |parent| try self.collectAfterEach(parent, out);
    }

    fn runHookList(self: *HostRunner, hooks: []const Hook, timeout_ms: i64) !CallbackOutcome {
        for (hooks) |hook| {
            const outcome = try self.invokeCallback(hook.callback, if (hook.timeout_ms > 0) hook.timeout_ms else timeout_ms);
            if (!outcome.ok) return outcome;
        }
        return .{ .ok = true };
    }

    fn invokeCallback(self: *HostRunner, callback: quickjs.Value, timeout_ms: i64) !CallbackOutcome {
        const result = callback.call(self.ctx, quickjs.Value.undefined, &.{});
        defer result.deinit(self.ctx);
        if (result.isException()) {
            return .{ .ok = false, .error_text = self.takeExceptionText() };
        }
        if (result.isPromise()) {
            var iterations: usize = 0;
            while (result.promiseState(self.ctx) == .pending) : (iterations += 1) {
                if (!self.rt.isJobPending()) break;
                _ = self.rt.executePendingJob() catch return .{ .ok = false, .error_text = self.takeExceptionText() };
                if (iterations > 100_000) break;
            }
            switch (result.promiseState(self.ctx)) {
                .fulfilled => {},
                .rejected => {
                    const rejection = result.promiseResult(self.ctx);
                    defer rejection.deinit(self.ctx);
                    return .{ .ok = false, .error_text = try self.formatErrorValue(rejection) };
                },
                .pending => return .{ .ok = false, .timeout = true, .error_text = try std.fmt.allocPrint(self.allocator, "Exceeded timeout of {d}ms", .{timeout_ms}) },
                .not_a_promise => {},
            }
        }
        return .{ .ok = true };
    }

    fn failScopeTree(self: *HostRunner, scope: *Scope, result: *RunResult, only_mode: bool, message: []const u8) !void {
        for (scope.entries.items) |entry| switch (entry) {
            .case => |test_entry| {
                if (test_entry.todo or test_entry.skip or (only_mode and !test_entry.only)) continue;
                const path = try self.testPath(test_entry);
                defer self.allocator.free(path);
                const name = try std.fmt.allocPrint(self.allocator, "{s} (beforeAll)", .{path});
                defer self.allocator.free(name);
                try self.addFailure(result, name, message, false);
            },
            .scope => |child| try self.failScopeTree(child, result, only_mode, message),
        };
    }

    fn addFailure(self: *HostRunner, result: *RunResult, name: []const u8, error_text: []const u8, timeout: bool) !void {
        try result.failures.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .message = try self.allocator.dupe(u8, error_text),
            .timeout = timeout,
        });
        result.failed += 1;
        if (timeout) result.timed_out += 1;
    }

    fn publishResult(self: *HostRunner, result: *RunResult, only_mode: bool, has_runnable: bool) !void {
        const ctx = self.ctx;
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        global.setPropertyStr(ctx, "__zigPassed", quickjs.Value.initInt32(result.passed)) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigFailed", quickjs.Value.initInt32(result.failed)) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigSkipped", quickjs.Value.initInt32(result.skipped)) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigTimedOut", quickjs.Value.initInt32(result.timed_out)) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigCollectionErrors", quickjs.Value.initInt32(@intCast(self.collection_errors.items.len))) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigRegisteredTests", quickjs.Value.initInt32(self.registered_test_count)) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigOnlyMode", quickjs.Value.initBool(only_mode)) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigHasRunnable", quickjs.Value.initBool(has_runnable)) catch return error.JSError;
        const failures_text = try self.buildFailuresText(result.failures.items);
        defer self.allocator.free(failures_text);
        const collection_text = try self.buildCollectionText();
        defer self.allocator.free(collection_text);
        global.setPropertyStr(ctx, "__zigFailuresText", quickjs.Value.initStringLen(ctx, failures_text)) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigCollectionText", quickjs.Value.initStringLen(ctx, collection_text)) catch return error.JSError;
    }

    fn buildFailuresText(self: *HostRunner, failures: []const Failure) ![]u8 {
        var builder: std.ArrayList(u8) = .empty;
        for (failures, 0..) |failure, index| {
            if (index > 0) try builder.appendSlice(self.allocator, "\n\n");
            try builder.appendSlice(self.allocator, failure.name);
            try builder.append(self.allocator, '\n');
            try builder.appendSlice(self.allocator, failure.message);
        }
        return builder.toOwnedSlice(self.allocator);
    }

    fn buildCollectionText(self: *HostRunner) ![]u8 {
        var builder: std.ArrayList(u8) = .empty;
        for (self.collection_errors.items, 0..) |item, index| {
            if (index > 0) try builder.appendSlice(self.allocator, "\n\n");
            try builder.appendSlice(self.allocator, item);
        }
        return builder.toOwnedSlice(self.allocator);
    }

    fn valueToOwnedString(self: *HostRunner, value: quickjs.Value) ![]u8 {
        const text = value.toCStringLen(self.ctx) orelse return error.OutOfMemory;
        defer self.ctx.freeCString(text.ptr);
        return self.allocator.dupe(u8, text.ptr[0..text.len]);
    }

    fn readTimeout(self: *HostRunner, args: []const quickjs.c.JSValue) i64 {
        if (args.len < 3) return DEFAULT_TIMEOUT_MS;
        const options = quickjs.Value.fromCVal(args[2]);
        if (!options.isObject()) return DEFAULT_TIMEOUT_MS;
        const timeout = options.getPropertyStr(self.ctx, "timeout");
        defer timeout.deinit(self.ctx);
        if (timeout.isException()) return DEFAULT_TIMEOUT_MS;
        const value = timeout.toInt64(self.ctx) catch return DEFAULT_TIMEOUT_MS;
        return if (value > 0) value else DEFAULT_TIMEOUT_MS;
    }

    fn takeExceptionText(self: *HostRunner) []u8 {
        const exception = self.ctx.getException();
        defer exception.deinit(self.ctx);
        return self.formatErrorValue(exception) catch self.allocator.dupe(u8, "Unknown error") catch unreachable;
    }

    fn formatErrorValue(self: *HostRunner, value: quickjs.Value) ![]u8 {
        const stack = value.getPropertyStr(self.ctx, "stack");
        defer stack.deinit(self.ctx);
        if (!stack.isException() and !stack.isUndefined() and !stack.isNull()) {
            return self.valueToOwnedString(stack);
        }
        return self.valueToOwnedString(value);
    }
};

fn jsTest(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerTest(args, false, false, false);
    return quickjs.Value.undefined;
}

fn jsTestSkip(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerTest(args, true, false, false);
    return quickjs.Value.undefined;
}

fn jsTestOnly(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerTest(args, false, true, false);
    return quickjs.Value.undefined;
}

fn jsTestTodo(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerTest(args, false, false, true);
    return quickjs.Value.undefined;
}

fn jsDescribe(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerDescribe(args, false);
    return quickjs.Value.undefined;
}

fn jsDescribeSkip(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerDescribe(args, true);
    return quickjs.Value.undefined;
}

fn jsBeforeAll(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerHook(.beforeAll, args);
    return quickjs.Value.undefined;
}

fn jsBeforeEach(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerHook(.beforeEach, args);
    return quickjs.Value.undefined;
}

fn jsAfterEach(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerHook(.afterEach, args);
    return quickjs.Value.undefined;
}

fn jsAfterAll(_: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.registerHook(.afterAll, args);
    return quickjs.Value.undefined;
}

fn jsRun(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    if (active_runner) |runner| runner.run() catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn setFunction(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) HostRunnerError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

const std = @import("std");
const quickjs = @import("quickjs");
const reporter = @import("../runner/reporter.zig");
const zig_dom = @import("../dom/dom.zig");
const platform = @import("platform.zig");

const Allocator = std.mem.Allocator;
const DEFAULT_TIMEOUT_MS: i64 = 5000;

pub const HostRunnerError = error{ OutOfMemory, JSError };

var active_runner: ?*HostRunner = null;

const HookKind = enum { beforeAll, beforeEach, afterEach, afterAll };

const RunnerPerfStats = struct {
    tests: u64 = 0,
    before_each_ns: i128 = 0,
    body_ns: i128 = 0,
    after_each_ns: i128 = 0,
    restore_spies_ns: i128 = 0,
    pending_jobs_ns: i128 = 0,
    timer_turns_ns: i128 = 0,
    promise_iterations: u64 = 0,
    pending_jobs: u64 = 0,
    timer_turns: u64 = 0,
    due_timer_turns: u64 = 0,
};

var runner_perf_stats = RunnerPerfStats{};
var runner_profile_enabled: ?bool = null;
var runner_profile_tests_enabled: ?bool = null;

fn runnerProfileEnabled() bool {
    if (runner_profile_enabled) |enabled| return enabled;
    const raw = std.c.getenv("ZIG_DOM_PROFILE_RUNNER");
    const enabled = if (raw) |value| !std.mem.eql(u8, std.mem.span(value), "0") else false;
    runner_profile_enabled = enabled;
    return enabled;
}

fn runnerProfileTestsEnabled() bool {
    if (runner_profile_tests_enabled) |enabled| return enabled;
    const raw = std.c.getenv("ZIG_DOM_PROFILE_TESTS");
    const enabled = if (raw) |value| !std.mem.eql(u8, std.mem.span(value), "0") else false;
    runner_profile_tests_enabled = enabled;
    return enabled;
}

fn runnerProfileActive() bool {
    return runnerProfileEnabled() or runnerProfileTestsEnabled();
}

fn autoRestoreSpiesEnabled() bool {
    const raw = std.c.getenv("ZIG_DOM_AUTO_RESTORE_SPIES") orelse return false;
    const value = std.mem.trim(u8, std.mem.span(raw), " \t\r\n");
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, "0") or
        std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.ascii.eqlIgnoreCase(value, "off"))
    {
        return false;
    }
    return true;
}

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

    fn deinit(self: *RunResult, allocator: Allocator) void {
        for (self.failures.items) |*failure| failure.deinit(allocator);
        self.failures.deinit(allocator);
    }
};

const CallbackOutcome = struct {
    ok: bool,
    timeout: bool = false,
    elapsed_ms: i64 = 0,
    error_text: ?[]u8 = null,
};

fn profileNowNs() i128 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return 0;
    return (@as(i128, ts.sec) * 1_000_000_000) + @as(i128, ts.nsec);
}

pub const HostRunner = struct {
    allocator: Allocator,
    io: std.Io,
    rt: *quickjs.Runtime,
    ctx: *quickjs.Context,
    root_scope: *Scope,
    active_scope: *Scope,
    collection_errors: std.ArrayList([]u8) = .empty,
    registered_test_count: i32 = 0,
    runnable_test_index: usize = 0,

    pub fn init(allocator: Allocator, io: std.Io, rt: *quickjs.Runtime, ctx: *quickjs.Context) HostRunnerError!*HostRunner {
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
            .io = io,
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
        try self.installDomCleanup();

        const runner_obj = quickjs.Value.initObject(ctx);
        if (runner_obj.isException()) return error.JSError;
        try setFunction(ctx, runner_obj, "run", jsRun, 0);
        global.setPropertyStr(ctx, "__zigRunner", runner_obj) catch return error.JSError;
    }

    fn installEachHelpers(self: *HostRunner) HostRunnerError!void {
        const ctx = self.ctx;
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);

        try installEachOnGlobalTarget(ctx, global, "test");
        try installEachOnGlobalTarget(ctx, global, "it");
        try installEachOnGlobalTarget(ctx, global, "describe");
        try installEachOnGlobalNestedTarget(ctx, global, "test", "skip");
        try installEachOnGlobalNestedTarget(ctx, global, "test", "only");
        try installEachOnGlobalNestedTarget(ctx, global, "it", "skip");
        try installEachOnGlobalNestedTarget(ctx, global, "it", "only");
        try installEachOnGlobalNestedTarget(ctx, global, "describe", "skip");
    }

    fn installDomCleanup(self: *HostRunner) HostRunnerError!void {
        const cleanup_fn = quickjs.Value.initCFunction(self.ctx, jsRunnerDomCleanup, "__zigRunnerDomCleanup", 0);
        if (cleanup_fn.isException()) return error.JSError;
        errdefer cleanup_fn.deinit(self.ctx);

        self.root_scope.after_each.append(self.allocator, .{
            .callback = cleanup_fn,
            .timeout_ms = DEFAULT_TIMEOUT_MS,
        }) catch return error.OutOfMemory;
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
        defer result.deinit(self.allocator);
        if (runnerProfileActive()) runner_perf_stats = .{};
        defer if (runnerProfileActive()) {
            std.debug.print(
                "[zig-dom runner profile] tests={d} before_each_ms={d:.3} body_ms={d:.3} after_each_ms={d:.3} restore_spies_ms={d:.3} pending_jobs_ms={d:.3} timer_turns_ms={d:.3} promise_iterations={d} pending_jobs={d} timer_turns={d} due_timer_turns={d}\n",
                .{
                    runner_perf_stats.tests,
                    @as(f64, @floatFromInt(runner_perf_stats.before_each_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.body_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.after_each_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.restore_spies_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.pending_jobs_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.timer_turns_ns)) / 1_000_000.0,
                    runner_perf_stats.promise_iterations,
                    runner_perf_stats.pending_jobs,
                    runner_perf_stats.timer_turns,
                    runner_perf_stats.due_timer_turns,
                },
            );
        };

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
        const auto_restore_spies = autoRestoreSpiesEnabled();
        const spy_checkpoint = if (auto_restore_spies) self.captureSpyCheckpoint() else 0;
        if (auto_restore_spies) {
            defer {
                const restore_start = if (runnerProfileActive()) profileNowNs() else 0;
                self.restoreSpiesSince(spy_checkpoint);
                if (runnerProfileActive()) runner_perf_stats.restore_spies_ns += profileNowNs() - restore_start;
            }
        }

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

        const test_stats_start = runner_perf_stats;
        const before_start = if (runnerProfileActive()) profileNowNs() else 0;
        const before_outcome = try self.runHookList(before_each.items, test_entry.timeout_ms);
        if (runnerProfileActive()) runner_perf_stats.before_each_ns += profileNowNs() - before_start;
        defer if (before_outcome.error_text) |text| self.allocator.free(text);
        if (!before_outcome.ok) {
            const name = try std.fmt.allocPrint(self.allocator, "{s} (beforeEach)", .{full_name});
            defer self.allocator.free(name);
            try self.addFailure(result, name, before_outcome.error_text orelse "beforeEach failed", before_outcome.timeout);
            _ = try self.runHookList(after_each.items, test_entry.timeout_ms);
            return;
        }

        const profile_start = profileNowNs();
        const test_outcome = try self.invokeCallback(test_entry.callback, test_entry.timeout_ms);
        const body_elapsed_ns = profileNowNs() - profile_start;
        const elapsed_ms = @as(f64, @floatFromInt(body_elapsed_ns)) / 1_000_000.0;
        if (runnerProfileActive()) runner_perf_stats.body_ns += body_elapsed_ns;
        defer if (test_outcome.error_text) |text| self.allocator.free(text);
        const after_start = if (runnerProfileActive()) profileNowNs() else 0;
        const after_outcome = try self.runHookList(after_each.items, test_entry.timeout_ms);
        if (runnerProfileActive()) runner_perf_stats.after_each_ns += profileNowNs() - after_start;
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
        if (runnerProfileActive()) runner_perf_stats.tests += 1;
        if (runnerProfileTestsEnabled()) {
            std.debug.print(
                "[zig-dom test profile] {s} body_ms={d:.3} before_ms={d:.3} after_ms={d:.3} pending_jobs_ms={d:.3} timer_ms={d:.3} jobs={d} timer_turns={d} due_timer_turns={d} promise_iterations={d}\n",
                .{
                    full_name,
                    @as(f64, @floatFromInt(body_elapsed_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.before_each_ns - test_stats_start.before_each_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.after_each_ns - test_stats_start.after_each_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.pending_jobs_ns - test_stats_start.pending_jobs_ns)) / 1_000_000.0,
                    @as(f64, @floatFromInt(runner_perf_stats.timer_turns_ns - test_stats_start.timer_turns_ns)) / 1_000_000.0,
                    runner_perf_stats.pending_jobs - test_stats_start.pending_jobs,
                    runner_perf_stats.timer_turns - test_stats_start.timer_turns,
                    runner_perf_stats.due_timer_turns - test_stats_start.due_timer_turns,
                    runner_perf_stats.promise_iterations - test_stats_start.promise_iterations,
                },
            );
        }
        try reporter.printPassedLineStdout(self.allocator, self.io, full_name, elapsed_ms);
    }

    fn restoreAllSpies(self: *HostRunner) void {
        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);

        const restore_all = global.getPropertyStr(self.ctx, "__zigRestoreAllSpies");
        defer restore_all.deinit(self.ctx);
        if (restore_all.isException() or !restore_all.isFunction(self.ctx)) return;

        const result = restore_all.call(self.ctx, quickjs.Value.undefined, &.{});
        defer result.deinit(self.ctx);
        if (result.isException()) {
            const exception = self.ctx.getException();
            exception.deinit(self.ctx);
        }
    }

    fn captureSpyCheckpoint(self: *HostRunner) i32 {
        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);

        const get_count = global.getPropertyStr(self.ctx, "__zigGetSpyCount");
        defer get_count.deinit(self.ctx);
        if (get_count.isException() or !get_count.isFunction(self.ctx)) return 0;

        const result = get_count.call(self.ctx, quickjs.Value.undefined, &.{});
        defer result.deinit(self.ctx);
        if (result.isException()) {
            const exception = self.ctx.getException();
            exception.deinit(self.ctx);
            return 0;
        }
        return result.toInt32(self.ctx) catch 0;
    }

    fn restoreSpiesSince(self: *HostRunner, checkpoint: i32) void {
        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);

        const restore_since = global.getPropertyStr(self.ctx, "__zigRestoreSpiesSince");
        defer restore_since.deinit(self.ctx);
        if (restore_since.isException() or !restore_since.isFunction(self.ctx)) {
            self.restoreAllSpies();
            return;
        }

        var checkpoint_value = quickjs.Value.initInt32(if (checkpoint > 0) checkpoint else 0);
        defer checkpoint_value.deinit(self.ctx);
        var args = [_]quickjs.Value{checkpoint_value};
        const result = restore_since.call(self.ctx, quickjs.Value.undefined, &args);
        defer result.deinit(self.ctx);
        if (result.isException()) {
            const exception = self.ctx.getException();
            exception.deinit(self.ctx);
            self.restoreAllSpies();
        }
    }

    fn collectBeforeEach(self: *HostRunner, scope: *Scope, out: *std.ArrayList(Hook)) !void {
        if (scope.parent) |parent| try self.collectBeforeEach(parent, out);
        try out.appendSlice(self.allocator, scope.before_each.items);
    }

    fn collectAfterEach(self: *HostRunner, scope: *Scope, out: *std.ArrayList(Hook)) !void {
        var index = scope.after_each.items.len;
        while (index > 0) {
            index -= 1;
            try out.append(self.allocator, scope.after_each.items[index]);
        }
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
                if (runnerProfileActive()) runner_perf_stats.promise_iterations += 1;
                if (self.rt.isJobPending()) {
                    while (self.rt.isJobPending()) {
                        if (runnerProfileActive()) runner_perf_stats.pending_jobs += 1;
                        const job_start = if (runnerProfileActive()) profileNowNs() else 0;
                        _ = self.rt.executePendingJob() catch return .{ .ok = false, .error_text = self.takeExceptionText() };
                        if (runnerProfileActive()) runner_perf_stats.pending_jobs_ns += profileNowNs() - job_start;
                    }
                } else if (platform.hasPendingNativeTimers()) {
                    if (runnerProfileActive()) runner_perf_stats.timer_turns += 1;
                    const timer_start = if (runnerProfileActive()) profileNowNs() else 0;
                    const timer_result = platform.runNativeTimerTurn(self.ctx);
                    if (runnerProfileActive()) runner_perf_stats.timer_turns_ns += profileNowNs() - timer_start;
                    defer timer_result.deinit(self.ctx);
                    if (timer_result.isException()) return .{ .ok = false, .error_text = self.takeExceptionText() };
                    while (platform.hasDueNativeTimers()) {
                        if (runnerProfileActive()) runner_perf_stats.due_timer_turns += 1;
                        const due_timer_start = if (runnerProfileActive()) profileNowNs() else 0;
                        const due_timer_result = platform.runNativeTimerTurn(self.ctx);
                        if (runnerProfileActive()) runner_perf_stats.timer_turns_ns += profileNowNs() - due_timer_start;
                        defer due_timer_result.deinit(self.ctx);
                        if (due_timer_result.isException()) return .{ .ok = false, .error_text = self.takeExceptionText() };
                    }
                } else {
                    break;
                }
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
        global.setPropertyStr(ctx, "__zigPassedText", quickjs.Value.initStringLen(ctx, "")) catch return error.JSError;
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
        const message = value.getPropertyStr(self.ctx, "message");
        defer message.deinit(self.ctx);
        const stack = value.getPropertyStr(self.ctx, "stack");
        defer stack.deinit(self.ctx);
        if (!stack.isException() and !stack.isUndefined() and !stack.isNull()) {
            const stack_text = try self.valueToOwnedString(stack);
            errdefer self.allocator.free(stack_text);
            if (!message.isException() and !message.isUndefined() and !message.isNull()) {
                const message_text = try self.valueToOwnedString(message);
                defer self.allocator.free(message_text);
                if (message_text.len > 0 and std.mem.indexOf(u8, stack_text, message_text) == null) {
                    const combined = try std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ message_text, stack_text });
                    self.allocator.free(stack_text);
                    return combined;
                }
            }
            return stack_text;
        }
        return self.valueToOwnedString(value);
    }
};

fn installEachOnGlobalTarget(ctx: *quickjs.Context, global: quickjs.Value, comptime name: [:0]const u8) HostRunnerError!void {
    const target = global.getPropertyStr(ctx, name);
    defer target.deinit(ctx);
    if (target.isException() or !target.isObject()) return error.JSError;
    try installEachOnTarget(ctx, target);
}

fn installEachOnGlobalNestedTarget(
    ctx: *quickjs.Context,
    global: quickjs.Value,
    comptime parent_name: [:0]const u8,
    comptime child_name: [:0]const u8,
) HostRunnerError!void {
    const parent = global.getPropertyStr(ctx, parent_name);
    defer parent.deinit(ctx);
    if (parent.isException() or !parent.isObject()) return error.JSError;

    const target = parent.getPropertyStr(ctx, child_name);
    defer target.deinit(ctx);
    if (target.isException() or !target.isObject()) return error.JSError;
    try installEachOnTarget(ctx, target);
}

fn installEachOnTarget(ctx: *quickjs.Context, target: quickjs.Value) HostRunnerError!void {
    var data = [_]quickjs.Value{target};
    const each_fn = quickjs.Value.initCFunctionData2(ctx, jsEachBindTable, "each", 1, 0, &data);
    if (each_fn.isException()) return error.JSError;
    errdefer each_fn.deinit(ctx);
    target.setPropertyStr(ctx, "each", each_fn) catch return error.JSError;
}

fn jsEachBindTable(
    maybe_ctx: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const target = quickjs.Value.fromCVal(data[0]);
    const table = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    var closure_data = [_]quickjs.Value{ target, table };
    return quickjs.Value.initCFunctionData2(ctx, jsEachRegisterRows, "__zigEachRows", 3, 0, &closure_data);
}

fn jsEachRegisterRows(
    maybe_ctx: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const target = quickjs.Value.fromCVal(data[0]);
    const table = quickjs.Value.fromCVal(data[1]);

    const rows = eachRowsArrayFrom(ctx, table);
    defer rows.deinit(ctx);
    if (rows.isException()) return quickjs.Value.exception;

    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const callback = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    const timeout_arg = if (args.len > 2) quickjs.Value.fromCVal(args[2]) else quickjs.Value.undefined;

    const row_count = valueArrayLength(ctx, rows);
    for (0..row_count) |index| {
        const row = rows.getPropertyUint32(ctx, @intCast(index));
        defer row.deinit(ctx);
        if (row.isException()) return quickjs.Value.exception;

        const formatted_name = formatEachName(ctx, name, row, index);
        defer formatted_name.deinit(ctx);
        if (formatted_name.isException()) return quickjs.Value.exception;

        var callback_data = [_]quickjs.Value{ callback, row };
        const row_callback = quickjs.Value.initCFunctionData2(ctx, jsEachInvokeRow, "__zigEachRow", 0, 0, &callback_data);
        if (row_callback.isException()) return quickjs.Value.exception;
        defer row_callback.deinit(ctx);

        var call_args = [_]quickjs.Value{ formatted_name, row_callback, timeout_arg };
        const register_result = target.call(ctx, quickjs.Value.undefined, &call_args);
        defer register_result.deinit(ctx);
        if (register_result.isException()) return quickjs.Value.exception;
    }

    return quickjs.Value.undefined;
}

fn jsEachInvokeRow(
    maybe_ctx: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const callback = quickjs.Value.fromCVal(data[0]);
    const row = quickjs.Value.fromCVal(data[1]);
    if (!callback.isFunction(ctx)) return ctx.throwInternalError("each() callback must be a function");

    if (row.isArray()) {
        var call_args: std.ArrayList(quickjs.Value) = .empty;
        defer {
            for (call_args.items) |value| value.deinit(ctx);
            call_args.deinit(std.heap.c_allocator);
        }

        const row_len = valueArrayLength(ctx, row);
        call_args.ensureTotalCapacity(std.heap.c_allocator, row_len) catch return quickjs.Value.exception;
        for (0..row_len) |index| {
            const item = row.getPropertyUint32(ctx, @intCast(index));
            defer item.deinit(ctx);
            if (item.isException()) return quickjs.Value.exception;
            call_args.append(std.heap.c_allocator, item.dup(ctx)) catch return quickjs.Value.exception;
        }

        return callback.call(ctx, quickjs.Value.undefined, call_args.items);
    }

    var call_args = [_]quickjs.Value{row.dup(ctx)};
    defer call_args[0].deinit(ctx);
    return callback.call(ctx, quickjs.Value.undefined, &call_args);
}

fn eachRowsArrayFrom(ctx: *quickjs.Context, table: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const array_ctor = global.getPropertyStr(ctx, "Array");
    defer array_ctor.deinit(ctx);
    if (array_ctor.isException() or !array_ctor.isObject()) return quickjs.Value.exception;

    const from_fn = array_ctor.getPropertyStr(ctx, "from");
    defer from_fn.deinit(ctx);
    if (!from_fn.isFunction(ctx)) return quickjs.Value.exception;

    const input = if (table.isNull() or table.isUndefined()) quickjs.Value.initArray(ctx) else table.dup(ctx);
    defer input.deinit(ctx);
    if (input.isException()) return quickjs.Value.exception;

    var from_args = [_]quickjs.Value{input};
    return from_fn.call(ctx, array_ctor, &from_args);
}

fn formatEachName(ctx: *quickjs.Context, name: quickjs.Value, row: quickjs.Value, index: usize) quickjs.Value {
    const allocator = std.heap.c_allocator;

    var formatted = stringifyToOwned(ctx, name, allocator) catch return quickjs.Value.exception;
    defer allocator.free(formatted);

    const index_text = std.fmt.allocPrint(allocator, "{d}", .{index}) catch return quickjs.Value.exception;
    defer allocator.free(index_text);

    var replaced = replaceEachIndexTokens(allocator, formatted, index_text) catch return quickjs.Value.exception;
    allocator.free(formatted);
    formatted = replaced;

    if (row.isArray()) {
        const row_len = valueArrayLength(ctx, row);
        for (0..row_len) |item_index| {
            const item = row.getPropertyUint32(ctx, @intCast(item_index));
            defer item.deinit(ctx);
            if (item.isException()) return quickjs.Value.exception;

            const item_text = stringifyToOwned(ctx, item, allocator) catch return quickjs.Value.exception;
            defer allocator.free(item_text);

            replaced = replaceFirstEachValueToken(allocator, formatted, item_text) catch return quickjs.Value.exception;
            allocator.free(formatted);
            formatted = replaced;
        }
    } else {
        const row_text = stringifyToOwned(ctx, row, allocator) catch return quickjs.Value.exception;
        defer allocator.free(row_text);

        replaced = replaceFirstEachValueToken(allocator, formatted, row_text) catch return quickjs.Value.exception;
        allocator.free(formatted);
        formatted = replaced;
    }

    return quickjs.Value.initStringLen(ctx, formatted);
}

fn stringifyToOwned(ctx: *quickjs.Context, value: quickjs.Value, allocator: Allocator) ![]u8 {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const string_ctor = global.getPropertyStr(ctx, "String");
    defer string_ctor.deinit(ctx);
    if (string_ctor.isException() or !string_ctor.isFunction(ctx)) return error.JSError;

    var args = [_]quickjs.Value{value.dup(ctx)};
    defer args[0].deinit(ctx);
    const string_value = string_ctor.call(ctx, quickjs.Value.undefined, &args);
    defer string_value.deinit(ctx);
    if (string_value.isException()) return error.JSError;

    const text = string_value.toCStringLen(ctx) orelse return error.OutOfMemory;
    defer ctx.freeCString(text.ptr);
    return allocator.dupe(u8, text.ptr[0..text.len]);
}

fn replaceEachIndexTokens(allocator: Allocator, input: []const u8, replacement: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < input.len) {
        if (cursor + 1 < input.len and input[cursor] == '%' and input[cursor + 1] == '#') {
            try out.appendSlice(allocator, replacement);
            cursor += 2;
            continue;
        }
        try out.append(allocator, input[cursor]);
        cursor += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn replaceFirstEachValueToken(allocator: Allocator, input: []const u8, replacement: []const u8) ![]u8 {
    var found_at: ?usize = null;
    if (input.len >= 2) {
        for (0..input.len - 1) |index| {
            if (input[index] == '%' and isEachValueTokenChar(input[index + 1])) {
                found_at = index;
                break;
            }
        }
    }

    if (found_at == null) return allocator.dupe(u8, input);

    const at = found_at.?;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, input[0..at]);
    try out.appendSlice(allocator, replacement);
    try out.appendSlice(allocator, input[at + 2 ..]);
    return out.toOwnedSlice(allocator);
}

fn isEachValueTokenChar(ch: u8) bool {
    return ch == 's' or
        ch == 'd' or
        ch == 'i' or
        ch == 'f' or
        ch == 'o' or
        ch == 'O' or
        ch == 'j';
}

fn valueArrayLength(ctx: *quickjs.Context, value: quickjs.Value) usize {
    const length = value.getPropertyStr(ctx, "length");
    defer length.deinit(ctx);
    if (length.isException()) return 0;
    const raw = length.toInt64(ctx) catch return 0;
    if (raw <= 0) return 0;
    return @intCast(raw);
}

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

fn jsRunnerDomCleanup(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    runTestingLibraryCleanup(ctx, global);

    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (!document.isException() and document.isObject()) {
        clearDocumentWindowNodes(ctx, document);
        document.setPropertyStr(ctx, "__zigCookie", quickjs.Value.initStringLen(ctx, "")) catch {
            clearPendingException(ctx);
        };
    } else if (document.isException()) {
        clearPendingException(ctx);
    }

    clearStorageObject(ctx, global, "localStorage");
    clearStorageObject(ctx, global, "sessionStorage");

    return quickjs.Value.undefined;
}

fn runTestingLibraryCleanup(ctx: *quickjs.Context, global: quickjs.Value) void {
    const testing_library = global.getPropertyStr(ctx, "__zigTestingLibraryReact");
    defer testing_library.deinit(ctx);
    if (testing_library.isException()) {
        clearPendingException(ctx);
        return;
    }
    if (!testing_library.isObject()) return;

    const cleanup_fn = testing_library.getPropertyStr(ctx, "cleanup");
    defer cleanup_fn.deinit(ctx);
    if (cleanup_fn.isException()) {
        clearPendingException(ctx);
        return;
    }
    if (!cleanup_fn.isFunction(ctx)) return;

    const result = cleanup_fn.call(ctx, testing_library, &.{});
    defer result.deinit(ctx);
    if (result.isException()) {
        clearPendingException(ctx);
    }
}

fn clearDocumentWindowNodes(ctx: *quickjs.Context, document: quickjs.Value) void {
    const window_handle_value = document.getPropertyStr(ctx, "_windowHandle");
    defer window_handle_value.deinit(ctx);
    if (window_handle_value.isException()) {
        clearPendingException(ctx);
        return;
    }
    const window_handle_raw = window_handle_value.toInt64(ctx) catch return;
    if (window_handle_raw <= 0) return;
    const window_handle: u64 = @intCast(window_handle_raw);

    var body_handle: u64 = 0;
    if (zig_dom.zig_dom_window_body(window_handle, &body_handle) == 0 and body_handle != 0) {
        _ = zig_dom.zig_dom_node_set_inner_html(body_handle, "", 0);
    }

    var head_handle: u64 = 0;
    if (zig_dom.zig_dom_window_head(window_handle, &head_handle) == 0 and head_handle != 0) {
        _ = zig_dom.zig_dom_node_set_inner_html(head_handle, "", 0);
    }
}

fn clearStorageObject(ctx: *quickjs.Context, global: quickjs.Value, comptime name: [:0]const u8) void {
    const storage = global.getPropertyStr(ctx, name);
    defer storage.deinit(ctx);
    if (storage.isException()) {
        clearPendingException(ctx);
        return;
    }
    if (!storage.isObject()) return;

    const clear_fn = storage.getPropertyStr(ctx, "clear");
    defer clear_fn.deinit(ctx);
    if (clear_fn.isException()) {
        clearPendingException(ctx);
        return;
    }
    if (!clear_fn.isFunction(ctx)) return;

    const clear_result = clear_fn.call(ctx, storage, &.{});
    defer clear_result.deinit(ctx);
    if (clear_result.isException()) {
        clearPendingException(ctx);
    }
}

fn clearPendingException(ctx: *quickjs.Context) void {
    const exception = ctx.getException();
    exception.deinit(ctx);
}

fn setFunction(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) HostRunnerError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

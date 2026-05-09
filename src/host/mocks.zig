const std = @import("std");
const quickjs = @import("quickjs");

const Allocator = std.mem.Allocator;

pub const HostMocksError = error{ OutOfMemory, JSError };

var active_mocks: ?*HostMocks = null;

const MockState = struct {
    owner: *HostMocks,
    mock_function: quickjs.Value,
    calls: quickjs.Value,
    once_implementations: quickjs.Value,
    implementation: quickjs.Value,
    original_implementation: quickjs.Value,
    return_value: quickjs.Value,
    resolved_value: quickjs.Value,
    rejected_value: quickjs.Value,
    restore_target: quickjs.Value,
    restore_property: quickjs.Value,
    restore_value: quickjs.Value,
    has_return_value: bool = false,
    has_resolved_value: bool = false,
    has_rejected_value: bool = false,
    has_restore: bool = false,
    restore_getter: bool = false,
    disposed: bool = false,

    fn deinit(self: *MockState, rt: *quickjs.Runtime) void {
        if (self.disposed) return;
        self.disposed = true;
        self.mock_function.deinitRT(rt);
        self.calls.deinitRT(rt);
        self.once_implementations.deinitRT(rt);
        self.implementation.deinitRT(rt);
        self.original_implementation.deinitRT(rt);
        self.return_value.deinitRT(rt);
        self.resolved_value.deinitRT(rt);
        self.rejected_value.deinitRT(rt);
        self.restore_target.deinitRT(rt);
        self.restore_property.deinitRT(rt);
        self.restore_value.deinitRT(rt);
    }
};

const OnLoadHook = struct {
    filter: quickjs.Value,
    callback: quickjs.Value,

    fn deinit(self: *OnLoadHook, rt: *quickjs.Runtime) void {
        self.filter.deinitRT(rt);
        self.callback.deinitRT(rt);
    }
};

pub const OnLoadResult = struct {
    contents: []u8,
    loader: ?[]u8,

    pub fn deinit(self: *OnLoadResult, allocator: Allocator) void {
        allocator.free(self.contents);
        if (self.loader) |loader| allocator.free(loader);
    }
};

pub const HostMocks = struct {
    allocator: Allocator,
    rt: *quickjs.Runtime,
    ctx: *quickjs.Context,
    mock_class_id: quickjs.ClassId = .invalid,
    on_load_hooks: std.ArrayList(OnLoadHook) = .empty,
    mock_states: std.ArrayList(*MockState) = .empty,
    mock_module_sources: std.StringHashMap([]u8),

    pub fn init(allocator: Allocator, rt: *quickjs.Runtime, ctx: *quickjs.Context) HostMocksError!*HostMocks {
        const mocks = allocator.create(HostMocks) catch return error.OutOfMemory;
        errdefer allocator.destroy(mocks);
        mocks.* = .{
            .allocator = allocator,
            .rt = rt,
            .ctx = ctx,
            .mock_module_sources = std.StringHashMap([]u8).init(allocator),
        };
        active_mocks = mocks;
        try mocks.installGlobals();
        return mocks;
    }

    pub fn deinit(self: *HostMocks) void {
        if (active_mocks == self) active_mocks = null;
        self.clearHooks();
        self.clearMockModuleSources();
        self.on_load_hooks.deinit(self.allocator);
        self.mock_module_sources.deinit();
        for (self.mock_states.items) |state| {
            state.deinit(self.rt);
            self.allocator.destroy(state);
        }
        self.mock_states.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn hasOnLoadHooks(self: *HostMocks) bool {
        return self.on_load_hooks.items.len > 0;
    }

    pub fn matchesOnLoad(self: *HostMocks, path: []const u8) HostMocksError!bool {
        if (self.on_load_hooks.items.len == 0) return false;

        const ctx = self.ctx;
        const path_value = quickjs.Value.initStringLen(ctx, path);
        if (path_value.isException()) return error.JSError;
        defer path_value.deinit(ctx);

        for (self.on_load_hooks.items) |hook| {
            const test_fn = hook.filter.getPropertyStr(ctx, "test");
            defer test_fn.deinit(ctx);
            if (!test_fn.isFunction(ctx)) continue;

            var test_args = [_]quickjs.Value{path_value.dup(ctx)};
            defer test_args[0].deinit(ctx);
            const matched = test_fn.call(ctx, hook.filter, &test_args);
            defer matched.deinit(ctx);
            if (matched.isException()) return error.JSError;
            if (matched.toBool(ctx) catch return error.JSError) return true;
        }

        return false;
    }

    pub fn applyOnLoad(self: *HostMocks, path: []const u8) HostMocksError!?OnLoadResult {
        if (self.on_load_hooks.items.len == 0) return null;

        const ctx = self.ctx;
        const path_value = quickjs.Value.initStringLen(ctx, path);
        if (path_value.isException()) return error.JSError;
        defer path_value.deinit(ctx);

        for (self.on_load_hooks.items) |hook| {
            const test_fn = hook.filter.getPropertyStr(ctx, "test");
            defer test_fn.deinit(ctx);
            if (!test_fn.isFunction(ctx)) continue;

            var test_args = [_]quickjs.Value{path_value.dup(ctx)};
            defer test_args[0].deinit(ctx);
            const matched = test_fn.call(ctx, hook.filter, &test_args);
            defer matched.deinit(ctx);
            if (matched.isException()) return error.JSError;
            if (!(matched.toBool(ctx) catch return error.JSError)) continue;

            const request = quickjs.Value.initObject(ctx);
            if (request.isException()) return error.JSError;
            defer request.deinit(ctx);
            request.setPropertyStr(ctx, "path", path_value.dup(ctx)) catch return error.JSError;

            var call_args = [_]quickjs.Value{request.dup(ctx)};
            defer call_args[0].deinit(ctx);
            var result = hook.callback.call(ctx, quickjs.Value.undefined, &call_args);
            defer result.deinit(ctx);
            if (result.isException()) return error.JSError;
            if (result.isPromise()) {
                const awaited = awaitPromise(ctx, self.rt, result) catch return error.JSError;
                result.deinit(ctx);
                result = awaited;
            }

            const contents_value = result.getPropertyStr(ctx, "contents");
            defer contents_value.deinit(ctx);
            if (contents_value.isException()) return error.JSError;
            if (contents_value.isUndefined() or contents_value.isNull()) continue;

            const contents_text = contents_value.toCStringLen(ctx) orelse return error.JSError;
            defer ctx.freeCString(contents_text.ptr);
            const contents = self.allocator.dupe(u8, contents_text.ptr[0..contents_text.len]) catch return error.OutOfMemory;
            errdefer self.allocator.free(contents);

            const loader_value = result.getPropertyStr(ctx, "loader");
            defer loader_value.deinit(ctx);
            if (loader_value.isException()) return error.JSError;
            const loader = if (!loader_value.isUndefined() and !loader_value.isNull()) blk: {
                const loader_text = loader_value.toCStringLen(ctx) orelse return error.JSError;
                defer ctx.freeCString(loader_text.ptr);
                if (loader_text.len == 0) break :blk null;
                break :blk self.allocator.dupe(u8, loader_text.ptr[0..loader_text.len]) catch return error.OutOfMemory;
            } else null;
            errdefer if (loader) |owned| self.allocator.free(owned);

            return .{ .contents = contents, .loader = loader };
        }

        return null;
    }

    pub fn destroyAfterRuntimeFree(self: *HostMocks) void {
        if (active_mocks == self) active_mocks = null;
        self.clearMockModuleSources();
        self.on_load_hooks.deinit(self.allocator);
        self.mock_module_sources.deinit();
        for (self.mock_states.items) |state| self.allocator.destroy(state);
        self.mock_states.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn clearHooks(self: *HostMocks) void {
        for (self.on_load_hooks.items) |*hook| hook.deinit(self.rt);
        self.on_load_hooks.clearRetainingCapacity();
    }

    pub fn clearMockStates(self: *HostMocks) void {
        for (self.mock_states.items) |state| state.deinit(self.rt);
    }

    pub fn clearMockModuleSources(self: *HostMocks) void {
        var iterator = self.mock_module_sources.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.mock_module_sources.clearRetainingCapacity();
    }

    pub fn clearGlobals(self: *HostMocks) void {
        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);
        inline for (.{ "__zigRunnerMockExports", "__zigMockModuleManifestJson", "__zigMock", "mock", "__zigSpyOn", "spyOn", "__zigRunnerApplyOnLoad", "__zigCollectRelatedSpyCalls", "__zigRestoreAllSpies", "__zigBunApi", "Bun" }) |name| {
            global.setPropertyStr(self.ctx, name, quickjs.Value.undefined) catch {};
        }
    }

    fn installClass(self: *HostMocks) HostMocksError!void {
        self.mock_class_id = quickjs.ClassId.new(self.rt);
        const def: quickjs.ClassDef = .{
            .class_name = "ZigMockFunction",
            .finalizer = jsMockFinalizer,
            .call = jsMockCall,
        };
        self.rt.newClass(self.mock_class_id, &def) catch return error.JSError;
        const proto = quickjs.Value.initObject(self.ctx);
        if (proto.isException()) return error.OutOfMemory;
        defer proto.deinit(self.ctx);
        self.ctx.setClassProto(self.mock_class_id, proto.dup(self.ctx));
    }

    fn installGlobals(self: *HostMocks) HostMocksError!void {
        const ctx = self.ctx;
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);

        const exports = quickjs.Value.initObject(ctx);
        if (exports.isException()) return error.OutOfMemory;
        global.setPropertyStr(ctx, "__zigRunnerMockExports", exports) catch return error.JSError;
        global.setPropertyStr(ctx, "__zigMockModuleManifestJson", quickjs.Value.initStringLen(ctx, "[]")) catch return error.JSError;

        const mock_fn = quickjs.Value.initCFunction(ctx, jsMock, "mock", 1);
        if (mock_fn.isException()) return error.JSError;
        try setFunction(ctx, mock_fn, "module", jsMockModule, 2);
        global.setPropertyStr(ctx, "__zigMock", mock_fn) catch return error.JSError;

        try setFunction(ctx, global, "__zigSpyOn", jsSpyOn, 2);
        try setFunction(ctx, global, "__zigRunnerApplyOnLoad", jsApplyOnLoad, 1);
        try setFunction(ctx, global, "__zigCollectRelatedSpyCalls", jsCollectRelatedSpyCalls, 1);
        try setFunction(ctx, global, "__zigRestoreAllSpies", jsRestoreAllSpies, 0);

        const bun_api = quickjs.Value.initObject(ctx);
        if (bun_api.isException()) return error.OutOfMemory;
        try setFunction(ctx, bun_api, "plugin", jsBunPlugin, 1);
        try setFunction(ctx, bun_api, "$", jsBunShellTag, 0);
        try setFunction(ctx, bun_api, "file", jsBunFile, 1);
        global.setPropertyStr(ctx, "__zigBunApi", bun_api.dup(ctx)) catch return error.JSError;
        if (std.c.getenv("ZIG_DOM_HIDE_BUN")) |raw| {
            if (!std.mem.eql(u8, std.mem.span(raw), "0")) {
                bun_api.deinit(ctx);
                return;
            }
        }
        global.setPropertyStr(ctx, "Bun", bun_api) catch return error.JSError;
    }

    fn createMockFunction(self: *HostMocks, implementation: quickjs.Value, original: quickjs.Value, restore_target: quickjs.Value, restore_property: quickjs.Value, restore_value: quickjs.Value, has_restore: bool, restore_getter: bool) quickjs.Value {
        if (self.mock_class_id == .invalid) {
            self.installClass() catch return quickjs.Value.exception;
        }
        const ctx = self.ctx;
        const state = self.allocator.create(MockState) catch return quickjs.Value.exception;
        state.* = .{
            .owner = self,
            .mock_function = quickjs.Value.undefined,
            .calls = quickjs.Value.initArray(ctx),
            .once_implementations = quickjs.Value.initArray(ctx),
            .implementation = if (implementation.isFunction(ctx)) implementation.dup(ctx) else quickjs.Value.undefined,
            .original_implementation = if (original.isFunction(ctx)) original.dup(ctx) else quickjs.Value.undefined,
            .return_value = quickjs.Value.undefined,
            .resolved_value = quickjs.Value.undefined,
            .rejected_value = quickjs.Value.undefined,
            .restore_target = if (has_restore) restore_target.dup(ctx) else quickjs.Value.undefined,
            .restore_property = if (has_restore) restore_property.dup(ctx) else quickjs.Value.undefined,
            .restore_value = if (has_restore) restore_value.dup(ctx) else quickjs.Value.undefined,
            .has_restore = has_restore,
            .restore_getter = restore_getter,
        };
        errdefer {
            state.deinit(self.rt);
            self.allocator.destroy(state);
        }
        self.mock_states.append(self.allocator, state) catch return quickjs.Value.exception;

        const func = quickjs.Value.initObjectClass(ctx, self.mock_class_id);
        if (func.isException()) return quickjs.Value.exception;
        if (!func.setOpaque(state)) return quickjs.Value.exception;
        state.mock_function = func.dup(ctx);

        const mock_info = quickjs.Value.initObject(ctx);
        if (mock_info.isException()) return quickjs.Value.exception;
        mock_info.setPropertyStr(ctx, "calls", state.calls.dup(ctx)) catch return quickjs.Value.exception;
        mock_info.setPropertyStr(ctx, "lastCall", quickjs.Value.undefined) catch return quickjs.Value.exception;
        func.setPropertyStr(ctx, "mock", mock_info) catch return quickjs.Value.exception;

        installMockMethod(ctx, func, "mockImplementation", .implementation, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockImplementationOnce", .implementation_once, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockReturnValue", .return_value, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockReturnValueOnce", .return_value_once, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockResolvedValue", .resolved_value, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockResolvedValueOnce", .resolved_value_once, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockRejectedValue", .rejected_value, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockRejectedValueOnce", .rejected_value_once, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockClear", .clear, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockReset", .reset, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockRestore", .restore, state) catch return quickjs.Value.exception;
        installMockSymbolDispose(ctx, func) catch return quickjs.Value.exception;
        return func;
    }

    fn putMockModuleSource(self: *HostMocks, specifier: []const u8, source: []const u8) !void {
        const value = try self.allocator.dupe(u8, source);
        errdefer self.allocator.free(value);

        if (self.mock_module_sources.getEntry(specifier)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            entry.value_ptr.* = value;
        } else {
            const key = try self.allocator.dupe(u8, specifier);
            errdefer self.allocator.free(key);
            try self.mock_module_sources.put(key, value);
        }

        try self.publishMockModuleManifest();
    }

    fn publishMockModuleManifest(self: *HostMocks) !void {
        var manifest: std.ArrayList(u8) = .empty;
        defer manifest.deinit(self.allocator);

        try manifest.append(self.allocator, '[');
        var iterator = self.mock_module_sources.iterator();
        var first = true;
        while (iterator.next()) |entry| {
            if (!first) try manifest.append(self.allocator, ',');
            first = false;

            const escaped_specifier = try jsonString(self.allocator, entry.key_ptr.*);
            defer self.allocator.free(escaped_specifier);
            const escaped_source = try jsonString(self.allocator, entry.value_ptr.*);
            defer self.allocator.free(escaped_source);

            try manifest.print(self.allocator, "{{\"specifier\":{s},\"source\":{s}}}", .{ escaped_specifier, escaped_source });
        }
        try manifest.append(self.allocator, ']');

        const ctx = self.ctx;
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        global.setPropertyStr(ctx, "__zigMockModuleManifestJson", quickjs.Value.initStringLen(ctx, manifest.items)) catch return error.JSError;
    }
};

const MockMethod = enum(i32) {
    implementation = 1,
    return_value = 2,
    resolved_value = 3,
    rejected_value = 4,
    clear = 5,
    reset = 6,
    restore = 7,
    implementation_once = 8,
    return_value_once = 9,
    resolved_value_once = 10,
    rejected_value_once = 11,
};

const OnceMode = enum(i32) {
    return_value = 1,
    resolved_value = 2,
    rejected_value = 3,
};

fn jsMockFinalizer(rt: ?*quickjs.c.JSRuntime, value: quickjs.c.JSValue) callconv(.c) void {
    const wrapped_value = quickjs.Value.fromCVal(value);
    const state = wrapped_value.getOpaque(MockState, active_mocks.?.mock_class_id) orelse return;
    if (rt) |runtime| state.deinit(@ptrCast(runtime));
}

fn jsMockCall(ctx: ?*quickjs.c.JSContext, func_obj: quickjs.c.JSValue, this_val: quickjs.c.JSValue, argc: c_int, argv: [*c]quickjs.c.JSValue, _: c_int) callconv(.c) quickjs.c.JSValue {
    const real_ctx: *quickjs.Context = @ptrCast(ctx orelse return quickjs.Value.exception.cval());
    const wrapped_func = quickjs.Value.fromCVal(func_obj);
    const wrapped_this = quickjs.Value.fromCVal(this_val);
    const mocks = active_mocks orelse return quickjs.Value.exception.cval();
    const state = wrapped_func.getOpaque(MockState, mocks.mock_class_id) orelse return quickjs.Value.exception.cval();

    const call_args = quickjs.Value.initArray(real_ctx);
    if (call_args.isException()) return quickjs.Value.exception.cval();
    for (0..@intCast(argc)) |index| {
        call_args.setPropertyUint32(real_ctx, @intCast(index), quickjs.Value.fromCVal(argv[index]).dup(real_ctx)) catch return quickjs.Value.exception.cval();
    }

    const length = state.calls.getLength(real_ctx) catch 0;
    state.calls.setPropertyUint32(real_ctx, @intCast(@max(length, 0)), call_args) catch return quickjs.Value.exception.cval();
    setMockLastCall(real_ctx, wrapped_func, call_args) catch return quickjs.Value.exception.cval();

    const args_slice: []const quickjs.Value = if (argc > 0) @ptrCast(argv[0..@intCast(argc)]) else &.{};
    const once_length = state.once_implementations.getLength(real_ctx) catch 0;
    const debug_request = blk: {
        if (std.c.getenv("ZIG_DOM_DEBUG_MOCK_CALLS") == null) break :blk false;
        if (!state.restore_property.isString()) break :blk false;
        const property_text = state.restore_property.toCStringLen(real_ctx) orelse break :blk false;
        defer real_ctx.freeCString(property_text.ptr);
        break :blk std.mem.eql(u8, property_text.ptr[0..property_text.len], "request");
    };
    if (debug_request) {
        std.debug.print(
            "[zig-dom mockCall] request once_len={} has_return={} has_resolved={} has_rejected={} impl_is_fn={}\n",
            .{
                once_length,
                state.has_return_value,
                state.has_resolved_value,
                state.has_rejected_value,
                state.implementation.isFunction(real_ctx),
            },
        );
    }
    if (once_length > 0) {
        const once_impl = shiftArrayValue(real_ctx, state.once_implementations) catch return quickjs.Value.exception.cval();
        defer once_impl.deinit(real_ctx);
        if (once_impl.isFunction(real_ctx)) {
            if (debug_request) std.debug.print("[zig-dom mockCall] request branch=once-implementation\n", .{});
            return once_impl.call(real_ctx, wrapped_this, args_slice).cval();
        }

        if (once_impl.isObject()) {
            const mode_value = once_impl.getPropertyStr(real_ctx, "__zigMockOnceMode");
            defer mode_value.deinit(real_ctx);
            const mode_raw = mode_value.toInt32(real_ctx) catch 0;
            const once_value = once_impl.getPropertyStr(real_ctx, "value");
            defer once_value.deinit(real_ctx);
            switch (mode_raw) {
                @intFromEnum(OnceMode.return_value) => {
                    if (debug_request) std.debug.print("[zig-dom mockCall] request branch=once-return\n", .{});
                    return once_value.dup(real_ctx).cval();
                },
                @intFromEnum(OnceMode.resolved_value) => {
                    if (debug_request) std.debug.print("[zig-dom mockCall] request branch=once-resolved\n", .{});
                    return resolvedPromise(real_ctx, once_value).cval();
                },
                @intFromEnum(OnceMode.rejected_value) => {
                    if (debug_request) std.debug.print("[zig-dom mockCall] request branch=once-rejected\n", .{});
                    return rejectedPromise(real_ctx, once_value).cval();
                },
                else => {},
            }
        }
    }
    if (state.implementation.isFunction(real_ctx)) {
        if (debug_request) std.debug.print("[zig-dom mockCall] request branch=implementation\n", .{});
        return state.implementation.call(real_ctx, wrapped_this, args_slice).cval();
    }
    if (state.has_return_value) {
        if (debug_request) std.debug.print("[zig-dom mockCall] request branch=return\n", .{});
        return state.return_value.dup(real_ctx).cval();
    }
    if (state.has_resolved_value) {
        if (debug_request) std.debug.print("[zig-dom mockCall] request branch=resolved\n", .{});
        return resolvedPromise(real_ctx, state.resolved_value).cval();
    }
    if (state.has_rejected_value) {
        if (debug_request) std.debug.print("[zig-dom mockCall] request branch=rejected\n", .{});
        return rejectedPromise(real_ctx, state.rejected_value).cval();
    }
    if (debug_request) std.debug.print("[zig-dom mockCall] request branch=undefined\n", .{});
    return quickjs.Value.undefined.cval();
}

fn shiftArrayValue(ctx: *quickjs.Context, array: quickjs.Value) !quickjs.Value {
    const shift_fn = array.getPropertyStr(ctx, "shift");
    defer shift_fn.deinit(ctx);
    if (!shift_fn.isFunction(ctx)) return error.JSError;

    var call_args = [_]quickjs.Value{};
    const shifted = shift_fn.call(ctx, array, &call_args);
    if (shifted.isException()) {
        shifted.deinit(ctx);
        return error.JSError;
    }
    return shifted;
}

fn pushArrayValue(ctx: *quickjs.Context, array: quickjs.Value, value: quickjs.Value) !void {
    const push_fn = array.getPropertyStr(ctx, "push");
    defer push_fn.deinit(ctx);
    if (!push_fn.isFunction(ctx)) return error.JSError;

    var call_args = [_]quickjs.Value{value.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const push_result = push_fn.call(ctx, array, &call_args);
    defer push_result.deinit(ctx);
    if (push_result.isException()) return error.JSError;
}

fn jsMock(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    _ = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.exception;
    const implementation = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    return mocks.createMockFunction(implementation, implementation, quickjs.Value.undefined, quickjs.Value.undefined, quickjs.Value.undefined, false, false);
}

fn jsMockModule(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.exception;
    if (args.len == 0) return ctx.throwInternalError("mock.module() requires a non-empty module specifier");
    const specifier_text = quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(specifier_text.ptr);
    const specifier = specifier_text.ptr[0..specifier_text.len];
    if (specifier.len == 0) return ctx.throwInternalError("mock.module() requires a non-empty module specifier");

    const factory = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    var produced = if (factory.isFunction(ctx)) factory.call(ctx, quickjs.Value.undefined, &.{}) else factory.dup(ctx);
    defer produced.deinit(ctx);
    if (produced.isException()) return quickjs.Value.exception;
    if (produced.isPromise()) {
        const promise_value = produced;
        produced = awaitPromise(ctx, mocks.rt, promise_value) catch return quickjs.Value.exception;
        promise_value.deinit(ctx);
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const exports = global.getPropertyStr(ctx, "__zigRunnerMockExports");
    defer exports.deinit(ctx);
    exports.setPropertyStr(ctx, specifier_text.ptr, produced.dup(ctx)) catch return quickjs.Value.exception;

    const source = buildMockModuleSource(mocks.allocator, ctx, specifier, produced) catch return quickjs.Value.exception;
    defer mocks.allocator.free(source);
    mocks.putMockModuleSource(specifier, source) catch return quickjs.Value.exception;

    const apply_loaded = global.getPropertyStr(ctx, "__zigApplyMockModuleExports");
    defer apply_loaded.deinit(ctx);
    if (!apply_loaded.isException() and apply_loaded.isFunction(ctx)) {
        var apply_args = [_]quickjs.Value{
            quickjs.Value.initStringLen(ctx, specifier),
            produced.dup(ctx),
        };
        defer {
            apply_args[0].deinit(ctx);
            apply_args[1].deinit(ctx);
        }

        const apply_result = apply_loaded.call(ctx, global, &apply_args);
        defer apply_result.deinit(ctx);
        if (apply_result.isException()) return quickjs.Value.exception;
    }

    return produced.dup(ctx);
}

fn jsSpyOn(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.exception;
    if (args.len < 2) return ctx.throwInternalError("spyOn() requires an object target");
    const target = quickjs.Value.fromCVal(args[0]);
    const property = quickjs.Value.fromCVal(args[1]);
    if (!target.isObject()) return ctx.throwInternalError("spyOn() requires an object target");

    const property_key = property.toStringValue(ctx);
    defer property_key.deinit(ctx);

    const current = target.getProperty(ctx, quickjs.Atom.fromValue(ctx, property_key));
    defer current.deinit(ctx);
    const current_is_mock_callable = current.getOpaque(MockState, mocks.mock_class_id) != null;
    const current_is_callable = current.isFunction(ctx) or current_is_mock_callable;
    if (std.c.getenv("ZIG_DOM_DEBUG_SPYON")) |_| {
        const key_text = property_key.toCStringLen(ctx);
        defer if (key_text) |text| ctx.freeCString(text.ptr);
        if (key_text) |text| {
            std.debug.print(
                "[zig-dom spyOn] property={s} callable={} is_function={} is_mock={}\n",
                .{
                    text.ptr[0..text.len],
                    current_is_callable,
                    current.isFunction(ctx),
                    current_is_mock_callable,
                },
            );
        }
    }

    if (findExistingMockState(mocks, ctx, target, property_key)) |existing_state| {
        if (existing_state.mock_function.isObject()) {
            const existing_mock = existing_state.mock_function.dup(ctx);
            if (std.c.getenv("ZIG_DOM_DEBUG_SPYON")) |_| {
                const key_text = property_key.toCStringLen(ctx);
                defer if (key_text) |text| ctx.freeCString(text.ptr);
                if (key_text) |text| {
                    const mock_return = existing_mock.getPropertyStr(ctx, "mockReturnValueOnce");
                    defer mock_return.deinit(ctx);
                    std.debug.print(
                        "[zig-dom spyOn] existing property={s} has_mockReturnValueOnce={} is_fn={}\n",
                        .{
                            text.ptr[0..text.len],
                            !mock_return.isUndefined(),
                            mock_return.isFunction(ctx),
                        },
                    );
                }
            }
            const atom = quickjs.Atom.fromValue(ctx, property_key);
            defer atom.deinit(ctx);
            if (!setSpyTargetProperty(ctx, target, atom, existing_mock)) {
                _ = patchModuleNamespaceExport(ctx, target, property_key, existing_mock);
                // Some objects (for example ESM module namespace bindings) are not replaceable.
                // Keep Bun-compatible behavior by returning the existing mock wrapper without throwing.
                mirrorGlobalWindowProperty(ctx, target, property_key, current, existing_mock);
                return existing_mock;
            }
            mirrorGlobalWindowProperty(ctx, target, property_key, current, existing_mock);
            return existing_mock;
        }
    }

    // Bun-compatible behavior: repeated spyOn on the same property should
    // return the existing mock wrapper instead of stacking nested wrappers.
    if (current_is_mock_callable) {
        if (std.c.getenv("ZIG_DOM_DEBUG_SPYON")) |_| {
            const key_text = property_key.toCStringLen(ctx);
            defer if (key_text) |text| ctx.freeCString(text.ptr);
            if (key_text) |text| {
                const mock_return = current.getPropertyStr(ctx, "mockReturnValueOnce");
                defer mock_return.deinit(ctx);
                std.debug.print(
                    "[zig-dom spyOn] reuse property={s} has_mockReturnValueOnce={} is_fn={}\n",
                    .{
                        text.ptr[0..text.len],
                        !mock_return.isUndefined(),
                        mock_return.isFunction(ctx),
                    },
                );
            }
        }
        return current.dup(ctx);
    }

    if (!current_is_callable) {
        const descriptor = getOwnPropertyDescriptor(ctx, target, property_key);
        defer descriptor.deinit(ctx);
        const getter = descriptor.getPropertyStr(ctx, "get");
        defer getter.deinit(ctx);
        const original_getter = if (getter.isFunction(ctx)) getter else quickjs.Value.undefined;
        const wrapped_getter = mocks.createMockFunction(original_getter, original_getter, target, property_key, original_getter, true, true);
        if (wrapped_getter.isException()) return quickjs.Value.exception;
        const atom = quickjs.Atom.fromValue(ctx, property_key);
        defer atom.deinit(ctx);
        const setter = quickjs.Value.undefined;
        _ = quickjs.c.JS_DefinePropertyGetSet(ctx.cval(), target.cval(), @intFromEnum(atom), wrapped_getter.dup(ctx).cval(), setter.cval(), quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_ENUMERABLE);
        return wrapped_getter;
    }

    const wrapped = mocks.createMockFunction(current, current, target, property_key, current, true, false);
    if (wrapped.isException()) return quickjs.Value.exception;
    if (std.c.getenv("ZIG_DOM_DEBUG_SPYON")) |_| {
        const key_text = property_key.toCStringLen(ctx);
        defer if (key_text) |text| ctx.freeCString(text.ptr);
        if (key_text) |text| {
            const mock_return = wrapped.getPropertyStr(ctx, "mockReturnValueOnce");
            defer mock_return.deinit(ctx);
            std.debug.print(
                "[zig-dom spyOn] wrap property={s} has_mockReturnValueOnce={} is_fn={}\n",
                .{
                    text.ptr[0..text.len],
                    !mock_return.isUndefined(),
                    mock_return.isFunction(ctx),
                },
            );
        }
    }
    const atom = quickjs.Atom.fromValue(ctx, property_key);
    defer atom.deinit(ctx);
    if (!setSpyTargetProperty(ctx, target, atom, wrapped)) {
        _ = patchModuleNamespaceExport(ctx, target, property_key, wrapped);
        // Fall back to returning the spy wrapper even when the target cannot be redefined.
        mirrorGlobalWindowProperty(ctx, target, property_key, current, wrapped);
        return wrapped;
    }
    mirrorGlobalWindowProperty(ctx, target, property_key, current, wrapped);
    return wrapped;
}

fn jsCollectRelatedSpyCalls(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.exception;

    const out = quickjs.Value.initArray(ctx);
    if (out.isException()) return quickjs.Value.exception;

    if (args.len == 0) return out;
    const received = quickjs.Value.fromCVal(args[0]);
    const state = received.getOpaque(MockState, mocks.mock_class_id) orelse return out;
    if (!state.has_restore or !state.restore_property.isString()) return out;

    var out_index: u32 = 0;
    for (mocks.mock_states.items) |candidate| {
        if (candidate.disposed or !candidate.has_restore) continue;
        if (!candidate.restore_property.isString()) continue;
        if (!candidate.restore_property.isSameValue(ctx, state.restore_property)) continue;

        out.setPropertyUint32(ctx, out_index, candidate.calls.dup(ctx)) catch return quickjs.Value.exception;
        out_index += 1;
    }

    return out;
}

fn jsRestoreAllSpies(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.undefined;

    for (mocks.mock_states.items) |state| {
        if (state.disposed or !state.has_restore) continue;
        if (!state.mock_function.isObject()) continue;
        restoreMockState(ctx, state, state.mock_function) catch return quickjs.Value.exception;
    }

    return quickjs.Value.undefined;
}

fn setSpyTargetProperty(ctx: *quickjs.Context, target: quickjs.Value, atom: quickjs.Atom, value: quickjs.Value) bool {
    target.setProperty(ctx, atom, value.dup(ctx)) catch {
        if (ctx.hasException()) {
            const exception = ctx.getException();
            exception.deinit(ctx);
        }
        return false;
    };

    var current = target.getProperty(ctx, atom);
    defer current.deinit(ctx);
    if (!current.isException() and current.isStrictEqual(ctx, value)) {
        return true;
    }

    const defined = quickjs.c.JS_DefinePropertyValue(
        ctx.cval(),
        target.cval(),
        @intFromEnum(atom),
        value.dup(ctx).cval(),
        quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_WRITABLE | quickjs.c.JS_PROP_ENUMERABLE,
    );
    if (defined < 0) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        return false;
    }

    current.deinit(ctx);
    current = target.getProperty(ctx, atom);
    if (current.isException()) {
        if (ctx.hasException()) {
            const exception = ctx.getException();
            exception.deinit(ctx);
        }
        return false;
    }
    return current.isStrictEqual(ctx, value);
}

fn patchModuleNamespaceExport(ctx: *quickjs.Context, target: quickjs.Value, property_key: quickjs.Value, replacement: quickjs.Value) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const patch_fn = global.getPropertyStr(ctx, "__zigPatchLoadedModuleExportByNamespace");
    defer patch_fn.deinit(ctx);
    if (patch_fn.isException() or !patch_fn.isFunction(ctx)) return false;

    var args = [_]quickjs.Value{ target.dup(ctx), property_key.dup(ctx), replacement.dup(ctx) };
    defer {
        args[0].deinit(ctx);
        args[1].deinit(ctx);
        args[2].deinit(ctx);
    }

    const result = patch_fn.call(ctx, global, &args);
    defer result.deinit(ctx);
    if (result.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        return false;
    }
    return result.toBool(ctx) catch false;
}

fn findExistingMockState(mocks: *HostMocks, ctx: *quickjs.Context, target: quickjs.Value, property_key: quickjs.Value) ?*MockState {
    for (mocks.mock_states.items) |state| {
        if (state.disposed or !state.has_restore) continue;
        if (!state.restore_target.isObject()) continue;
        if (!state.restore_property.isString()) continue;
        if (!state.restore_target.isSameValue(ctx, target)) continue;
        if (!state.restore_property.isSameValue(ctx, property_key)) continue;
        return state;
    }
    return null;
}

fn mirrorGlobalWindowProperty(ctx: *quickjs.Context, target: quickjs.Value, property_key: quickjs.Value, expected_current: quickjs.Value, replacement: quickjs.Value) void {
    _ = expected_current;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const window = global.getPropertyStr(ctx, "window");
    defer window.deinit(ctx);
    if (!window.isObject()) return;

    const atom = quickjs.Atom.fromValue(ctx, property_key);
    defer atom.deinit(ctx);

    if (target.isSameValue(ctx, window)) {
        _ = quickjs.c.JS_DefinePropertyValue(
            ctx.cval(),
            global.cval(),
            @intFromEnum(atom),
            replacement.dup(ctx).cval(),
            quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_WRITABLE | quickjs.c.JS_PROP_ENUMERABLE,
        );
        return;
    }

    if (!target.isSameValue(ctx, global)) return;

    _ = quickjs.c.JS_DefinePropertyValue(
        ctx.cval(),
        window.cval(),
        @intFromEnum(atom),
        replacement.dup(ctx).cval(),
        quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_WRITABLE | quickjs.c.JS_PROP_ENUMERABLE,
    );
}

fn jsBunPlugin(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.exception;
    if (args.len == 0) return ctx.throwInternalError("plugin() requires a plugin definition object");
    const definition = quickjs.Value.fromCVal(args[0]);
    if (!definition.isObject()) return ctx.throwInternalError("plugin() requires a plugin definition object");
    const setup = definition.getPropertyStr(ctx, "setup");
    defer setup.deinit(ctx);
    if (setup.isFunction(ctx)) {
        const build = quickjs.Value.initObject(ctx);
        if (build.isException()) return quickjs.Value.exception;
        defer build.deinit(ctx);
        setFunction(ctx, build, "onLoad", jsBuildOnLoad, 2) catch return quickjs.Value.exception;
        var call_args = [_]quickjs.Value{build.dup(ctx)};
        defer call_args[0].deinit(ctx);
        const result = setup.call(ctx, definition, &call_args);
        defer result.deinit(ctx);
        if (result.isException()) return quickjs.Value.exception;
    }
    _ = mocks;
    return definition.dup(ctx);
}

fn jsBuildOnLoad(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.exception;
    if (args.len < 2) return ctx.throwInternalError("build.onLoad() requires options and callback");
    const options = quickjs.Value.fromCVal(args[0]);
    const callback = quickjs.Value.fromCVal(args[1]);
    const filter = options.getPropertyStr(ctx, "filter");
    defer filter.deinit(ctx);
    if (!filter.isObject() or !callback.isFunction(ctx)) return ctx.throwInternalError("build.onLoad() requires filter and callback");
    mocks.on_load_hooks.append(mocks.allocator, .{ .filter = filter.dup(ctx), .callback = callback.dup(ctx) }) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsApplyOnLoad(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.exception;
    const path = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    for (mocks.on_load_hooks.items) |hook| {
        const test_fn = hook.filter.getPropertyStr(ctx, "test");
        defer test_fn.deinit(ctx);
        if (!test_fn.isFunction(ctx)) continue;
        var test_args = [_]quickjs.Value{path.dup(ctx)};
        defer test_args[0].deinit(ctx);
        const matched = test_fn.call(ctx, hook.filter, &test_args);
        defer matched.deinit(ctx);
        if (!(matched.toBool(ctx) catch false)) continue;
        const request = quickjs.Value.initObject(ctx);
        if (request.isException()) return quickjs.Value.exception;
        defer request.deinit(ctx);
        request.setPropertyStr(ctx, "path", path.dup(ctx)) catch return quickjs.Value.exception;
        var call_args = [_]quickjs.Value{request.dup(ctx)};
        defer call_args[0].deinit(ctx);
        var result = hook.callback.call(ctx, quickjs.Value.undefined, &call_args);
        defer result.deinit(ctx);
        if (result.isException()) return quickjs.Value.exception;
        if (result.isPromise()) {
            result = awaitPromise(ctx, mocks.rt, result) catch return quickjs.Value.exception;
        }
        const contents = result.getPropertyStr(ctx, "contents");
        defer contents.deinit(ctx);
        if (!contents.isUndefined() and !contents.isNull()) return result.dup(ctx);
    }
    return quickjs.Value.null;
}

fn jsBunShellTag(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    return ctx.throwInternalError("bun.$ shell execution is not implemented in this runner");
}

fn jsBunFile(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    return ctx.throwInternalError("bun.file() is not implemented in this runner");
}

fn jsMockMethod(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue, magic: i32, _: [*c]quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.exception;
    const state = this_value.getOpaque(MockState, mocks.mock_class_id) orelse return quickjs.Value.exception;
    const method: MockMethod = @enumFromInt(magic);
    switch (method) {
        .implementation => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            if (!next.isFunction(ctx)) return ctx.throwInternalError("mockImplementation() requires a function");
            replaceValue(ctx, &state.implementation, next);
            clearModes(ctx, state, false);
        },
        .implementation_once => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            if (!next.isFunction(ctx)) return ctx.throwInternalError("mockImplementationOnce() requires a function");
            pushArrayValue(ctx, state.once_implementations, next) catch return quickjs.Value.exception;
        },
        .return_value_once => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            appendOnceValue(ctx, state, .return_value, next) catch return quickjs.Value.exception;
        },
        .return_value => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            replaceValue(ctx, &state.return_value, next);
            state.implementation.deinit(ctx);
            state.implementation = quickjs.Value.undefined;
            state.has_return_value = true;
            state.has_resolved_value = false;
            state.has_rejected_value = false;
        },
        .resolved_value_once => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            appendOnceValue(ctx, state, .resolved_value, next) catch return quickjs.Value.exception;
        },
        .resolved_value => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            replaceValue(ctx, &state.resolved_value, next);
            state.implementation.deinit(ctx);
            state.implementation = quickjs.Value.undefined;
            state.has_return_value = false;
            state.has_resolved_value = true;
            state.has_rejected_value = false;
        },
        .rejected_value_once => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            appendOnceValue(ctx, state, .rejected_value, next) catch return quickjs.Value.exception;
        },
        .rejected_value => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            replaceValue(ctx, &state.rejected_value, next);
            state.implementation.deinit(ctx);
            state.implementation = quickjs.Value.undefined;
            state.has_return_value = false;
            state.has_resolved_value = false;
            state.has_rejected_value = true;
        },
        .clear => {
            state.calls.setLength(ctx, 0) catch return quickjs.Value.exception;
            setMockLastCall(ctx, this_value, quickjs.Value.undefined) catch return quickjs.Value.exception;
        },
        .reset => {
            state.calls.setLength(ctx, 0) catch return quickjs.Value.exception;
            state.once_implementations.setLength(ctx, 0) catch return quickjs.Value.exception;
            setMockLastCall(ctx, this_value, quickjs.Value.undefined) catch return quickjs.Value.exception;
            replaceValue(ctx, &state.implementation, state.original_implementation);
            clearModes(ctx, state, true);
        },
        .restore => {
            restoreMockState(ctx, state, this_value) catch return quickjs.Value.exception;
        },
    }
    return this_value.dup(ctx);
}

fn jsMockDispose(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const mocks = active_mocks orelse return quickjs.Value.undefined;
    const state = this_value.getOpaque(MockState, mocks.mock_class_id) orelse return quickjs.Value.undefined;
    restoreMockState(ctx, state, this_value) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn restoreMockState(ctx: *quickjs.Context, state: *MockState, this_value: quickjs.Value) !void {
    if (state.has_restore) {
        const atom = quickjs.Atom.fromValue(ctx, state.restore_property);
        defer atom.deinit(ctx);
        if (state.restore_getter) {
            _ = quickjs.c.JS_DefinePropertyGetSet(
                ctx.cval(),
                state.restore_target.cval(),
                @intFromEnum(atom),
                state.restore_value.dup(ctx).cval(),
                quickjs.Value.undefined.cval(),
                quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_ENUMERABLE,
            );
        } else {
            _ = quickjs.c.JS_DefinePropertyValue(
                ctx.cval(),
                state.restore_target.cval(),
                @intFromEnum(atom),
                state.restore_value.dup(ctx).cval(),
                quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_WRITABLE | quickjs.c.JS_PROP_ENUMERABLE,
            );
            mirrorGlobalWindowProperty(ctx, state.restore_target, state.restore_property, this_value, state.restore_value);
        }
    }
    state.calls.setLength(ctx, 0) catch return error.JSError;
    state.once_implementations.setLength(ctx, 0) catch return error.JSError;
    setMockLastCall(ctx, this_value, quickjs.Value.undefined) catch return error.JSError;
    replaceValue(ctx, &state.implementation, state.original_implementation);
    clearModes(ctx, state, true);
}

fn installMockMethod(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, method: MockMethod, state: *MockState) HostMocksError!void {
    _ = state;
    var data = [_]quickjs.Value{};
    const func = quickjs.Value.initCFunctionData2(ctx, jsMockMethod, name, 1, @intFromEnum(method), &data);
    if (func.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, func) catch return error.JSError;
}

fn installMockSymbolDispose(ctx: *quickjs.Context, object: quickjs.Value) HostMocksError!void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const symbol_ctor = global.getPropertyStr(ctx, "Symbol");
    defer symbol_ctor.deinit(ctx);
    if (symbol_ctor.isException() or !symbol_ctor.isObject()) return;

    var dispose_symbol = symbol_ctor.getPropertyStr(ctx, "dispose");
    defer dispose_symbol.deinit(ctx);
    if (dispose_symbol.isException() or dispose_symbol.isUndefined() or dispose_symbol.isNull()) {
        const symbol_for = symbol_ctor.getPropertyStr(ctx, "for");
        defer symbol_for.deinit(ctx);
        if (symbol_for.isException() or !symbol_for.isFunction(ctx)) return;

        var args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, "Symbol.dispose")};
        defer args[0].deinit(ctx);
        const fallback_symbol = symbol_for.call(ctx, symbol_ctor, &args);
        if (fallback_symbol.isException() or fallback_symbol.isUndefined() or fallback_symbol.isNull()) {
            fallback_symbol.deinit(ctx);
            return;
        }
        dispose_symbol.deinit(ctx);
        dispose_symbol = fallback_symbol;
    }

    const atom = quickjs.Atom.fromValue(ctx, dispose_symbol);
    defer atom.deinit(ctx);

    const dispose_fn = quickjs.Value.initCFunction(ctx, jsMockDispose, "__zigMockDispose", 0);
    if (dispose_fn.isException()) return error.JSError;
    object.setProperty(ctx, atom, dispose_fn) catch return error.JSError;
}

fn setMockLastCall(ctx: *quickjs.Context, mock_function: quickjs.Value, value: quickjs.Value) !void {
    const mock_info = mock_function.getPropertyStr(ctx, "mock");
    defer mock_info.deinit(ctx);
    if (mock_info.isException() or !mock_info.isObject()) return error.JSError;
    mock_info.setPropertyStr(ctx, "lastCall", value.dup(ctx)) catch return error.JSError;
}

fn appendOnceValue(ctx: *quickjs.Context, state: *MockState, mode: OnceMode, value: quickjs.Value) !void {
    const entry = quickjs.Value.initObject(ctx);
    if (entry.isException()) return error.JSError;
    defer entry.deinit(ctx);
    entry.setPropertyStr(ctx, "__zigMockOnceMode", quickjs.Value.initInt32(@intFromEnum(mode))) catch return error.JSError;
    entry.setPropertyStr(ctx, "value", value.dup(ctx)) catch return error.JSError;
    pushArrayValue(ctx, state.once_implementations, entry) catch return error.JSError;
}

fn replaceValue(ctx: *quickjs.Context, slot: *quickjs.Value, next: quickjs.Value) void {
    slot.deinit(ctx);
    slot.* = next.dup(ctx);
}

fn clearModes(ctx: *quickjs.Context, state: *MockState, clear_values: bool) void {
    state.has_return_value = false;
    state.has_resolved_value = false;
    state.has_rejected_value = false;
    if (clear_values) {
        replaceValue(ctx, &state.return_value, quickjs.Value.undefined);
        replaceValue(ctx, &state.resolved_value, quickjs.Value.undefined);
        replaceValue(ctx, &state.rejected_value, quickjs.Value.undefined);
    }
}

fn resolvedPromise(ctx: *quickjs.Context, value: quickjs.Value) quickjs.Value {
    const promise = quickjs.Value.initPromiseCapability(ctx);
    var args = [_]quickjs.Value{value.dup(ctx)};
    defer args[0].deinit(ctx);
    const result = promise.resolve.call(ctx, quickjs.Value.undefined, &args);
    result.deinit(ctx);
    const out = promise.value.dup(ctx);
    promise.deinit(ctx);
    return out;
}

fn rejectedPromise(ctx: *quickjs.Context, value: quickjs.Value) quickjs.Value {
    const promise = quickjs.Value.initPromiseCapability(ctx);
    var args = [_]quickjs.Value{value.dup(ctx)};
    defer args[0].deinit(ctx);
    const result = promise.reject.call(ctx, quickjs.Value.undefined, &args);
    result.deinit(ctx);
    const out = promise.value.dup(ctx);
    promise.deinit(ctx);
    return out;
}

fn awaitPromise(ctx: *quickjs.Context, rt: *quickjs.Runtime, promise: quickjs.Value) !quickjs.Value {
    var iterations: usize = 0;
    while (promise.promiseState(ctx) == .pending) : (iterations += 1) {
        if (!rt.isJobPending() or iterations > 100_000) return error.JSError;
        _ = rt.executePendingJob() catch return error.JSError;
    }
    return switch (promise.promiseState(ctx)) {
        .fulfilled => promise.promiseResult(ctx),
        .rejected => blk: {
            const rejection = promise.promiseResult(ctx);
            _ = rejection.throw(ctx);
            break :blk error.JSError;
        },
        else => error.JSError,
    };
}

fn buildMockModuleSource(allocator: Allocator, ctx: *quickjs.Context, specifier: []const u8, exports_value: quickjs.Value) ![]u8 {
    var builder: std.ArrayList(u8) = .empty;
    errdefer builder.deinit(allocator);
    const specifier_json = try jsonString(allocator, specifier);
    defer allocator.free(specifier_json);
    try builder.print(allocator, "const value = globalThis.__zigRunnerMockExports[{s}];\n", .{specifier_json});
    try builder.appendSlice(allocator, "const moduleExports = value && (typeof value === 'object' || typeof value === 'function') ? value : { default: value };\n");
    if (exports_value.isObject()) {
        const keys = objectKeys(ctx, exports_value);
        defer keys.deinit(ctx);
        const length = keys.getLength(ctx) catch 0;
        var index: i64 = 0;
        while (index < length) : (index += 1) {
            const key = keys.getPropertyUint32(ctx, @intCast(index));
            defer key.deinit(ctx);
            const name_text = key.toCStringLen(ctx) orelse continue;
            defer ctx.freeCString(name_text.ptr);
            const name = name_text.ptr[0..name_text.len];
            if (std.mem.eql(u8, name, "default") or !isIdentifierName(name)) continue;
            const name_json = try jsonString(allocator, name);
            defer allocator.free(name_json);
            try builder.print(allocator, "export const {s} = moduleExports[{s}];\n", .{ name, name_json });
        }
    }
    try builder.appendSlice(allocator, "export default Object.prototype.hasOwnProperty.call(moduleExports, 'default') ? moduleExports.default : moduleExports;\n");
    return builder.toOwnedSlice(allocator);
}

fn objectKeys(ctx: *quickjs.Context, value: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const object_ctor = global.getPropertyStr(ctx, "Object");
    defer object_ctor.deinit(ctx);
    const keys_fn = object_ctor.getPropertyStr(ctx, "keys");
    defer keys_fn.deinit(ctx);
    if (!keys_fn.isFunction(ctx)) return quickjs.Value.initArray(ctx);
    var args = [_]quickjs.Value{value.dup(ctx)};
    defer args[0].deinit(ctx);
    return keys_fn.call(ctx, object_ctor, &args);
}

fn getOwnPropertyDescriptor(ctx: *quickjs.Context, target: quickjs.Value, property: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const object_ctor = global.getPropertyStr(ctx, "Object");
    defer object_ctor.deinit(ctx);
    const descriptor_fn = object_ctor.getPropertyStr(ctx, "getOwnPropertyDescriptor");
    defer descriptor_fn.deinit(ctx);
    if (!descriptor_fn.isFunction(ctx)) return quickjs.Value.undefined;
    var args = [_]quickjs.Value{ target.dup(ctx), property.dup(ctx) };
    defer {
        args[0].deinit(ctx);
        args[1].deinit(ctx);
    }
    return descriptor_fn.call(ctx, object_ctor, &args);
}

fn isIdentifierName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!(std.ascii.isAlphabetic(name[0]) or name[0] == '_' or name[0] == '$')) return false;
    for (name[1..]) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$')) return false;
    }
    return true;
}

fn jsonString(allocator: Allocator, text: []const u8) ![]u8 {
    var builder: std.ArrayList(u8) = .empty;
    errdefer builder.deinit(allocator);
    try builder.append(allocator, '"');
    for (text) |ch| switch (ch) {
        '\\' => try builder.appendSlice(allocator, "\\\\"),
        '"' => try builder.appendSlice(allocator, "\\\""),
        '\n' => try builder.appendSlice(allocator, "\\n"),
        '\r' => try builder.appendSlice(allocator, "\\r"),
        '\t' => try builder.appendSlice(allocator, "\\t"),
        else => try builder.append(allocator, ch),
    };
    try builder.append(allocator, '"');
    return builder.toOwnedSlice(allocator);
}

fn setFunction(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) HostMocksError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

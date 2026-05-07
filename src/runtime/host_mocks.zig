const std = @import("std");
const quickjs = @import("quickjs");

const Allocator = std.mem.Allocator;

pub const HostMocksError = error{ OutOfMemory, JSError };

var active_mocks: ?*HostMocks = null;

const MockState = struct {
    owner: *HostMocks,
    calls: quickjs.Value,
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
        self.calls.deinitRT(rt);
        self.implementation.deinitRT(rt);
        self.original_implementation.deinitRT(rt);
        self.return_value.deinitRT(rt);
        self.resolved_value.deinitRT(rt);
        self.rejected_value.deinitRT(rt);
        self.restore_target.deinitRT(rt);
        self.restore_property.deinitRT(rt);
        self.restore_value.deinitRT(rt);
        self.disposed = true;
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
        inline for (.{ "__zigRunnerMockExports", "__zigMockModuleManifestJson", "__zigMock", "mock", "__zigSpyOn", "spyOn", "__zigRunnerApplyOnLoad", "__zigBunApi", "Bun" }) |name| {
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

        const bun_api = quickjs.Value.initObject(ctx);
        if (bun_api.isException()) return error.OutOfMemory;
        try setFunction(ctx, bun_api, "plugin", jsBunPlugin, 1);
        try setFunction(ctx, bun_api, "$", jsBunShellTag, 0);
        try setFunction(ctx, bun_api, "file", jsBunFile, 1);
        global.setPropertyStr(ctx, "__zigBunApi", bun_api.dup(ctx)) catch return error.JSError;
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
            .calls = quickjs.Value.initArray(ctx),
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

        const mock_info = quickjs.Value.initObject(ctx);
        if (mock_info.isException()) return quickjs.Value.exception;
        mock_info.setPropertyStr(ctx, "calls", state.calls.dup(ctx)) catch return quickjs.Value.exception;
        func.setPropertyStr(ctx, "mock", mock_info) catch return quickjs.Value.exception;

        installMockMethod(ctx, func, "mockImplementation", .implementation, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockReturnValue", .return_value, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockResolvedValue", .resolved_value, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockRejectedValue", .rejected_value, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockClear", .clear, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockReset", .reset, state) catch return quickjs.Value.exception;
        installMockMethod(ctx, func, "mockRestore", .restore, state) catch return quickjs.Value.exception;
        return func;
    }

    fn putMockModuleSource(self: *HostMocks, specifier: []const u8, source: []const u8) !void {
        const key = try self.allocator.dupe(u8, specifier);
        errdefer self.allocator.free(key);
        const value = try self.allocator.dupe(u8, source);
        errdefer self.allocator.free(value);

        if (try self.mock_module_sources.fetchPut(key, value)) |previous| {
            self.allocator.free(previous.key);
            self.allocator.free(previous.value);
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

    const args_slice: []const quickjs.Value = if (argc > 0) @ptrCast(argv[0..@intCast(argc)]) else &.{};
    if (state.implementation.isFunction(real_ctx)) {
        return state.implementation.call(real_ctx, wrapped_this, args_slice).cval();
    }
    if (state.has_return_value) return state.return_value.dup(real_ctx).cval();
    if (state.has_resolved_value) return resolvedPromise(real_ctx, state.resolved_value).cval();
    if (state.has_rejected_value) return rejectedPromise(real_ctx, state.rejected_value).cval();
    return quickjs.Value.undefined.cval();
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
    if (!current.isFunction(ctx)) {
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
    const atom = quickjs.Atom.fromValue(ctx, property_key);
    defer atom.deinit(ctx);
    _ = quickjs.c.JS_DefinePropertyValue(ctx.cval(), target.cval(), @intFromEnum(atom), wrapped.dup(ctx).cval(), quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_WRITABLE | quickjs.c.JS_PROP_ENUMERABLE);
    return wrapped;
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
        .return_value => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            replaceValue(ctx, &state.return_value, next);
            state.implementation.deinit(ctx);
            state.implementation = quickjs.Value.undefined;
            state.has_return_value = true;
            state.has_resolved_value = false;
            state.has_rejected_value = false;
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
        .rejected_value => {
            const next = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
            replaceValue(ctx, &state.rejected_value, next);
            state.implementation.deinit(ctx);
            state.implementation = quickjs.Value.undefined;
            state.has_return_value = false;
            state.has_resolved_value = false;
            state.has_rejected_value = true;
        },
        .clear => state.calls.setLength(ctx, 0) catch return quickjs.Value.exception,
        .reset => {
            state.calls.setLength(ctx, 0) catch return quickjs.Value.exception;
            replaceValue(ctx, &state.implementation, state.original_implementation);
            clearModes(ctx, state, true);
        },
        .restore => {
            if (state.has_restore) {
                const atom = quickjs.Atom.fromValue(ctx, state.restore_property);
                defer atom.deinit(ctx);
                if (state.restore_getter) {
                    _ = quickjs.c.JS_DefinePropertyGetSet(ctx.cval(), state.restore_target.cval(), @intFromEnum(atom), state.restore_value.dup(ctx).cval(), quickjs.Value.undefined.cval(), quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_ENUMERABLE);
                } else {
                    _ = quickjs.c.JS_DefinePropertyValue(ctx.cval(), state.restore_target.cval(), @intFromEnum(atom), state.restore_value.dup(ctx).cval(), quickjs.c.JS_PROP_CONFIGURABLE | quickjs.c.JS_PROP_WRITABLE | quickjs.c.JS_PROP_ENUMERABLE);
                }
            }
            state.calls.setLength(ctx, 0) catch return quickjs.Value.exception;
            replaceValue(ctx, &state.implementation, state.original_implementation);
            clearModes(ctx, state, true);
        },
    }
    return this_value.dup(ctx);
}

fn installMockMethod(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, method: MockMethod, state: *MockState) HostMocksError!void {
    _ = state;
    var data = [_]quickjs.Value{};
    const func = quickjs.Value.initCFunctionData2(ctx, jsMockMethod, name, 1, @intFromEnum(method), &data);
    if (func.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, func) catch return error.JSError;
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

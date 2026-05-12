const std = @import("std");
const quickjs = @import("quickjs");
const platform = @import("platform.zig");

pub const TestingLibraryReactError = error{ OutOfMemory, JSError };

const FamilyDef = struct { suffix: []const u8 };
const ModeDef = struct { prefix: []const u8 };

const families = [_]FamilyDef{
    .{ .suffix = "Text" },
    .{ .suffix = "TestId" },
    .{ .suffix = "LabelText" },
    .{ .suffix = "Role" },
    .{ .suffix = "DisplayValue" },
    .{ .suffix = "PlaceholderText" },
    .{ .suffix = "Title" },
    .{ .suffix = "AltText" },
};

const modes = [_]ModeDef{
    .{ .prefix = "queryBy" },
    .{ .prefix = "queryAllBy" },
    .{ .prefix = "getBy" },
    .{ .prefix = "getAllBy" },
    .{ .prefix = "findBy" },
    .{ .prefix = "findAllBy" },
};

const default_flush_turns: i64 = 48;

pub fn install(ctx: *quickjs.Context) TestingLibraryReactError!void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const dom_api = global.getPropertyStr(ctx, "__zigTestingLibraryDom");
    defer dom_api.deinit(ctx);
    if (!dom_api.isObject()) return error.JSError;

    const api = quickjs.Value.initObject(ctx);
    if (api.isException()) return error.OutOfMemory;
    defer api.deinit(ctx);

    try copyProperty(ctx, api, dom_api, "screen");
    try copyProperty(ctx, api, dom_api, "within");
    try copyProperty(ctx, api, dom_api, "fireEvent");
    try copyProperty(ctx, api, dom_api, "cleanup");
    try copyProperty(ctx, api, dom_api, "waitFor");
    try copyProperty(ctx, api, dom_api, "waitForElementToBeRemoved");
    try copyProperty(ctx, api, dom_api, "getConfig");
    try copyProperty(ctx, api, dom_api, "configure");
    try copyProperty(ctx, api, dom_api, "setConfig");
    try copyProperty(ctx, api, dom_api, "queries");

    for (modes) |mode| {
        for (families) |family| {
            const method_name = std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}", .{ mode.prefix, family.suffix }) catch return error.OutOfMemory;
            defer std.heap.c_allocator.free(method_name);
            try copyProperty(ctx, api, dom_api, method_name);
        }
    }

    try setFunction(ctx, api, "render", jsRender, 2);
    try setFunction(ctx, api, "renderHook", jsRenderHook, 2);
    try setFunction(ctx, api, "cleanup", jsCleanup, 0);

    try setFunction(ctx, api, "act", jsActFallback, 1);

    registerAutoCleanup(ctx, global);
    global.setPropertyStr(ctx, "__zigTestingLibraryReact", api.dup(ctx)) catch return error.JSError;
}

fn registerAutoCleanup(ctx: *quickjs.Context, global: quickjs.Value) void {
    const installed = global.getPropertyStr(ctx, "__zigTestingLibraryReactAutoCleanupInstalled");
    defer installed.deinit(ctx);
    if (!installed.isException() and (installed.toBool(ctx) catch false)) return;

    const after_each = global.getPropertyStr(ctx, "afterEach");
    defer after_each.deinit(ctx);
    if (!after_each.isFunction(ctx)) return;

    const cleanup = quickjs.Value.initCFunction(ctx, jsCleanup, "__zigTestingLibraryAutoCleanup", 0);
    if (cleanup.isException()) return;
    defer cleanup.deinit(ctx);

    var call_args = [_]quickjs.Value{cleanup.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = after_each.call(ctx, quickjs.Value.undefined, &call_args);
    defer result.deinit(ctx);
    if (result.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        return;
    }

    global.setPropertyStr(ctx, "__zigTestingLibraryReactAutoCleanupInstalled", quickjs.Value.initBool(true)) catch {};
}

fn jsRender(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const ui = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const options = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    const wrapper = if (options.isObject()) options.getPropertyStr(ctx, "wrapper") else quickjs.Value.undefined;
    defer wrapper.deinit(ctx);

    const parsed = resolveRenderTargets(ctx, options) orelse return quickjs.Value.exception;
    defer parsed.deinit(ctx);

    const react_dom_client = requireModule(ctx, "react-dom/client");
    defer react_dom_client.deinit(ctx);
    if (react_dom_client.isException()) return quickjs.Value.exception;

    const create_root = moduleMember(ctx, react_dom_client, "createRoot");
    defer create_root.deinit(ctx);
    if (!create_root.isFunction(ctx)) return throwMessage(ctx, "react-dom/client.createRoot is unavailable");

    var create_root_args = [_]quickjs.Value{parsed.container.dup(ctx)};
    const root = create_root.call(ctx, react_dom_client, &create_root_args);
    defer root.deinit(ctx);
    if (root.isException()) return quickjs.Value.exception;

    const tree = buildRenderTree(ctx, ui, wrapper);
    defer tree.deinit(ctx);
    if (tree.isException()) return quickjs.Value.exception;
    if (!callRootRender(ctx, root, tree)) return quickjs.Value.exception;
    if (!flushWork(ctx, default_flush_turns)) return quickjs.Value.exception;

    if (!trackRoot(ctx, root, parsed.container, parsed.managed_container)) return quickjs.Value.exception;

    const within_result = callDomWithin(ctx, parsed.base_element) orelse return quickjs.Value.exception;
    defer within_result.deinit(ctx);

    const out = within_result.dup(ctx);
    out.setPropertyStr(ctx, "container", parsed.container.dup(ctx)) catch return quickjs.Value.exception;
    out.setPropertyStr(ctx, "baseElement", parsed.base_element.dup(ctx)) catch return quickjs.Value.exception;

    var debug_data = [_]quickjs.Value{parsed.base_element.dup(ctx)};
    const debug_fn = quickjs.Value.initCFunctionData2(ctx, jsRenderDebug, "__zigTestingLibraryDebug", 0, 0, &debug_data);
    if (debug_fn.isException()) return quickjs.Value.exception;
    out.setPropertyStr(ctx, "debug", debug_fn) catch return quickjs.Value.exception;

    var rerender_data = [_]quickjs.Value{
        root.dup(ctx),
        wrapper.dup(ctx),
    };
    const rerender_fn = quickjs.Value.initCFunctionData2(ctx, jsRenderRerender, "__zigTestingLibraryRerender", 1, 0, &rerender_data);
    if (rerender_fn.isException()) return quickjs.Value.exception;
    out.setPropertyStr(ctx, "rerender", rerender_fn) catch return quickjs.Value.exception;

    var unmount_data = [_]quickjs.Value{
        root.dup(ctx),
        parsed.container.dup(ctx),
        quickjs.Value.initBool(parsed.managed_container),
    };
    const unmount_fn = quickjs.Value.initCFunctionData2(ctx, jsRenderUnmount, "__zigTestingLibraryUnmount", 0, 0, &unmount_data);
    if (unmount_fn.isException()) return quickjs.Value.exception;
    out.setPropertyStr(ctx, "unmount", unmount_fn) catch return quickjs.Value.exception;

    return out;
}

const RenderTargets = struct {
    container: quickjs.Value,
    base_element: quickjs.Value,
    managed_container: bool,

    fn deinit(self: RenderTargets, ctx: *quickjs.Context) void {
        self.container.deinit(ctx);
        self.base_element.deinit(ctx);
    }
};

fn resolveRenderTargets(ctx: *quickjs.Context, options: quickjs.Value) ?RenderTargets {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (!document.isObject()) return null;

    var container: quickjs.Value = quickjs.Value.undefined;
    var base_element: quickjs.Value = quickjs.Value.undefined;
    var managed = false;

    if (options.isObject()) {
        container = options.getPropertyStr(ctx, "container");
        if (container.isException()) {
            const exception = ctx.getException();
            exception.deinit(ctx);
            container = quickjs.Value.undefined;
        }
        base_element = options.getPropertyStr(ctx, "baseElement");
        if (base_element.isException()) {
            const exception = ctx.getException();
            exception.deinit(ctx);
            base_element = quickjs.Value.undefined;
        }
    }

    if (!container.isObject()) {
        const create = document.getPropertyStr(ctx, "createElement");
        defer create.deinit(ctx);
        if (!create.isFunction(ctx)) return null;
        var args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, "div")};
        defer args[0].deinit(ctx);
        container.deinit(ctx);
        container = create.call(ctx, document, &args);
        if (!container.isObject()) return null;
        managed = true;

        const body = document.getPropertyStr(ctx, "body");
        defer body.deinit(ctx);
        if (body.isObject()) {
            const append = body.getPropertyStr(ctx, "appendChild");
            defer append.deinit(ctx);
            if (append.isFunction(ctx)) {
                var append_args = [_]quickjs.Value{container.dup(ctx)};
                const append_result = append.call(ctx, body, &append_args);
                append_result.deinit(ctx);
            }
        }
    }

    if (!base_element.isObject()) {
        base_element.deinit(ctx);
        const body = document.getPropertyStr(ctx, "body");
        if (!body.isException() and body.isObject()) {
            base_element = body;
        } else {
            if (body.isException()) {
                const exception = ctx.getException();
                exception.deinit(ctx);
            }
            base_element = document.dup(ctx);
        }
    }

    return .{
        .container = container,
        .base_element = base_element,
        .managed_container = managed,
    };
}

fn jsRenderRerender(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    data_len: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const root = quickjs.Value.fromCVal(data[0]);
    const wrapper = if (data_len > 1) quickjs.Value.fromCVal(data[1]) else quickjs.Value.undefined;
    const next_ui = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const tree = buildRenderTree(ctx, next_ui, wrapper);
    defer tree.deinit(ctx);
    if (tree.isException()) return quickjs.Value.exception;
    if (!callRootRender(ctx, root, tree)) return quickjs.Value.exception;
    if (!flushWork(ctx, default_flush_turns)) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsRenderDebug(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const base = quickjs.Value.fromCVal(data[0]);
    const outer_html = base.getPropertyStr(ctx, "outerHTML");
    defer outer_html.deinit(ctx);
    if (outer_html.isException()) return quickjs.Value.undefined;
    return outer_html.dup(ctx);
}

fn jsRenderUnmount(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const root = quickjs.Value.fromCVal(data[0]);
    const container = quickjs.Value.fromCVal(data[1]);
    const managed = quickjs.Value.fromCVal(data[2]).toBool(ctx) catch false;

    if (!callRootUnmount(ctx, root)) return quickjs.Value.exception;
    if (!flushWork(ctx, default_flush_turns)) return quickjs.Value.exception;

    if (managed and container.isObject()) {
        const parent = container.getPropertyStr(ctx, "parentNode");
        defer parent.deinit(ctx);
        if (parent.isObject()) {
            const remove = parent.getPropertyStr(ctx, "removeChild");
            defer remove.deinit(ctx);
            if (remove.isFunction(ctx)) {
                var call_args = [_]quickjs.Value{container.dup(ctx)};
                const remove_result = remove.call(ctx, parent, &call_args);
                remove_result.deinit(ctx);
            }
        }
    }

    clearTrackedRoot(ctx, root);
    return quickjs.Value.undefined;
}

fn jsCleanup(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const roots = trackedRoots(ctx) orelse return quickjs.Value.undefined;
    defer roots.deinit(ctx);

    const count = arrayLength(ctx, roots);
    var index: i64 = 0;
    while (index < count) : (index += 1) {
        const record = roots.getPropertyUint32(ctx, @intCast(index));
        defer record.deinit(ctx);
        if (!record.isObject()) continue;

        const root = record.getPropertyStr(ctx, "root");
        defer root.deinit(ctx);
        const container = record.getPropertyStr(ctx, "container");
        defer container.deinit(ctx);
        const managed = record.getPropertyStr(ctx, "managed");
        defer managed.deinit(ctx);

        if (root.isObject()) {
            if (!callRootUnmount(ctx, root)) {
                const exception = ctx.getException();
                exception.deinit(ctx);
            }
            if (!flushWork(ctx, default_flush_turns)) {
                const exception = ctx.getException();
                exception.deinit(ctx);
            }
        }

        if ((managed.toBool(ctx) catch false) and container.isObject()) {
            const parent = container.getPropertyStr(ctx, "parentNode");
            defer parent.deinit(ctx);
            if (parent.isObject()) {
                const remove = parent.getPropertyStr(ctx, "removeChild");
                defer remove.deinit(ctx);
                if (remove.isFunction(ctx)) {
                    var remove_args = [_]quickjs.Value{container.dup(ctx)};
                    const remove_result = remove.call(ctx, parent, &remove_args);
                    remove_result.deinit(ctx);
                }
            }
        }
    }

    roots.setPropertyStr(ctx, "length", quickjs.Value.initInt32(0)) catch {
        const exception = ctx.getException();
        exception.deinit(ctx);
    };
    if (!flushWork(ctx, 12)) {
        const exception = ctx.getException();
        exception.deinit(ctx);
    }
    return quickjs.Value.undefined;
}

fn callRootUnmount(ctx: *quickjs.Context, root: quickjs.Value) bool {
    const unmount = root.getPropertyStr(ctx, "unmount");
    defer unmount.deinit(ctx);
    if (!unmount.isFunction(ctx)) return true;

    if (installedAct(ctx)) |act| {
        defer act.deinit(ctx);
        var callback_data = [_]quickjs.Value{root.dup(ctx)};
        const callback = quickjs.Value.initCFunctionData2(ctx, jsActUnmountCallback, "__zigActUnmountCallback", 0, 0, &callback_data);
        if (callback.isException()) return false;
        defer callback.deinit(ctx);

        var act_args = [_]quickjs.Value{callback.dup(ctx)};
        const act_result = act.call(ctx, quickjs.Value.undefined, &act_args);
        defer act_result.deinit(ctx);
        if (act_result.isException()) return false;
        if (act_result.isPromise()) {
            if (!flushWork(ctx, default_flush_turns)) return false;
        }
        return true;
    }

    const result = unmount.call(ctx, root, &.{});
    defer result.deinit(ctx);
    if (result.isException()) return false;
    return true;
}

fn jsActUnmountCallback(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const root = quickjs.Value.fromCVal(data[0]);
    const unmount = root.getPropertyStr(ctx, "unmount");
    defer unmount.deinit(ctx);
    if (!unmount.isFunction(ctx)) return quickjs.Value.undefined;
    const result = unmount.call(ctx, root, &.{});
    defer result.deinit(ctx);
    if (result.isException()) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsRenderHook(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return throwMessage(ctx, "renderHook expects a callback");

    const callback = quickjs.Value.fromCVal(args[0]);
    if (!callback.isFunction(ctx)) return throwMessage(ctx, "renderHook callback must be a function");
    const options = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;

    const parsed = resolveRenderTargets(ctx, options) orelse return quickjs.Value.exception;
    defer parsed.deinit(ctx);

    const wrapper = if (options.isObject()) options.getPropertyStr(ctx, "wrapper") else quickjs.Value.undefined;
    defer wrapper.deinit(ctx);

    const initial_props = if (options.isObject()) options.getPropertyStr(ctx, "initialProps") else quickjs.Value.undefined;
    defer initial_props.deinit(ctx);

    const react_module = requireModule(ctx, "react");
    defer react_module.deinit(ctx);
    if (react_module.isException()) return quickjs.Value.exception;
    const create_element = moduleMember(ctx, react_module, "createElement");
    defer create_element.deinit(ctx);
    if (!create_element.isFunction(ctx)) return throwMessage(ctx, "React.createElement is unavailable");

    const react_dom_client = requireModule(ctx, "react-dom/client");
    defer react_dom_client.deinit(ctx);
    if (react_dom_client.isException()) return quickjs.Value.exception;
    const create_root = moduleMember(ctx, react_dom_client, "createRoot");
    defer create_root.deinit(ctx);
    if (!create_root.isFunction(ctx)) return throwMessage(ctx, "react-dom/client.createRoot is unavailable");

    var create_root_args = [_]quickjs.Value{parsed.container.dup(ctx)};
    const root = create_root.call(ctx, react_dom_client, &create_root_args);
    defer root.deinit(ctx);
    if (!root.isObject()) return quickjs.Value.exception;

    const result_ref = quickjs.Value.initObject(ctx);
    if (result_ref.isException()) return quickjs.Value.exception;
    defer result_ref.deinit(ctx);
    result_ref.setPropertyStr(ctx, "current", quickjs.Value.undefined) catch return quickjs.Value.exception;

    const props_box = quickjs.Value.initObject(ctx);
    if (props_box.isException()) return quickjs.Value.exception;
    defer props_box.deinit(ctx);
    props_box.setPropertyStr(ctx, "value", initial_props.dup(ctx)) catch return quickjs.Value.exception;

    var probe_data = [_]quickjs.Value{ callback.dup(ctx), result_ref.dup(ctx), props_box.dup(ctx) };
    const probe_component = quickjs.Value.initCFunctionData2(ctx, jsRenderHookProbeComponent, "__zigRenderHookProbe", 1, 0, &probe_data);
    defer probe_component.deinit(ctx);
    if (probe_component.isException()) return quickjs.Value.exception;

    const tree = buildRenderHookTree(ctx, create_element, probe_component, wrapper);
    defer tree.deinit(ctx);
    if (tree.isException()) return quickjs.Value.exception;

    if (!callRootRender(ctx, root, tree)) return quickjs.Value.exception;
    if (!flushWork(ctx, default_flush_turns)) return quickjs.Value.exception;

    if (!trackRoot(ctx, root, parsed.container, parsed.managed_container)) return quickjs.Value.exception;

    const out = quickjs.Value.initObject(ctx);
    if (out.isException()) return quickjs.Value.exception;
    out.setPropertyStr(ctx, "result", result_ref.dup(ctx)) catch return quickjs.Value.exception;

    var hook_rerender_data = [_]quickjs.Value{
        root.dup(ctx),
        create_element.dup(ctx),
        probe_component.dup(ctx),
        wrapper.dup(ctx),
        props_box.dup(ctx),
    };
    const rerender_fn = quickjs.Value.initCFunctionData2(ctx, jsRenderHookRerender, "__zigRenderHookRerender", 1, 0, &hook_rerender_data);
    if (rerender_fn.isException()) return quickjs.Value.exception;
    out.setPropertyStr(ctx, "rerender", rerender_fn) catch return quickjs.Value.exception;

    var unmount_data = [_]quickjs.Value{
        root.dup(ctx),
        parsed.container.dup(ctx),
        quickjs.Value.initBool(parsed.managed_container),
    };
    const unmount_fn = quickjs.Value.initCFunctionData2(ctx, jsRenderUnmount, "__zigRenderHookUnmount", 0, 0, &unmount_data);
    if (unmount_fn.isException()) return quickjs.Value.exception;
    out.setPropertyStr(ctx, "unmount", unmount_fn) catch return quickjs.Value.exception;

    return out;
}

fn jsRenderHookProbeComponent(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const callback = quickjs.Value.fromCVal(data[0]);
    const result_ref = quickjs.Value.fromCVal(data[1]);
    const props_box = quickjs.Value.fromCVal(data[2]);

    const props_value = props_box.getPropertyStr(ctx, "value");
    defer props_value.deinit(ctx);

    const callback_result = if (props_value.isUndefined())
        callback.call(ctx, quickjs.Value.undefined, &.{})
    else blk: {
        var call_args = [_]quickjs.Value{props_value.dup(ctx)};
        break :blk callback.call(ctx, quickjs.Value.undefined, &call_args);
    };
    defer callback_result.deinit(ctx);
    if (callback_result.isException()) return quickjs.Value.exception;

    result_ref.setPropertyStr(ctx, "current", callback_result.dup(ctx)) catch return quickjs.Value.exception;
    return quickjs.Value.null;
}

fn jsRenderHookRerender(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const root = quickjs.Value.fromCVal(data[0]);
    const create_element = quickjs.Value.fromCVal(data[1]);
    const probe_component = quickjs.Value.fromCVal(data[2]);
    const wrapper = quickjs.Value.fromCVal(data[3]);
    const props_box = quickjs.Value.fromCVal(data[4]);

    const next_props = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    props_box.setPropertyStr(ctx, "value", next_props.dup(ctx)) catch return quickjs.Value.exception;

    const tree = buildRenderHookTree(ctx, create_element, probe_component, wrapper);
    defer tree.deinit(ctx);
    if (tree.isException()) return quickjs.Value.exception;

    if (!callRootRender(ctx, root, tree)) return quickjs.Value.exception;
    if (!flushWork(ctx, default_flush_turns)) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn callRootRender(ctx: *quickjs.Context, root: quickjs.Value, tree: quickjs.Value) bool {
    const render_fn = root.getPropertyStr(ctx, "render");
    defer render_fn.deinit(ctx);
    if (!render_fn.isFunction(ctx)) return false;

    if (installedAct(ctx)) |act| {
        defer act.deinit(ctx);
        var callback_data = [_]quickjs.Value{ root.dup(ctx), tree.dup(ctx) };
        const callback = quickjs.Value.initCFunctionData2(ctx, jsActRenderCallback, "__zigActRenderCallback", 0, 0, &callback_data);
        if (callback.isException()) return false;
        defer callback.deinit(ctx);

        var act_args = [_]quickjs.Value{callback.dup(ctx)};
        const act_result = act.call(ctx, quickjs.Value.undefined, &act_args);
        defer act_result.deinit(ctx);
        if (act_result.isException()) return false;
        if (act_result.isPromise()) {
            if (!flushWork(ctx, 24)) return false;
        }
        return true;
    }

    var render_args = [_]quickjs.Value{tree.dup(ctx)};
    const result = render_fn.call(ctx, root, &render_args);
    defer result.deinit(ctx);
    if (result.isException()) return false;
    return true;
}

fn jsActRenderCallback(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const quickjs.c.JSValue,
    _: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const root = quickjs.Value.fromCVal(data[0]);
    const tree = quickjs.Value.fromCVal(data[1]);
    const render_fn = root.getPropertyStr(ctx, "render");
    defer render_fn.deinit(ctx);
    if (!render_fn.isFunction(ctx)) return quickjs.Value.exception;
    var render_args = [_]quickjs.Value{tree.dup(ctx)};
    const result = render_fn.call(ctx, root, &render_args);
    defer result.deinit(ctx);
    if (result.isException()) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn buildRenderHookTree(ctx: *quickjs.Context, create_element: quickjs.Value, probe_component: quickjs.Value, wrapper: quickjs.Value) quickjs.Value {
    const probe_element = createElementCall(ctx, create_element, probe_component, null, null);
    defer probe_element.deinit(ctx);
    if (probe_element.isException()) return quickjs.Value.exception;

    if (!wrapper.isFunction(ctx)) return probe_element.dup(ctx);
    return createElementCall(ctx, create_element, wrapper, null, probe_element);
}

fn buildRenderTree(ctx: *quickjs.Context, ui: quickjs.Value, wrapper: quickjs.Value) quickjs.Value {
    if (!wrapper.isFunction(ctx)) return ui.dup(ctx);

    const react_module = requireModule(ctx, "react");
    defer react_module.deinit(ctx);
    if (react_module.isException()) return quickjs.Value.exception;
    const create_element = moduleMember(ctx, react_module, "createElement");
    defer create_element.deinit(ctx);
    if (!create_element.isFunction(ctx)) return throwMessage(ctx, "React.createElement is unavailable");

    return createElementCall(ctx, create_element, wrapper, null, ui);
}

fn createElementCall(
    ctx: *quickjs.Context,
    create_element: quickjs.Value,
    component: quickjs.Value,
    props: ?quickjs.Value,
    child: ?quickjs.Value,
) quickjs.Value {
    var call_args: [3]quickjs.Value = .{
        component.dup(ctx),
        if (props) |value| value.dup(ctx) else quickjs.Value.null,
        if (child) |value| value.dup(ctx) else quickjs.Value.undefined,
    };
    defer call_args[0].deinit(ctx);
    defer call_args[1].deinit(ctx);
    defer call_args[2].deinit(ctx);

    const args_slice = if (child == null) call_args[0..2] else call_args[0..3];
    return create_element.call(ctx, quickjs.Value.undefined, args_slice);
}

fn callDomWithin(ctx: *quickjs.Context, container: quickjs.Value) ?quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const dom_api = global.getPropertyStr(ctx, "__zigTestingLibraryDom");
    defer dom_api.deinit(ctx);
    if (!dom_api.isObject()) return null;
    const within = dom_api.getPropertyStr(ctx, "within");
    defer within.deinit(ctx);
    if (!within.isFunction(ctx)) return null;
    var call_args = [_]quickjs.Value{container.dup(ctx)};
    const result = within.call(ctx, dom_api, &call_args);
    if (result.isException()) return null;
    return result;
}

fn installedAct(ctx: *quickjs.Context) ?quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const testing_library = global.getPropertyStr(ctx, "__zigTestingLibraryReact");
    defer testing_library.deinit(ctx);
    if (!testing_library.isObject()) return null;
    const act = testing_library.getPropertyStr(ctx, "act");
    if (!act.isException() and act.isFunction(ctx)) return act;
    act.deinit(ctx);
    return null;
}

fn jsActFallback(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const callback = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    if (!callback.isFunction(ctx)) return throwMessage(ctx, "act(callback) requires a function");

    const callback_result = callback.call(ctx, quickjs.Value.undefined, &.{});
    defer callback_result.deinit(ctx);
    if (callback_result.isException()) return quickjs.Value.exception;

    if (callback_result.isPromise()) {
        if (!flushWork(ctx, default_flush_turns)) return quickjs.Value.exception;
        if (callback_result.promiseState(ctx) == .rejected) {
            const rejection = callback_result.promiseResult(ctx);
            defer rejection.deinit(ctx);
            _ = rejection.throw(ctx);
            return quickjs.Value.exception;
        }
        if (!flushWork(ctx, default_flush_turns)) return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn requireModule(ctx: *quickjs.Context, specifier: []const u8) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const native_require = global.getPropertyStr(ctx, "__zigNativeRequire");
    defer native_require.deinit(ctx);
    if (!native_require.isFunction(ctx)) return quickjs.Value.exception;

    const parent = requireParentModuleId(ctx, global);
    defer parent.deinit(ctx);

    var call_args = [_]quickjs.Value{
        parent.dup(ctx),
        quickjs.Value.initStringLen(ctx, specifier),
        quickjs.Value.initStringLen(ctx, ""),
    };
    defer call_args[0].deinit(ctx);
    defer call_args[1].deinit(ctx);
    defer call_args[2].deinit(ctx);
    return native_require.call(ctx, quickjs.Value.undefined, &call_args);
}

fn requireParentModuleId(ctx: *quickjs.Context, global: quickjs.Value) quickjs.Value {
    const process = global.getPropertyStr(ctx, "process");
    defer process.deinit(ctx);
    if (!process.isObject()) return quickjs.Value.initStringLen(ctx, "<zig-testing-library>");
    const argv = process.getPropertyStr(ctx, "argv");
    defer argv.deinit(ctx);
    if (!argv.isObject()) return quickjs.Value.initStringLen(ctx, "<zig-testing-library>");
    const entry = argv.getPropertyUint32(ctx, 2);
    if (!entry.isException() and entry.isString()) return entry;
    entry.deinit(ctx);
    return quickjs.Value.initStringLen(ctx, "<zig-testing-library>");
}

fn moduleMember(ctx: *quickjs.Context, module_value: quickjs.Value, comptime name: [:0]const u8) quickjs.Value {
    const direct = module_value.getPropertyStr(ctx, name);
    if (!direct.isException() and !direct.isUndefined()) return direct;
    if (direct.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        direct.deinit(ctx);
    }
    const default_value = module_value.getPropertyStr(ctx, "default");
    defer default_value.deinit(ctx);
    if (!default_value.isObject()) return quickjs.Value.undefined;
    const nested = default_value.getPropertyStr(ctx, name);
    if (nested.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        nested.deinit(ctx);
        return quickjs.Value.undefined;
    }
    return nested;
}

fn trackRoot(ctx: *quickjs.Context, root: quickjs.Value, container: quickjs.Value, managed: bool) bool {
    const roots = trackedRoots(ctx) orelse return false;
    defer roots.deinit(ctx);

    const record = quickjs.Value.initObject(ctx);
    if (record.isException()) return false;
    defer record.deinit(ctx);
    record.setPropertyStr(ctx, "root", root.dup(ctx)) catch return false;
    record.setPropertyStr(ctx, "container", container.dup(ctx)) catch return false;
    record.setPropertyStr(ctx, "managed", quickjs.Value.initBool(managed)) catch return false;

    const length = arrayLength(ctx, roots);
    roots.setPropertyUint32(ctx, @intCast(length), record.dup(ctx)) catch return false;
    return true;
}

fn clearTrackedRoot(ctx: *quickjs.Context, root: quickjs.Value) void {
    const roots = trackedRoots(ctx) orelse return;
    defer roots.deinit(ctx);

    const count = arrayLength(ctx, roots);
    var write_index: u32 = 0;
    var index: i64 = 0;
    while (index < count) : (index += 1) {
        const record = roots.getPropertyUint32(ctx, @intCast(index));
        defer record.deinit(ctx);
        if (!record.isObject()) continue;
        const candidate_root = record.getPropertyStr(ctx, "root");
        defer candidate_root.deinit(ctx);
        if (!candidate_root.isException() and candidate_root.isSameValue(ctx, root)) {
            continue;
        }
        roots.setPropertyUint32(ctx, write_index, record.dup(ctx)) catch return;
        write_index += 1;
    }
    roots.setPropertyStr(ctx, "length", quickjs.Value.initInt32(@intCast(write_index))) catch {};
}

fn trackedRoots(ctx: *quickjs.Context) ?quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const existing = global.getPropertyStr(ctx, "__zigTestingLibraryReactRoots");
    if (!existing.isException() and existing.isArray()) return existing;
    if (existing.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
    }
    existing.deinit(ctx);

    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) return null;
    global.setPropertyStr(ctx, "__zigTestingLibraryReactRoots", array.dup(ctx)) catch {
        array.deinit(ctx);
        return null;
    };
    return array;
}

fn arrayLength(ctx: *quickjs.Context, value: quickjs.Value) i64 {
    const length = value.getLength(ctx) catch return 0;
    return if (length < 0) 0 else length;
}

fn flushWork(ctx: *quickjs.Context, turns: i64) bool {
    const rt = ctx.getRuntime();
    var remaining = if (turns <= 0) @as(i64, 1) else turns;
    var guard: usize = 0;

    while (remaining > 0) : (remaining -= 1) {
        var progressed = false;
        while (rt.isJobPending()) : (guard += 1) {
            _ = rt.executePendingJob() catch return false;
            progressed = true;
            if (guard > 100_000) return false;
        }

        if (platform.hasPendingNativeTimers()) {
            const timer_result = platform.runNativeTimerTurn(ctx);
            defer timer_result.deinit(ctx);
            if (timer_result.isException()) return false;
            progressed = true;
            while (platform.hasDueNativeTimers()) {
                const due_timer_result = platform.runNativeTimerTurn(ctx);
                defer due_timer_result.deinit(ctx);
                if (due_timer_result.isException()) return false;
            }
        }
        if (!progressed) break;
    }

    while (rt.isJobPending()) : (guard += 1) {
        _ = rt.executePendingJob() catch return false;
        if (guard > 100_000) return false;
    }

    return true;
}

fn copyProperty(ctx: *quickjs.Context, target: quickjs.Value, source: quickjs.Value, name: []const u8) TestingLibraryReactError!void {
    const name_z = std.heap.c_allocator.dupeZ(u8, name) catch return error.OutOfMemory;
    defer std.heap.c_allocator.free(name_z);
    const value = source.getPropertyStr(ctx, name_z);
    defer value.deinit(ctx);
    if (value.isException() or value.isUndefined()) return;
    target.setPropertyStr(ctx, name_z, value.dup(ctx)) catch return error.JSError;
}

fn throwMessage(ctx: *quickjs.Context, text: []const u8) quickjs.Value {
    const value = quickjs.Value.initStringLen(ctx, text);
    return value.throw(ctx);
}

fn setFunction(
    ctx: *quickjs.Context,
    object: quickjs.Value,
    comptime name: [:0]const u8,
    comptime func: quickjs.cfunc.Func,
    arg_count: i32,
) TestingLibraryReactError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

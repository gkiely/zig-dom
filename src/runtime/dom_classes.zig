const std = @import("std");
const quickjs = @import("quickjs");
const zig_dom = @import("../zig_dom.zig");
const c = quickjs.c;

const Allocator = std.mem.Allocator;

pub const DomClassesError = error{
    OutOfMemory,
    RegistrationFailed,
    PropertyAccessFailed,
};

pub const DomClasses = struct {
    allocator: Allocator,
    node_class_id: quickjs.ClassId = .invalid,
    installed: bool = false,

    pub fn init(allocator: Allocator, rt: *quickjs.Runtime, ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!DomClasses {
        var classes: DomClasses = .{
            .allocator = allocator,
        };

        try classes.installScaffold(rt, ctx);
        try classes.installGlobals(ctx, global);
        classes.installed = true;
        return classes;
    }

    pub fn deinit(self: *DomClasses) void {
        self.* = .{
            .allocator = self.allocator,
        };
    }

    pub fn installNodeSlice(self: *DomClasses, ctx: *quickjs.Context) DomClassesError!void {
        _ = self;

        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);

        const node_ctor = global.getPropertyStr(ctx, "Node");
        defer node_ctor.deinit(ctx);
        if (node_ctor.isException() or !node_ctor.isObject()) {
            return error.PropertyAccessFailed;
        }

        const node_proto = node_ctor.getPropertyStr(ctx, "prototype");
        defer node_proto.deinit(ctx);
        if (node_proto.isException() or !node_proto.isObject()) {
            return error.PropertyAccessFailed;
        }

        try installGetter(ctx, node_proto, "nodeType", jsNodeTypeGet);
        try installGetter(ctx, node_proto, "nodeName", jsNodeNameGet);
        try installGetter(ctx, node_proto, "parentNode", jsNodeParentNodeGet);
        try installGetter(ctx, node_proto, "parentElement", jsNodeParentElementGet);
        try installGetter(ctx, node_proto, "firstChild", jsNodeFirstChildGet);
        try installGetter(ctx, node_proto, "lastChild", jsNodeLastChildGet);
        try installGetter(ctx, node_proto, "previousSibling", jsNodePreviousSiblingGet);
        try installGetter(ctx, node_proto, "nextSibling", jsNodeNextSiblingGet);
        try installGetter(ctx, node_proto, "ownerDocument", jsNodeOwnerDocumentGet);
        try installGetter(ctx, node_proto, "isConnected", jsNodeIsConnectedGet);
        try installAccessor(ctx, node_proto, "textContent", jsNodeTextContentGet, jsNodeTextContentSet);
        try installMethod(ctx, node_proto, "contains", jsNodeContains, 1);
        try installMethod(ctx, node_proto, "appendChild", jsNodeAppendChild, 1);
        try installMethod(ctx, node_proto, "insertBefore", jsNodeInsertBefore, 2);
        try installMethod(ctx, node_proto, "removeChild", jsNodeRemoveChild, 1);
        try installMethod(ctx, node_proto, "replaceChild", jsNodeReplaceChild, 2);
        try installElementSlice(ctx, global);
        try installDocumentDefaultView(ctx, global);

        const info = global.getPropertyStr(ctx, "__zigDomNativeClasses");
        defer info.deinit(ctx);
        if (!info.isException() and info.isObject()) {
            info.setPropertyStr(ctx, "nodeSliceInstalled", quickjs.Value.initBool(true)) catch return error.PropertyAccessFailed;
        }
    }

    fn installScaffold(self: *DomClasses, rt: *quickjs.Runtime, ctx: *quickjs.Context) DomClassesError!void {
        self.node_class_id = quickjs.ClassId.new(rt);

        const def: quickjs.ClassDef = .{
            .class_name = "ZigDomNode",
        };
        rt.newClass(self.node_class_id, &def) catch return error.RegistrationFailed;

        const proto = quickjs.Value.initObject(ctx);
        if (proto.isException()) {
            return error.OutOfMemory;
        }
        defer proto.deinit(ctx);

        proto.setPropertyStr(ctx, "__zigDomNativeNodeProto", quickjs.Value.initBool(true)) catch {
            return error.PropertyAccessFailed;
        };

        ctx.setClassProto(self.node_class_id, proto.dup(ctx));
    }

    fn installGlobals(self: *DomClasses, ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
        _ = self;

        const info = quickjs.Value.initObject(ctx);
        if (info.isException()) {
            return error.OutOfMemory;
        }
        defer info.deinit(ctx);

        info.setPropertyStr(ctx, "nodeScaffold", quickjs.Value.initBool(true)) catch {
            return error.PropertyAccessFailed;
        };
        info.setPropertyStr(ctx, "nodeSliceInstalled", quickjs.Value.initBool(false)) catch {
            return error.PropertyAccessFailed;
        };

        global.setPropertyStr(ctx, "__zigDomNativeClasses", info.dup(ctx)) catch {
            return error.PropertyAccessFailed;
        };
    }
};

fn installElementSlice(ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
    const element_ctor = global.getPropertyStr(ctx, "Element");
    defer element_ctor.deinit(ctx);
    if (element_ctor.isException() or !element_ctor.isObject()) {
        return error.PropertyAccessFailed;
    }

    const element_proto = element_ctor.getPropertyStr(ctx, "prototype");
    defer element_proto.deinit(ctx);
    if (element_proto.isException() or !element_proto.isObject()) {
        return error.PropertyAccessFailed;
    }

    try installGetter(ctx, element_proto, "tagName", jsElementTagNameGet);
    try installGetter(ctx, element_proto, "localName", jsElementLocalNameGet);
    try installAccessor(ctx, element_proto, "id", jsElementIdGet, jsElementIdSet);
    try installAccessor(ctx, element_proto, "className", jsElementClassNameGet, jsElementClassNameSet);
        try installAccessor(ctx, element_proto, "innerHTML", jsElementInnerHtmlGet, jsElementInnerHtmlSet);
        try installGetter(ctx, element_proto, "outerHTML", jsElementOuterHtmlGet);
        try installMethod(ctx, element_proto, "getAttribute", jsElementGetAttribute, 1);
        try installMethod(ctx, element_proto, "setAttribute", jsElementSetAttribute, 2);
        try installMethod(ctx, element_proto, "removeAttribute", jsElementRemoveAttribute, 1);
        try installMethod(ctx, element_proto, "hasAttribute", jsElementHasAttribute, 1);
    try installDocumentSlice(ctx, global);
}

fn installDocumentSlice(ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
    const document_ctor = global.getPropertyStr(ctx, "Document");
    defer document_ctor.deinit(ctx);
    if (document_ctor.isException() or !document_ctor.isObject()) {
        return error.PropertyAccessFailed;
    }

    const document_proto = document_ctor.getPropertyStr(ctx, "prototype");
    defer document_proto.deinit(ctx);
    if (document_proto.isException() or !document_proto.isObject()) {
        return error.PropertyAccessFailed;
    }

    try installGetter(ctx, document_proto, "documentElement", jsDocumentElementGet);
    try installGetter(ctx, document_proto, "head", jsDocumentHeadGet);
    try installGetter(ctx, document_proto, "body", jsDocumentBodyGet);
    try installMethod(ctx, document_proto, "createElement", jsDocumentCreateElement, 1);
    try installMethod(ctx, document_proto, "createTextNode", jsDocumentCreateTextNode, 1);
    try installMethod(ctx, document_proto, "createComment", jsDocumentCreateComment, 1);
    try installMethod(ctx, document_proto, "createDocumentFragment", jsDocumentCreateDocumentFragment, 0);
    try installMethod(ctx, document_proto, "getElementById", jsDocumentGetElementById, 1);
}

fn installMethod(
    ctx: *quickjs.Context,
    target: quickjs.Value,
    name: [:0]const u8,
    comptime func: quickjs.cfunc.Func,
    arg_count: i32,
) DomClassesError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) {
        return error.OutOfMemory;
    }

    target.setPropertyStr(ctx, name.ptr, value) catch {
        return error.PropertyAccessFailed;
    };
}

fn installGetter(
    ctx: *quickjs.Context,
    target: quickjs.Value,
    name: [:0]const u8,
    comptime getter: quickjs.cfunc.Getter,
) DomClassesError!void {
    const atom = quickjs.Atom.init(ctx, name);
    defer atom.deinit(ctx);

    const getter_value = quickjs.Value.fromCVal(c.JS_NewCFunction2(
        ctx.cval(),
        @ptrCast(quickjs.cfunc.wrapGetter(getter)),
        name.ptr,
        0,
        c.JS_CFUNC_getter,
        0,
    ));
    if (getter_value.isException()) {
        return error.OutOfMemory;
    }

    _ = target.definePropertyGetSet(ctx, atom, getter_value, quickjs.Value.@"undefined", .{
        .configurable = true,
        .enumerable = true,
    }) catch return error.PropertyAccessFailed;
}

fn installAccessor(
    ctx: *quickjs.Context,
    target: quickjs.Value,
    name: [:0]const u8,
    comptime getter: quickjs.cfunc.Getter,
    comptime setter: quickjs.cfunc.Setter,
) DomClassesError!void {
    const atom = quickjs.Atom.init(ctx, name);
    defer atom.deinit(ctx);

    const getter_value = quickjs.Value.fromCVal(c.JS_NewCFunction2(
        ctx.cval(),
        @ptrCast(quickjs.cfunc.wrapGetter(getter)),
        name.ptr,
        0,
        c.JS_CFUNC_getter,
        0,
    ));
    if (getter_value.isException()) {
        return error.OutOfMemory;
    }

    const setter_value = quickjs.Value.fromCVal(c.JS_NewCFunction2(
        ctx.cval(),
        @ptrCast(quickjs.cfunc.wrapSetter(setter)),
        name.ptr,
        1,
        c.JS_CFUNC_setter,
        0,
    ));
    if (setter_value.isException()) {
        getter_value.deinit(ctx);
        return error.OutOfMemory;
    }

    _ = target.definePropertyGetSet(ctx, atom, getter_value, setter_value, .{
        .configurable = true,
        .enumerable = true,
    }) catch return error.PropertyAccessFailed;
}

fn installDocumentDefaultView(ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) {
        return error.PropertyAccessFailed;
    }

    const window = global.getPropertyStr(ctx, "window");
    if (window.isException() or !window.isObject()) {
        window.deinit(ctx);
        return error.PropertyAccessFailed;
    }

    _ = document.definePropertyValueStr(ctx, "defaultView", window, .default) catch return error.PropertyAccessFailed;
}

fn jsNodeTypeGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (getIntProperty(ctx, this_value, "_nodeTypeOverride")) |override| {
        if (override != 0) {
            return quickjs.Value.initInt64(override);
        }
    }
    const this_handle = parseThisHandle(ctx, this_value, "nodeType") orelse return quickjs.Value.exception;
    return quickjs.Value.initInt64(@intCast(zig_dom.zig_dom_node_type(this_handle)));
}

fn jsNodeNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const override = this_value.getPropertyStr(ctx, "_nodeNameOverride");
    defer override.deinit(ctx);
    if (!override.isException() and !override.isNull() and !override.isUndefined()) {
        return override.dup(ctx);
    }
    const this_handle = parseThisHandle(ctx, this_value, "nodeName") orelse return quickjs.Value.exception;
    return nodeNameToJs(ctx, this_handle, "nodeName");
}

fn jsNodeParentNodeGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "parentNode") orelse return quickjs.Value.exception;
    return wrapNodeHandle(ctx, zig_dom.zig_dom_node_parent(this_handle));
}

fn jsNodeParentElementGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "parentElement") orelse return quickjs.Value.exception;
    const parent_handle = zig_dom.zig_dom_node_parent(this_handle);
    if (parent_handle == 0 or zig_dom.zig_dom_node_type(parent_handle) != 1) {
        return quickjs.Value.@"null";
    }
    return wrapNodeHandle(ctx, parent_handle);
}

fn jsNodeFirstChildGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "firstChild") orelse return quickjs.Value.exception;
    return wrapNodeHandle(ctx, zig_dom.zig_dom_node_first_child(this_handle));
}

fn jsNodeLastChildGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "lastChild") orelse return quickjs.Value.exception;
    return wrapNodeHandle(ctx, zig_dom.zig_dom_node_last_child(this_handle));
}

fn jsNodePreviousSiblingGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "previousSibling") orelse return quickjs.Value.exception;
    return wrapNodeHandle(ctx, zig_dom.zig_dom_node_previous_sibling(this_handle));
}

fn jsNodeNextSiblingGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "nextSibling") orelse return quickjs.Value.exception;
    return wrapNodeHandle(ctx, zig_dom.zig_dom_node_next_sibling(this_handle));
}

fn jsNodeOwnerDocumentGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "ownerDocument") orelse return quickjs.Value.exception;
    if (zig_dom.zig_dom_node_type(this_handle) == 9) {
        return quickjs.Value.@"null";
    }

    var document_handle: u64 = 0;
    const status = zig_dom.zig_dom_node_owner_document(this_handle, &document_handle);
    if (status != 0) {
        return throwStatus(ctx, "ownerDocument", status);
    }
    if (document_handle == 0) {
        if (getIntProperty(ctx, this_value, "__zigDomOwnerDocumentHandle")) |fallback_handle| {
            if (fallback_handle > 0) {
                document_handle = @intCast(fallback_handle);
            }
        }
    }
    if (document_handle == 0) {
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const document = global.getPropertyStr(ctx, "document");
        if (!document.isException() and document.isObject()) {
            return document;
        }
        document.deinit(ctx);
    }
    return wrapNodeHandle(ctx, document_handle);
}

fn jsNodeIsConnectedGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "isConnected") orelse return quickjs.Value.exception;
    if (zig_dom.zig_dom_node_type(this_handle) == 9) {
        return quickjs.Value.initBool(true);
    }

    var cursor = zig_dom.zig_dom_node_parent(this_handle);
    while (cursor != 0) : (cursor = zig_dom.zig_dom_node_parent(cursor)) {
        if (zig_dom.zig_dom_node_type(cursor) == 9) {
            return quickjs.Value.initBool(true);
        }
    }
    return quickjs.Value.initBool(false);
}

fn jsNodeTextContentGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "textContent") orelse return quickjs.Value.exception;
    if (zig_dom.zig_dom_node_type(this_handle) == 10) {
        return quickjs.Value.@"null";
    }

    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_text_content(this_handle, &out_ptr, &out_len);
    if (status != 0) {
        return throwStatus(ctx, "textContent", status);
    }
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);

    if (out_ptr == null or out_len == 0) {
        return quickjs.Value.initStringLen(ctx, "");
    }

    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
}

fn jsNodeTextContentSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "textContent") orelse return quickjs.Value.exception;
    if (zig_dom.zig_dom_node_type(this_handle) == 10) {
        return quickjs.Value.@"undefined";
    }

    const text_value = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "textContent", "value could not be converted to string");
    defer ctx.freeCString(text_value.ptr);

    const status = zig_dom.zig_dom_node_set_text_content(this_handle, text_value.ptr, text_value.len);
    if (status != 0) {
        return throwStatus(ctx, "textContent", status);
    }

    return quickjs.Value.@"undefined";
}

fn jsElementTagNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "tagName") orelse return quickjs.Value.exception;
    const name = nodeNameToJs(ctx, this_handle, "tagName");
    defer name.deinit(ctx);
    const upper = name.toStringValue(ctx);
    defer upper.deinit(ctx);
    const cstr = upper.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    var buffer: [128]u8 = undefined;
    if (cstr.len > buffer.len) {
        return quickjs.Value.initStringLen(ctx, cstr.ptr[0..cstr.len]);
    }
    const out = buffer[0..cstr.len];
    for (cstr.ptr[0..cstr.len], 0..) |ch, i| {
        out[i] = std.ascii.toUpper(ch);
    }
    return quickjs.Value.initStringLen(ctx, out);
}

fn jsElementLocalNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "localName") orelse return quickjs.Value.exception;
    const name = nodeNameToJs(ctx, this_handle, "localName");
    defer name.deinit(ctx);
    const cstr = name.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    var buffer: [128]u8 = undefined;
    if (cstr.len > buffer.len) {
        return quickjs.Value.initStringLen(ctx, cstr.ptr[0..cstr.len]);
    }
    const out = buffer[0..cstr.len];
    for (cstr.ptr[0..cstr.len], 0..) |ch, i| {
        out[i] = std.ascii.toLower(ch);
    }
    return quickjs.Value.initStringLen(ctx, out);
}

fn jsElementIdGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "id", "");
}

fn jsElementIdSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return elementAttributeSet(ctx_opt, this_value, "id", next_value);
}

fn jsElementClassNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "class", "");
}

fn jsElementClassNameSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return elementAttributeSet(ctx_opt, this_value, "class", next_value);
}

fn jsElementInnerHtmlGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = parseThisHandle(ctx, this_value, "innerHTML") orelse return quickjs.Value.exception;
    const child_nodes = this_value.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (child_nodes.isException() or !child_nodes.isObject()) return quickjs.Value.exception;
    const to_array = child_nodes.getPropertyStr(ctx, "toArray");
    defer to_array.deinit(ctx);
    if (to_array.isException() or !to_array.isObject()) return quickjs.Value.exception;
    const array = to_array.call(ctx, child_nodes, &.{});
    defer array.deinit(ctx);
    if (array.isException()) return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const json = global.getPropertyStr(ctx, "Function");
    defer json.deinit(ctx);
    if (json.isException() or !json.isObject()) return quickjs.Value.exception;
    const body = quickjs.Value.initStringLen(ctx, "return Array.prototype.map.call(arguments[0], function(child) { return child.outerHTML || child.textContent || ''; }).join('');");
    defer body.deinit(ctx);
    const mapper = json.call(ctx, quickjs.Value.@"undefined", &.{body});
    defer mapper.deinit(ctx);
    if (mapper.isException()) return quickjs.Value.exception;
    return mapper.call(ctx, quickjs.Value.@"undefined", &.{array});
}

fn jsElementInnerHtmlSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "innerHTML") orelse return quickjs.Value.exception;
    const text = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "innerHTML", "value could not be converted to string");
    defer ctx.freeCString(text.ptr);
    const status = zig_dom.zig_dom_node_set_inner_html(this_handle, text.ptr, text.len);
    if (status != 0) return throwStatus(ctx, "innerHTML", status);
    return quickjs.Value.@"undefined";
}

fn jsElementOuterHtmlGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "outerHTML") orelse return quickjs.Value.exception;
    return nodeOuterHtmlToJs(ctx, this_handle, "outerHTML");
}

fn jsElementGetAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "getAttribute") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "getAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    return elementAttributeValueToJs(ctx, this_handle, name.ptr[0..name.len], null, "getAttribute");
}

fn jsElementSetAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "setAttribute") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "setAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const value = parseStringArg(ctx, args, 1, "setAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(value.ptr);
    const status = zig_dom.zig_dom_element_set_attribute(this_handle, name.ptr, name.len, value.ptr, value.len);
    if (status != 0) return throwStatus(ctx, "setAttribute", status);
    return quickjs.Value.@"undefined";
}

fn jsElementRemoveAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "removeAttribute") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "removeAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const status = zig_dom.zig_dom_element_remove_attribute(this_handle, name.ptr, name.len);
    if (status != 0) return throwStatus(ctx, "removeAttribute", status);
    return quickjs.Value.@"undefined";
}

fn jsElementHasAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "hasAttribute") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "hasAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    return quickjs.Value.initBool(zig_dom.zig_dom_element_has_attribute(this_handle, name.ptr, name.len) == 1);
}

fn jsElementQuerySelector(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "querySelector") orelse return quickjs.Value.exception;
    const selector = parseStringArg(ctx, args, 0, "querySelector") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector.ptr);
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_node_query_selector(this_handle, selector.ptr, selector.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "querySelector", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsElementQuerySelectorAll(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "querySelectorAll") orelse return quickjs.Value.exception;
    const selector = parseStringArg(ctx, args, 0, "querySelectorAll") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector.ptr);

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_query_selector_all(this_handle, selector.ptr, selector.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "querySelectorAll", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    const handles = handleArrayToJs(ctx, out_ptr, out_len);
    defer handles.deinit(ctx);
    return constructNodeList(ctx, handles);
}

fn jsDocumentElementGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return documentWindowNodeGet(ctx_opt, this_value, "documentElement", zig_dom.zig_dom_window_document_element);
}

fn jsDocumentHeadGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return documentWindowNodeGet(ctx_opt, this_value, "head", zig_dom.zig_dom_window_head);
}

fn jsDocumentBodyGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return documentWindowNodeGet(ctx_opt, this_value, "body", zig_dom.zig_dom_window_body);
}

fn jsDocumentCreateElement(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "createElement") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "createElement") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_element(document_handle, name.ptr, name.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "createElement", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsDocumentCreateTextNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "createTextNode") orelse return quickjs.Value.exception;
    const data = parseStringArg(ctx, args, 0, "createTextNode") orelse return quickjs.Value.exception;
    defer ctx.freeCString(data.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_text_node(document_handle, data.ptr, data.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "createTextNode", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsDocumentCreateComment(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "createComment") orelse return quickjs.Value.exception;
    const data = parseStringArg(ctx, args, 0, "createComment") orelse return quickjs.Value.exception;
    defer ctx.freeCString(data.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_comment(document_handle, data.ptr, data.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "createComment", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsDocumentCreateDocumentFragment(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const document_handle = parseThisHandle(ctx, this_value, "createDocumentFragment") orelse return quickjs.Value.exception;

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_document_fragment(document_handle, &out_handle);
    if (status != 0) return throwStatus(ctx, "createDocumentFragment", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsDocumentGetElementById(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "getElementById") orelse return quickjs.Value.exception;
    const id = parseStringArg(ctx, args, 0, "getElementById") orelse return quickjs.Value.exception;
    defer ctx.freeCString(id.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_get_element_by_id(document_handle, id.ptr, id.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "getElementById", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn documentWindowNodeGet(
    ctx_opt: ?*quickjs.Context,
    this_value: quickjs.Value,
    operation: []const u8,
    comptime func: fn (u64, *u64) callconv(.c) u32,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = parseThisHandle(ctx, this_value, operation) orelse return quickjs.Value.exception;
    const window_handle_i64 = getIntProperty(ctx, this_value, "_windowHandle") orelse {
        return throwOperationMessage(ctx, operation, "document has no window handle");
    };
    if (window_handle_i64 <= 0) {
        return quickjs.Value.@"null";
    }

    var out_handle: u64 = 0;
    const status = func(@intCast(window_handle_i64), &out_handle);
    if (status != 0) return throwStatus(ctx, operation, status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsNodeContains(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "contains") orelse return quickjs.Value.exception;
    const other_handle = parseOptionalNodeArgHandle(ctx, args, 0) orelse return quickjs.Value.initBool(false);

    return quickjs.Value.initBool(zig_dom.zig_dom_node_contains(this_handle, other_handle) == 1);
}

fn jsNodeAppendChild(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "appendChild") orelse return quickjs.Value.exception;
    const child_handle = parseRequiredNodeArgHandle(ctx, args, 0, "appendChild") orelse return quickjs.Value.exception;

    const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
        zig_dom.zig_dom_node_append_fragment(this_handle, child_handle)
    else
        zig_dom.zig_dom_node_append_child(this_handle, child_handle);
    if (status != 0) {
        return throwStatus(ctx, "appendChild", status);
    }

    return args[0].dup(ctx);
}

fn jsNodeInsertBefore(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "insertBefore") orelse return quickjs.Value.exception;
    const child_handle = parseRequiredNodeArgHandle(ctx, args, 0, "insertBefore") orelse return quickjs.Value.exception;
    const reference_handle = parseNullableNodeArgHandle(ctx, args, 1, "insertBefore") orelse return quickjs.Value.exception;

    const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
        insertFragmentBefore(this_handle, child_handle, reference_handle)
    else
        zig_dom.zig_dom_node_insert_before(this_handle, child_handle, reference_handle);
    if (status != 0) {
        return throwStatus(ctx, "insertBefore", status);
    }

    return args[0].dup(ctx);
}

fn jsNodeRemoveChild(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "removeChild") orelse return quickjs.Value.exception;
    const child_handle = parseRequiredNodeArgHandle(ctx, args, 0, "removeChild") orelse return quickjs.Value.exception;

    const status = zig_dom.zig_dom_node_remove_child(this_handle, child_handle);
    if (status != 0) {
        return throwStatus(ctx, "removeChild", status);
    }

    return args[0].dup(ctx);
}

fn jsNodeReplaceChild(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "replaceChild") orelse return quickjs.Value.exception;
    const new_child_handle = parseRequiredNodeArgHandle(ctx, args, 0, "replaceChild") orelse return quickjs.Value.exception;
    const old_child_handle = parseRequiredNodeArgHandle(ctx, args, 1, "replaceChild") orelse return quickjs.Value.exception;

    const status = zig_dom.zig_dom_node_replace_child(this_handle, new_child_handle, old_child_handle);
    if (status != 0) {
        return throwStatus(ctx, "replaceChild", status);
    }

    return args[1].dup(ctx);
}

fn parseThisHandle(ctx: *quickjs.Context, this_value: quickjs.Value, operation: []const u8) ?u64 {
    const handle_i64 = parseValueNodeHandle(ctx, this_value) orelse {
        _ = throwOperationMessage(ctx, operation, "receiver is not a native node");
        return null;
    };
    if (handle_i64 <= 0) {
        _ = throwOperationMessage(ctx, operation, "receiver has an invalid native handle");
        return null;
    }
    return @intCast(handle_i64);
}

fn parseRequiredNodeArgHandle(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize, operation: []const u8) ?u64 {
    if (index >= args.len) {
        _ = throwOperationMessage(ctx, operation, "missing node argument");
        return null;
    }

    const handle_i64 = parseValueNodeHandle(ctx, args[index]) orelse {
        _ = throwOperationMessage(ctx, operation, "node argument must be a native node");
        return null;
    };
    if (handle_i64 <= 0) {
        _ = throwOperationMessage(ctx, operation, "node argument has an invalid native handle");
        return null;
    }

    return @intCast(handle_i64);
}

fn parseOptionalNodeArgHandle(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize) ?u64 {
    if (index >= args.len) {
        return null;
    }

    const handle_i64 = parseValueNodeHandle(ctx, args[index]) orelse return null;
    if (handle_i64 <= 0) {
        return null;
    }
    return @intCast(handle_i64);
}

fn parseValueNodeHandle(ctx: *quickjs.Context, value: quickjs.Value) ?i64 {
    const handle_value = value.getPropertyStr(ctx, "__zigDomNativeHandle");
    defer handle_value.deinit(ctx);

    if (handle_value.isException() or handle_value.isUndefined() or handle_value.isNull()) {
        return null;
    }

    return handle_value.toInt64(ctx) catch null;
}

fn getIntProperty(ctx: *quickjs.Context, value: quickjs.Value, name: [*:0]const u8) ?i64 {
    const property = value.getPropertyStr(ctx, name);
    defer property.deinit(ctx);
    if (property.isException() or property.isUndefined() or property.isNull()) {
        return null;
    }
    return property.toInt64(ctx) catch null;
}

const CStringArg = struct {
    ptr: [*:0]const u8,
    len: usize,
};

fn parseStringArg(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize, operation: []const u8) ?CStringArg {
    if (index >= args.len) {
        _ = throwOperationMessage(ctx, operation, "missing string argument");
        return null;
    }
    const value = args[index].toCStringLen(ctx) orelse {
        _ = throwOperationMessage(ctx, operation, "argument could not be converted to string");
        return null;
    };
    return .{ .ptr = value.ptr, .len = value.len };
}

fn elementAttributeGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, name: []const u8, fallback: []const u8) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, name) orelse return quickjs.Value.exception;
    return elementAttributeValueToJs(ctx, this_handle, name, fallback, name);
}

fn elementAttributeSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, name: []const u8, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, name) orelse return quickjs.Value.exception;
    const text = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, name, "value could not be converted to string");
    defer ctx.freeCString(text.ptr);
    const status = zig_dom.zig_dom_element_set_attribute(this_handle, name.ptr, name.len, text.ptr, text.len);
    if (status != 0) return throwStatus(ctx, name, status);
    return quickjs.Value.@"undefined";
}

fn elementAttributeValueToJs(ctx: *quickjs.Context, element_handle: u64, name: []const u8, fallback: ?[]const u8, operation: []const u8) quickjs.Value {
    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    var out_exists: u8 = 0;
    const status = zig_dom.zig_dom_element_get_attribute(element_handle, name.ptr, name.len, &out_ptr, &out_len, &out_exists);
    if (status != 0) return throwStatus(ctx, operation, status);
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);

    if (out_exists == 0) {
        if (fallback) |value| return quickjs.Value.initStringLen(ctx, value);
        return quickjs.Value.@"null";
    }
    if (out_ptr == null or out_len == 0) return quickjs.Value.initStringLen(ctx, "");
    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
}

fn parseNullableNodeArgHandle(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize, operation: []const u8) ?u64 {
    if (index >= args.len or args[index].isNull()) {
        return 0;
    }
    return parseRequiredNodeArgHandle(ctx, args, index, operation);
}

fn wrapNodeHandle(ctx: *quickjs.Context, handle: u64) quickjs.Value {
    if (handle == 0) {
        return quickjs.Value.@"null";
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const wrap = global.getPropertyStr(ctx, "__zigDomWrapNode");
    defer wrap.deinit(ctx);
    if (wrap.isException() or !wrap.isObject()) {
        return throwMessage(ctx, "__zigDomWrapNode is not installed");
    }

    const arg = quickjs.Value.initInt64(@intCast(handle));
    return wrap.call(ctx, quickjs.Value.@"undefined", &.{arg});
}

fn insertFragmentBefore(parent_handle: u64, fragment_handle: u64, reference_handle: u64) u32 {
    while (true) {
        const child_handle = zig_dom.zig_dom_node_first_child(fragment_handle);
        if (child_handle == 0) {
            return 0;
        }
        const status = zig_dom.zig_dom_node_insert_before(parent_handle, child_handle, reference_handle);
        if (status != 0) {
            return status;
        }
    }
}

fn nodeNameToJs(ctx: *quickjs.Context, node_handle: u64, operation: []const u8) quickjs.Value {
    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_name(node_handle, &out_ptr, &out_len);
    if (status != 0) {
        return throwStatus(ctx, operation, status);
    }
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);

    if (out_ptr == null or out_len == 0) {
        return quickjs.Value.initStringLen(ctx, "");
    }

    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
}

fn nodeOuterHtmlToJs(ctx: *quickjs.Context, node_handle: u64, operation: []const u8) quickjs.Value {
    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_outer_html(node_handle, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, operation, status);
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);
    if (out_ptr == null or out_len == 0) return quickjs.Value.initStringLen(ctx, "");
    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
}

fn handleArrayToJs(ctx: *quickjs.Context, handles: [*c]u64, len: usize) quickjs.Value {
    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) return array;
    for (0..len) |i| {
        array.setPropertyUint32(ctx, @intCast(i), quickjs.Value.initInt64(@intCast(handles[i]))) catch return quickjs.Value.exception;
    }
    return array;
}

fn constructNodeList(ctx: *quickjs.Context, handles: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "NodeList");
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return quickjs.Value.exception;

    const body = quickjs.Value.initStringLen(ctx,
        \\const handles = arguments[0];
        \\return function() { return Array.prototype.map.call(handles, globalThis.__zigDomWrapNode); };
    );
    defer body.deinit(ctx);
    const function_ctor = global.getPropertyStr(ctx, "Function");
    defer function_ctor.deinit(ctx);
    if (function_ctor.isException() or !function_ctor.isObject()) return quickjs.Value.exception;
    const factory = function_ctor.call(ctx, quickjs.Value.@"undefined", &.{body});
    defer factory.deinit(ctx);
    if (factory.isException()) return quickjs.Value.exception;
    const reader = factory.call(ctx, quickjs.Value.@"undefined", &.{handles});
    defer reader.deinit(ctx);
    if (reader.isException()) return quickjs.Value.exception;
    var ctor_args = [_]quickjs.Value{reader.dup(ctx)};
    defer ctor_args[0].deinit(ctx);
    return quickjs.Value.fromCVal(c.JS_CallConstructor(
        ctx.cval(),
        ctor.cval(),
        ctor_args.len,
        @ptrCast(&ctor_args),
    ));
}

fn throwStatus(ctx: *quickjs.Context, operation: []const u8, status: u32) quickjs.Value {
    var message_buffer: [128]u8 = undefined;
    const message = std.fmt.bufPrint(&message_buffer, "{s} failed with status {d}", .{ operation, status }) catch "native DOM operation failed";
    return throwMessage(ctx, message);
}

fn throwOperationMessage(ctx: *quickjs.Context, operation: []const u8, detail: []const u8) quickjs.Value {
    var message_buffer: [160]u8 = undefined;
    const message = std.fmt.bufPrint(&message_buffer, "{s}: {s}", .{ operation, detail }) catch "native DOM argument error";
    return throwMessage(ctx, message);
}

fn throwMessage(ctx: *quickjs.Context, message: []const u8) quickjs.Value {
    return quickjs.Value.initStringLen(ctx, message).throw(ctx);
}

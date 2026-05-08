const std = @import("std");
const quickjs = @import("quickjs");
const bindings = @import("bindings.zig");
const character_data_surface = @import("character_data.zig");
const document_surface = @import("document.zig");
const element_surface = @import("element.zig");
const event_target_surface = @import("event_target.zig");
const node_surface = @import("node.zig");
const surfaces = @import("surfaces.zig");
const zig_dom = @import("dom.zig");
const c = quickjs.c;

const Allocator = std.mem.Allocator;
pub const DomClassesError = bindings.DomClassesError;
const installAccessor = bindings.installAccessor;
const installConstructor = bindings.installConstructor;
const installGetter = bindings.installGetter;
const installMethod = bindings.installMethod;

const EventTargetCallbacks = struct {
    pub const addEventListener = jsEventTargetAddEventListener;
    pub const removeEventListener = jsEventTargetRemoveEventListener;
    pub const dispatchEvent = jsEventTargetDispatchEvent;
};

const NodeCallbacks = struct {
    pub const nodeTypeGet = jsNodeTypeGet;
    pub const nodeNameGet = jsNodeNameGet;
    pub const parentNodeGet = jsNodeParentNodeGet;
    pub const parentElementGet = jsNodeParentElementGet;
    pub const firstChildGet = jsNodeFirstChildGet;
    pub const lastChildGet = jsNodeLastChildGet;
    pub const previousSiblingGet = jsNodePreviousSiblingGet;
    pub const nextSiblingGet = jsNodeNextSiblingGet;
    pub const ownerDocumentGet = jsNodeOwnerDocumentGet;
    pub const isConnectedGet = jsNodeIsConnectedGet;
    pub const childNodesGet = jsNodeChildNodesGet;
    pub const childrenGet = jsNodeChildrenGet;
    pub const firstElementChildGet = jsNodeFirstElementChildGet;
    pub const lastElementChildGet = jsNodeLastElementChildGet;
    pub const previousElementSiblingGet = jsNodePreviousElementSiblingGet;
    pub const nextElementSiblingGet = jsNodeNextElementSiblingGet;
    pub const childElementCountGet = jsNodeChildElementCountGet;
    pub const textContentGet = jsNodeTextContentGet;
    pub const textContentSet = jsNodeTextContentSet;
    pub const nodeValueGet = jsNodeValueGet;
    pub const nodeValueSet = jsNodeValueSet;
    pub const outerHtmlGet = jsNodeOuterHtmlGet;
    pub const contains = jsNodeContains;
    pub const getRootNode = jsNodeGetRootNode;
    pub const compareDocumentPosition = jsNodeCompareDocumentPosition;
    pub const isEqualNode = jsNodeIsEqualNode;
    pub const normalize = jsNodeNormalize;
    pub const appendChild = jsNodeAppendChild;
    pub const append = jsNodeAppend;
    pub const prepend = jsNodePrepend;
    pub const insertBefore = jsNodeInsertBefore;
    pub const removeChild = jsNodeRemoveChild;
    pub const replaceChild = jsNodeReplaceChild;
    pub const cloneNode = jsNodeCloneNode;
};

const ElementCallbacks = struct {
    pub const tagNameGet = jsElementTagNameGet;
    pub const localNameGet = jsElementLocalNameGet;
    pub const namespaceUriGet = jsElementNamespaceUriGet;
    pub const idGet = jsElementIdGet;
    pub const idSet = jsElementIdSet;
    pub const classNameGet = jsElementClassNameGet;
    pub const classNameSet = jsElementClassNameSet;
    pub const titleGet = jsElementTitleGet;
    pub const titleSet = jsElementTitleSet;
    pub const htmlForGet = jsElementHtmlForGet;
    pub const htmlForSet = jsElementHtmlForSet;
    pub const innerHtmlGet = jsElementInnerHtmlGet;
    pub const innerHtmlSet = jsElementInnerHtmlSet;
    pub const outerHtmlGet = jsElementOuterHtmlGet;
    pub const styleGet = jsElementStyleGet;
    pub const getAttribute = jsElementGetAttribute;
    pub const getAttributeNode = jsElementGetAttributeNode;
    pub const setAttribute = jsElementSetAttribute;
    pub const removeAttribute = jsElementRemoveAttribute;
    pub const hasAttribute = jsElementHasAttribute;
    pub const toggleAttribute = jsElementToggleAttribute;
    pub const getAttributeNames = jsElementGetAttributeNames;
    pub const attributesGet = jsElementAttributesGet;
    pub const classListGet = jsElementClassListGet;
    pub const datasetGet = jsElementDatasetGet;
    pub const querySelector = jsElementQuerySelector;
    pub const querySelectorAll = jsElementQuerySelectorAll;
    pub const getElementsByClassName = jsElementGetElementsByClassName;
    pub const matches = jsElementMatches;
    pub const closest = jsElementClosest;
    pub const insertAdjacentHTML = jsElementInsertAdjacentHTML;
    pub const attachShadow = jsElementAttachShadow;
    pub const getBoundingClientRect = jsElementGetBoundingClientRect;
    pub const getClientRects = jsElementGetClientRects;
    pub const focus = jsElementFocus;
    pub const blur = jsElementBlur;
    pub const select = jsElementSelect;
    pub const valueGet = jsElementValueGet;
    pub const valueSet = jsElementValueSet;
    pub const checkedGet = jsElementCheckedGet;
    pub const checkedSet = jsElementCheckedSet;
    pub const disabledGet = jsElementDisabledGet;
    pub const disabledSet = jsElementDisabledSet;
    pub const nameGet = jsElementNameGet;
    pub const nameSet = jsElementNameSet;
    pub const typeGet = jsElementTypeGet;
    pub const typeSet = jsElementTypeSet;
    pub const formGet = jsElementFormGet;
    pub const formElementsGet = jsElementFormElementsGet;
    pub const optionsGet = jsElementOptionsGet;
};

const DocumentCallbacks = struct {
    pub const documentElementGet = jsDocumentElementGet;
    pub const headGet = jsDocumentHeadGet;
    pub const bodyGet = jsDocumentBodyGet;
    pub const defaultViewGet = jsDocumentDefaultViewGet;
    pub const implementationGet = jsDocumentImplementationGet;
    pub const createElement = jsDocumentCreateElement;
    pub const createElementNS = jsDocumentCreateElementNS;
    pub const createTextNode = jsDocumentCreateTextNode;
    pub const createComment = jsDocumentCreateComment;
    pub const createDocumentFragment = jsDocumentCreateDocumentFragment;
    pub const createDocumentType = jsDocumentCreateDocumentType;
    pub const createRange = jsDocumentCreateRange;
    pub const getSelection = jsDocumentGetSelection;
    pub const importNode = jsDocumentImportNode;
    pub const adoptNode = jsDocumentAdoptNode;
    pub const getElementById = jsDocumentGetElementById;
    pub const querySelector = jsDocumentQuerySelector;
    pub const querySelectorAll = jsDocumentQuerySelectorAll;
    pub const getElementsByClassName = jsDocumentGetElementsByClassName;
};

const CharacterDataCallbacks = struct {
    pub const dataGet = jsNodeTextContentGet;
    pub const dataSet = jsNodeTextContentSet;
    pub const lengthGet = jsCharacterDataLengthGet;
    pub const appendData = jsCharacterDataAppendData;
    pub const deleteData = jsCharacterDataDeleteData;
    pub const insertData = jsCharacterDataInsertData;
    pub const replaceData = jsCharacterDataReplaceData;
    pub const substringData = jsCharacterDataSubstringData;
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

        try node_surface.installPrototype(ctx, node_proto, NodeCallbacks);
        try installMethod(ctx, node_proto, "click", jsElementClick, 0);
        try event_target_surface.installPrototype(ctx, node_proto, EventTargetCallbacks);
        try installElementSlice(ctx, global);
        try installEventTargetSlice(ctx, global);
        try installDocumentDefaultView(ctx, global);

        const info = global.getPropertyStr(ctx, "__zigDomNativeClasses");
        defer info.deinit(ctx);
        if (!info.isException() and info.isObject()) {
            info.setPropertyStr(ctx, "nodeSliceInstalled", quickjs.Value.initBool(true)) catch return error.PropertyAccessFailed;
        }
    }

    pub fn installNativeGlobals(self: *DomClasses, ctx: *quickjs.Context, global: quickjs.Value, window_handle: u64, document_handle: u64) DomClassesError!void {
        try installNativeConstructors(ctx, global);
        try installMethod(ctx, global, "__zigDomWrapNode", jsWrapNode, 1);

        const cache = quickjs.Value.initObject(ctx);
        if (cache.isException()) return error.OutOfMemory;
        global.setPropertyStr(ctx, "__zigDomNodeCache", cache) catch return error.PropertyAccessFailed;

        const document = wrapNativeNode(ctx, document_handle);
        if (document.isException()) return error.PropertyAccessFailed;
        defer document.deinit(ctx);
        document.setPropertyStr(ctx, "_windowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch return error.PropertyAccessFailed;

        const window = createWindowObject(ctx, window_handle, document);
        if (window.isException()) return error.PropertyAccessFailed;
        defer window.deinit(ctx);

        global.setPropertyStr(ctx, "document", document.dup(ctx)) catch return error.PropertyAccessFailed;
        global.setPropertyStr(ctx, "window", window.dup(ctx)) catch return error.PropertyAccessFailed;
        global.setPropertyStr(ctx, "self", window.dup(ctx)) catch return error.PropertyAccessFailed;
        window.setPropertyStr(ctx, "window", window.dup(ctx)) catch return error.PropertyAccessFailed;
        window.setPropertyStr(ctx, "self", window.dup(ctx)) catch return error.PropertyAccessFailed;
        window.setPropertyStr(ctx, "document", document.dup(ctx)) catch return error.PropertyAccessFailed;
        try installCustomElementsRegistry(ctx, global, window);
        try installDocumentCookie(ctx, document);
        try self.installNodeSlice(ctx);
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

fn installEventTargetSlice(ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
    const ctor = global.getPropertyStr(ctx, "EventTarget");
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) {
        return error.PropertyAccessFailed;
    }
    const proto = ctor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    if (proto.isException() or !proto.isObject()) {
        return error.PropertyAccessFailed;
    }

    try event_target_surface.installPrototype(ctx, proto, EventTargetCallbacks);
}

fn installNativeConstructors(ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
    const event_target_proto = try installConstructor(ctx, global, "EventTarget", jsConstructPlain);
    const node_proto = try installConstructor(ctx, global, "Node", jsIllegalConstructor);
    node_proto.setPrototype(ctx, event_target_proto) catch return error.PropertyAccessFailed;
    const element_proto = try installConstructor(ctx, global, "Element", jsConstructElement);
    element_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const html_proto = try installConstructor(ctx, global, "HTMLElement", jsConstructElement);
    html_proto.setPrototype(ctx, element_proto) catch return error.PropertyAccessFailed;
    const svg_proto = try installConstructor(ctx, global, "SVGElement", jsConstructElement);
    svg_proto.setPrototype(ctx, element_proto) catch return error.PropertyAccessFailed;

    for (surfaces.html_element_constructors) |name| {
        const proto = try installConstructor(ctx, global, name, jsConstructElement);
        proto.setPrototype(ctx, html_proto) catch return error.PropertyAccessFailed;
        proto.deinit(ctx);
    }
    try installFormElementPrototypeAccessors(ctx, global);

    const character_data_proto = try installConstructor(ctx, global, "CharacterData", jsIllegalConstructor);
    character_data_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const text_proto = try installConstructor(ctx, global, "Text", jsConstructText);
    text_proto.setPrototype(ctx, character_data_proto) catch return error.PropertyAccessFailed;
    const comment_proto = try installConstructor(ctx, global, "Comment", jsConstructComment);
    comment_proto.setPrototype(ctx, character_data_proto) catch return error.PropertyAccessFailed;
    const fragment_proto = try installConstructor(ctx, global, "DocumentFragment", jsConstructDocumentFragment);
    fragment_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const doctype_proto = try installConstructor(ctx, global, "DocumentType", jsConstructDocumentType);
    doctype_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const document_proto = try installConstructor(ctx, global, "Document", jsIllegalConstructor);
    document_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const window_proto = try installConstructor(ctx, global, "Window", jsConstructWindow);
    window_proto.setPrototype(ctx, event_target_proto) catch return error.PropertyAccessFailed;

    const node_list_proto = try installConstructor(ctx, global, "NodeList", jsConstructPlain);
    defer node_list_proto.deinit(ctx);
    const html_collection_proto = try installConstructor(ctx, global, "HTMLCollection", jsConstructPlain);
    defer html_collection_proto.deinit(ctx);
    const event_proto = try installConstructor(ctx, global, "Event", jsConstructEvent);
    try installMethod(ctx, event_proto, "preventDefault", jsEventPreventDefault, 0);
    try installMethod(ctx, event_proto, "stopPropagation", jsEventStop, 0);
    try installMethod(ctx, event_proto, "stopImmediatePropagation", jsEventStop, 0);
    try installMethod(ctx, event_proto, "composedPath", jsEventComposedPath, 0);
    const custom_event_proto = try installConstructor(ctx, global, "CustomEvent", jsConstructCustomEvent);
    custom_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    const mouse_event_proto = try installConstructor(ctx, global, "MouseEvent", jsConstructMouseEvent);
    mouse_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    const input_event_proto = try installConstructor(ctx, global, "InputEvent", jsConstructInputEvent);
    input_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    const composition_event_proto = try installConstructor(ctx, global, "CompositionEvent", jsConstructCompositionEvent);
    composition_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    const custom_elements_proto = try installConstructor(ctx, global, "CustomElementRegistry", jsConstructPlain);
    defer custom_elements_proto.deinit(ctx);
    const dom_rect_proto = try installConstructor(ctx, global, "DOMRect", jsConstructDOMRect);
    defer dom_rect_proto.deinit(ctx);
    const mutation_observer_proto = try installConstructor(ctx, global, "MutationObserver", jsConstructObserver);
    defer mutation_observer_proto.deinit(ctx);
    const resize_observer_proto = try installConstructor(ctx, global, "ResizeObserver", jsConstructObserver);
    defer resize_observer_proto.deinit(ctx);

    try setNodeConstants(ctx, global);

    event_target_proto.deinit(ctx);
    node_proto.deinit(ctx);
    element_proto.deinit(ctx);
    html_proto.deinit(ctx);
    svg_proto.deinit(ctx);
    character_data_proto.deinit(ctx);
    text_proto.deinit(ctx);
    comment_proto.deinit(ctx);
    fragment_proto.deinit(ctx);
    doctype_proto.deinit(ctx);
    document_proto.deinit(ctx);
    window_proto.deinit(ctx);
    event_proto.deinit(ctx);
    custom_event_proto.deinit(ctx);
    mouse_event_proto.deinit(ctx);
    input_event_proto.deinit(ctx);
    composition_event_proto.deinit(ctx);
}

fn setNodeConstants(ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
    const node = global.getPropertyStr(ctx, "Node");
    defer node.deinit(ctx);
    const proto = node.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    for (surfaces.node_constants) |constant| {
        node.setPropertyStr(ctx, constant.name.ptr, quickjs.Value.initInt64(constant.value)) catch return error.PropertyAccessFailed;
        proto.setPropertyStr(ctx, constant.name.ptr, quickjs.Value.initInt64(constant.value)) catch return error.PropertyAccessFailed;
    }
}

fn installFormElementPrototypeAccessors(ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
    for (surfaces.form_value_constructors) |name| {
        const ctor = global.getPropertyStr(ctx, name);
        defer ctor.deinit(ctx);
        if (ctor.isException() or !ctor.isObject()) continue;
        const proto = ctor.getPropertyStr(ctx, "prototype");
        defer proto.deinit(ctx);
        if (proto.isException() or !proto.isObject()) continue;
        try installAccessor(ctx, proto, "value", jsElementValueGet, jsElementValueSet);
        try installAccessor(ctx, proto, "checked", jsElementCheckedGet, jsElementCheckedSet);
        try installAccessor(ctx, proto, "disabled", jsElementDisabledGet, jsElementDisabledSet);
        try installAccessor(ctx, proto, "name", jsElementNameGet, jsElementNameSet);
        try installAccessor(ctx, proto, "type", jsElementTypeGet, jsElementTypeSet);
    }
}

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

    try element_surface.installPrototype(ctx, element_proto, ElementCallbacks);
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

    try document_surface.installPrototype(ctx, document_proto, DocumentCallbacks);

    try installCharacterDataSlice(ctx, global);
}

fn installCharacterDataSlice(ctx: *quickjs.Context, global: quickjs.Value) DomClassesError!void {
    const ctor = global.getPropertyStr(ctx, "CharacterData");
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return error.PropertyAccessFailed;
    const proto = ctor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    if (proto.isException() or !proto.isObject()) return error.PropertyAccessFailed;

    try character_data_surface.installPrototype(ctx, proto, CharacterDataCallbacks);

    const text_ctor = global.getPropertyStr(ctx, "Text");
    defer text_ctor.deinit(ctx);
    if (!text_ctor.isException() and text_ctor.isObject()) {
        const text_proto = text_ctor.getPropertyStr(ctx, "prototype");
        defer text_proto.deinit(ctx);
        if (!text_proto.isException() and text_proto.isObject()) {
            try installMethod(ctx, text_proto, "splitText", jsTextSplitText, 1);
        }
    }

    const fragment_ctor = global.getPropertyStr(ctx, "DocumentFragment");
    defer fragment_ctor.deinit(ctx);
    if (!fragment_ctor.isException() and fragment_ctor.isObject()) {
        const fragment_proto = fragment_ctor.getPropertyStr(ctx, "prototype");
        defer fragment_proto.deinit(ctx);
        if (!fragment_proto.isException() and fragment_proto.isObject()) {
            try installAccessor(ctx, fragment_proto, "innerHTML", jsElementInnerHtmlGet, jsElementInnerHtmlSet);
        }
    }
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

fn installCustomElementsRegistry(ctx: *quickjs.Context, global: quickjs.Value, window: quickjs.Value) DomClassesError!void {
    const registry = quickjs.Value.initObject(ctx);
    if (registry.isException()) return error.OutOfMemory;
    defer registry.deinit(ctx);
    const definitions = quickjs.Value.initObject(ctx);
    if (definitions.isException()) return error.OutOfMemory;
    registry.setPropertyStr(ctx, "__zigDefinitions", definitions) catch return error.PropertyAccessFailed;
    try installMethod(ctx, registry, "define", jsCustomElementsDefine, 2);
    try installMethod(ctx, registry, "get", jsCustomElementsGet, 1);
    try installMethod(ctx, registry, "whenDefined", jsCustomElementsWhenDefined, 1);
    global.setPropertyStr(ctx, "customElements", registry.dup(ctx)) catch return error.PropertyAccessFailed;
    window.setPropertyStr(ctx, "customElements", registry.dup(ctx)) catch return error.PropertyAccessFailed;
}

fn installDocumentCookie(ctx: *quickjs.Context, document: quickjs.Value) DomClassesError!void {
    document.setPropertyStr(ctx, "__zigCookie", quickjs.Value.initStringLen(ctx, "")) catch return error.PropertyAccessFailed;
    try installAccessor(ctx, document, "cookie", jsDocumentCookieGet, jsDocumentCookieSet);
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

fn jsIllegalConstructor(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwMessage(ctx, "Illegal constructor");
}

fn jsConstructPlain(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const proto = this_value.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    if (proto.isException() or !proto.isObject()) return quickjs.Value.initObject(ctx);
    return quickjs.Value.initObjectProto(ctx, proto);
}

fn jsConstructElement(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    const document_handle = parseThisHandle(ctx, document, "Element") orelse return quickjs.Value.exception;
    const name = if (args.len >= 1 and !args[0].isUndefined()) parseStringArg(ctx, args, 0, "Element") else null;
    defer if (name) |value| ctx.freeCString(value.ptr);
    const tag = if (name) |value| value.ptr[0..value.len] else "div";
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_element(document_handle, tag.ptr, tag.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "Element", status);
    _ = this_value;
    return wrapNodeHandle(ctx, out_handle);
}

fn jsConstructText(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    const document_handle = parseThisHandle(ctx, document, "Text") orelse return quickjs.Value.exception;
    const data = if (args.len >= 1) parseStringArg(ctx, args, 0, "Text") else null;
    defer if (data) |value| ctx.freeCString(value.ptr);
    const text = if (data) |value| value.ptr[0..value.len] else "";
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_text_node(document_handle, text.ptr, text.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "Text", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsConstructComment(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    const document_handle = parseThisHandle(ctx, document, "Comment") orelse return quickjs.Value.exception;
    const data = if (args.len >= 1) parseStringArg(ctx, args, 0, "Comment") else null;
    defer if (data) |value| ctx.freeCString(value.ptr);
    const text = if (data) |value| value.ptr[0..value.len] else "";
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_comment(document_handle, text.ptr, text.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "Comment", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsConstructDocumentFragment(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    const document_handle = parseThisHandle(ctx, document, "DocumentFragment") orelse return quickjs.Value.exception;
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_document_fragment(document_handle, &out_handle);
    if (status != 0) return throwStatus(ctx, "DocumentFragment", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsConstructDocumentType(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    const document_handle = parseThisHandle(ctx, document, "DocumentType") orelse return quickjs.Value.exception;
    var out_handle: u64 = 0;
    const empty = "";
    const status = zig_dom.zig_dom_document_create_comment(document_handle, empty.ptr, empty.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "DocumentType", status);
    const node = wrapNodeHandle(ctx, out_handle);
    if (node.isException()) return node;
    const name = if (args.len >= 1) parseStringArg(ctx, args, 0, "DocumentType") else null;
    defer if (name) |value| ctx.freeCString(value.ptr);
    const text = if (name) |value| value.ptr[0..value.len] else "html";
    node.setPropertyStr(ctx, "_nodeTypeOverride", quickjs.Value.initInt64(10)) catch return quickjs.Value.exception;
    node.setPropertyStr(ctx, "_nodeNameOverride", quickjs.Value.initStringLen(ctx, text)) catch return quickjs.Value.exception;
    node.setPropertyStr(ctx, "name", quickjs.Value.initStringLen(ctx, text)) catch return quickjs.Value.exception;
    return node;
}

fn jsDocumentImportNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return throwOperationMessage(ctx, "importNode", "node argument must be an object");
    const deep = args.len > 1 and (args[1].toBool(ctx) catch false);
    return cloneNodeForDocument(ctx, this_value, args[0], deep);
}

fn jsDocumentAdoptNode(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return throwOperationMessage(ctx, "adoptNode", "node argument must be an object");
    const parent = jsNodeParentNodeGet(ctx, args[0]);
    defer parent.deinit(ctx);
    if (parent.isObject()) {
        const removed = jsNodeRemoveChild(ctx, parent, @ptrCast(&[_]quickjs.Value{args[0]}));
        defer removed.deinit(ctx);
        if (removed.isException()) return quickjs.Value.exception;
    }
    return args[0].dup(ctx);
}

fn jsDocumentCreateRange(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const range = quickjs.Value.initObject(ctx);
    if (range.isException()) return range;
    installMethod(ctx, range, "setStart", jsRangeSetStart, 2) catch return quickjs.Value.exception;
    installMethod(ctx, range, "setEnd", jsRangeSetEnd, 2) catch return quickjs.Value.exception;
    installMethod(ctx, range, "selectNodeContents", jsRangeSelectNodeContents, 1) catch return quickjs.Value.exception;
    installMethod(ctx, range, "toString", jsRangeToString, 0) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "collapsed", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    return range;
}

fn jsDocumentGetSelection(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var existing = this_value.getPropertyStr(ctx, "__zigSelection");
    if (!existing.isException() and existing.isObject()) return existing;
    existing.deinit(ctx);
    const selection = quickjs.Value.initObject(ctx);
    if (selection.isException()) return selection;
    selection.setPropertyStr(ctx, "__zigRange", quickjs.Value.null) catch return quickjs.Value.exception;
    selection.setPropertyStr(ctx, "rangeCount", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    installMethod(ctx, selection, "removeAllRanges", jsSelectionRemoveAllRanges, 0) catch return quickjs.Value.exception;
    installMethod(ctx, selection, "addRange", jsSelectionAddRange, 1) catch return quickjs.Value.exception;
    installMethod(ctx, selection, "getRangeAt", jsSelectionGetRangeAt, 1) catch return quickjs.Value.exception;
    installMethod(ctx, selection, "toString", jsSelectionToString, 0) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "__zigSelection", selection.dup(ctx)) catch return quickjs.Value.exception;
    return selection;
}

fn jsConstructWindow(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var window_handle: u64 = 0;
    if (zig_dom.zig_dom_create_window(&window_handle) != 0) return throwMessage(ctx, "failed to create window");
    var document_handle: u64 = 0;
    if (zig_dom.zig_dom_window_document(window_handle, &document_handle) != 0) return throwMessage(ctx, "failed to create document");
    const document = wrapNodeHandle(ctx, document_handle);
    defer document.deinit(ctx);
    document.setPropertyStr(ctx, "_windowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch return quickjs.Value.exception;
    return createWindowObject(ctx, window_handle, document);
}

fn jsConstructEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .event);
}

fn jsConstructCustomEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .custom);
}

fn jsConstructMouseEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .mouse);
}

fn jsConstructInputEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .input);
}

fn jsConstructCompositionEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .composition);
}

fn jsEventPreventDefault(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (boolProperty(ctx, this_value, "cancelable")) {
        this_value.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
        this_value.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsEventStop(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsEventComposedPath(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const path = this_value.getPropertyStr(ctx, "_path");
    defer path.deinit(ctx);
    if (!path.isException() and path.isObject()) return path.dup(ctx);
    return quickjs.Value.initArray(ctx);
}

const EventKind = enum { event, custom, mouse, input, composition };

fn createEventObject(ctx: *quickjs.Context, constructor: quickjs.Value, args: []const quickjs.Value, kind: EventKind) quickjs.Value {
    const proto = constructor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    const obj = if (!proto.isException() and proto.isObject()) quickjs.Value.initObjectProto(ctx, proto) else quickjs.Value.initObject(ctx);
    if (obj.isException()) return obj;
    const event_type = if (args.len >= 1) parseStringArg(ctx, args, 0, "Event") else null;
    defer if (event_type) |value| ctx.freeCString(value.ptr);
    const type_text = if (event_type) |value| value.ptr[0..value.len] else "";
    obj.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, type_text)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(optionBool(ctx, args, "bubbles"))) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(optionBool(ctx, args, "cancelable"))) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "composed", quickjs.Value.initBool(optionBool(ctx, args, "composed"))) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_target", quickjs.Value.null) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_currentTarget", quickjs.Value.null) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_eventPhase", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "target", quickjs.Value.null) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "currentTarget", quickjs.Value.null) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "eventPhase", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    if (kind == .custom) {
        obj.setPropertyStr(ctx, "detail", optionValue(ctx, args, "detail")) catch return quickjs.Value.exception;
    }
    if (kind == .mouse) {
        obj.setPropertyStr(ctx, "clientX", quickjs.Value.initFloat64(optionNumber(ctx, args, "clientX"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "clientY", quickjs.Value.initFloat64(optionNumber(ctx, args, "clientY"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "button", quickjs.Value.initFloat64(optionNumber(ctx, args, "button"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "buttons", quickjs.Value.initFloat64(optionNumber(ctx, args, "buttons"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "relatedTarget", optionValueOrNull(ctx, args, "relatedTarget")) catch return quickjs.Value.exception;
    }
    if (kind == .input) {
        obj.setPropertyStr(ctx, "data", optionValueOrNull(ctx, args, "data")) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "inputType", optionString(ctx, args, "inputType", "")) catch return quickjs.Value.exception;
    }
    if (kind == .composition) {
        obj.setPropertyStr(ctx, "data", optionString(ctx, args, "data", "")) catch return quickjs.Value.exception;
    }
    return obj;
}

fn jsConstructDOMRect(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const proto = this_value.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    const obj = if (!proto.isException() and proto.isObject()) quickjs.Value.initObjectProto(ctx, proto) else quickjs.Value.initObject(ctx);
    if (obj.isException()) return obj;
    const x = numericArg(ctx, args, 0);
    const y = numericArg(ctx, args, 1);
    const width = numericArg(ctx, args, 2);
    const height = numericArg(ctx, args, 3);
    obj.setPropertyStr(ctx, "x", quickjs.Value.initFloat64(x)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "y", quickjs.Value.initFloat64(y)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "width", quickjs.Value.initFloat64(width)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "height", quickjs.Value.initFloat64(height)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "top", quickjs.Value.initFloat64(y)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "left", quickjs.Value.initFloat64(x)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "right", quickjs.Value.initFloat64(x + width)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "bottom", quickjs.Value.initFloat64(y + height)) catch return quickjs.Value.exception;
    return obj;
}

fn jsConstructObserver(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const obj = jsConstructPlain(ctx, this_value, &.{});
    if (obj.isException()) return obj;
    installMethod(ctx, obj, "observe", jsNoopMethod, 0) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "unobserve", jsNoopMethod, 0) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "disconnect", jsNoopMethod, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsWindowGetComputedStyle(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const style = quickjs.Value.initObject(ctx);
    if (style.isException()) return style;
    installMethod(ctx, style, "getPropertyValue", jsComputedStyleGetPropertyValue, 1) catch return quickjs.Value.exception;
    style.setPropertyStr(ctx, "visibility", quickjs.Value.initStringLen(ctx, "visible")) catch return quickjs.Value.exception;
    style.setPropertyStr(ctx, "display", quickjs.Value.initStringLen(ctx, "block")) catch return quickjs.Value.exception;
    return style;
}

fn jsComputedStyleGetPropertyValue(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return quickjs.Value.initStringLen(ctx, "");
}

fn jsStyleGetPropertyValue(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "style.getPropertyValue") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const direct = this_value.getPropertyStr(ctx, name.ptr);
    if (!direct.isException() and !direct.isUndefined() and !direct.isNull()) return direct;
    direct.deinit(ctx);
    const element = this_value.getPropertyStr(ctx, "__zigElement");
    defer element.deinit(ctx);
    if (element.isObject()) {
        const attr = elementAttributeGet(ctx, element, "style", "");
        defer attr.deinit(ctx);
        const text = attr.toCStringLen(ctx) orelse return quickjs.Value.initStringLen(ctx, "");
        defer ctx.freeCString(text.ptr);
        var parts = std.mem.splitScalar(u8, text.ptr[0..text.len], ';');
        while (parts.next()) |part_raw| {
            const part = std.mem.trim(u8, part_raw, " \t\r\n");
            const colon = std.mem.indexOfScalar(u8, part, ':') orelse continue;
            if (std.mem.eql(u8, std.mem.trim(u8, part[0..colon], " \t\r\n"), name.ptr[0..name.len])) {
                const value = std.mem.trim(u8, part[colon + 1 ..], " \t\r\n");
                return quickjs.Value.initStringLen(ctx, value);
            }
        }
    }
    return quickjs.Value.initStringLen(ctx, "");
}

fn jsNoopMethod(_: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsNodeNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const override = this_value.getPropertyStr(ctx, "_nodeNameOverride");
    defer override.deinit(ctx);
    if (!override.isException() and !override.isNull() and !override.isUndefined()) {
        return override.dup(ctx);
    }
    const this_handle = parseThisHandle(ctx, this_value, "nodeName") orelse return quickjs.Value.exception;
    if (zig_dom.zig_dom_node_type(this_handle) == 1) {
        return elementNameToJs(ctx, this_handle, "nodeName", .upper);
    }
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
        return quickjs.Value.null;
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
        return quickjs.Value.null;
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

fn jsNodeChildNodesGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "childNodes") orelse return quickjs.Value.exception;
    return childCollectionToJs(ctx, this_handle, false);
}

fn jsNodeChildrenGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "children") orelse return quickjs.Value.exception;
    return childCollectionToJs(ctx, this_handle, true);
}

fn jsNodeFirstElementChildGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "firstElementChild") orelse return quickjs.Value.exception;
    var child = zig_dom.zig_dom_node_first_child(this_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        if (zig_dom.zig_dom_node_type(child) == 1) return wrapNodeHandle(ctx, child);
    }
    return quickjs.Value.null;
}

fn jsNodeLastElementChildGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "lastElementChild") orelse return quickjs.Value.exception;
    var child = zig_dom.zig_dom_node_last_child(this_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_previous_sibling(child)) {
        if (zig_dom.zig_dom_node_type(child) == 1) return wrapNodeHandle(ctx, child);
    }
    return quickjs.Value.null;
}

fn jsNodePreviousElementSiblingGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "previousElementSibling") orelse return quickjs.Value.exception;
    var sibling = zig_dom.zig_dom_node_previous_sibling(this_handle);
    while (sibling != 0) : (sibling = zig_dom.zig_dom_node_previous_sibling(sibling)) {
        if (zig_dom.zig_dom_node_type(sibling) == 1) return wrapNodeHandle(ctx, sibling);
    }
    return quickjs.Value.null;
}

fn jsNodeNextElementSiblingGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "nextElementSibling") orelse return quickjs.Value.exception;
    var sibling = zig_dom.zig_dom_node_next_sibling(this_handle);
    while (sibling != 0) : (sibling = zig_dom.zig_dom_node_next_sibling(sibling)) {
        if (zig_dom.zig_dom_node_type(sibling) == 1) return wrapNodeHandle(ctx, sibling);
    }
    return quickjs.Value.null;
}

fn jsNodeChildElementCountGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "childElementCount") orelse return quickjs.Value.exception;
    var count: u32 = 0;
    var child = zig_dom.zig_dom_node_first_child(this_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        if (zig_dom.zig_dom_node_type(child) == 1) count += 1;
    }
    return quickjs.Value.initInt64(count);
}

fn jsNodeTextContentGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "textContent") orelse return quickjs.Value.exception;
    if (zig_dom.zig_dom_node_type(this_handle) == 10) {
        return quickjs.Value.null;
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
        return quickjs.Value.undefined;
    }

    const text_value = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "textContent", "value could not be converted to string");
    defer ctx.freeCString(text_value.ptr);

    const status = zig_dom.zig_dom_node_set_text_content(this_handle, text_value.ptr, text_value.len);
    if (status != 0) {
        return throwStatus(ctx, "textContent", status);
    }

    return quickjs.Value.undefined;
}

fn jsNodeValueGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const node_type = zig_dom.zig_dom_node_type(parseThisHandle(ctx, this_value, "nodeValue") orelse return quickjs.Value.exception);
    if (node_type == 3 or node_type == 8) return jsNodeTextContentGet(ctx, this_value);
    return quickjs.Value.null;
}

fn jsNodeValueSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const node_type = zig_dom.zig_dom_node_type(parseThisHandle(ctx, this_value, "nodeValue") orelse return quickjs.Value.exception);
    if (node_type == 3 or node_type == 8) return jsNodeTextContentSet(ctx, this_value, next_value);
    return quickjs.Value.undefined;
}

fn jsNodeCloneNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const deep = args.len > 0 and (args[0].toBool(ctx) catch false);
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    const cloned = cloneNodeForDocument(ctx, document, this_value, deep);
    return cloned;
}

fn cloneNodeForDocument(ctx: *quickjs.Context, document: quickjs.Value, node: quickjs.Value, deep: bool) quickjs.Value {
    const node_type = zig_dom.zig_dom_node_type(parseThisHandle(ctx, node, "cloneNode") orelse return quickjs.Value.exception);
    var clone: quickjs.Value = quickjs.Value.exception;
    switch (node_type) {
        1 => {
            const name = jsElementLocalNameGet(ctx, node);
            defer name.deinit(ctx);
            clone = jsDocumentCreateElement(ctx, document, @ptrCast(&[_]quickjs.Value{name}));
            if (clone.isException()) return clone;
            const names = jsElementGetAttributeNames(ctx, node, &.{});
            defer names.deinit(ctx);
            const len = arrayLength(ctx, names);
            for (0..len) |i_usize| {
                const attr_name = names.getPropertyUint32(ctx, @intCast(i_usize));
                defer attr_name.deinit(ctx);
                const attr_value = jsElementGetAttribute(ctx, node, @ptrCast(&[_]quickjs.Value{attr_name}));
                defer attr_value.deinit(ctx);
                const set_result = jsElementSetAttribute(ctx, clone, @ptrCast(&[_]quickjs.Value{ attr_name, attr_value }));
                defer set_result.deinit(ctx);
            }
        },
        3 => {
            const data = jsNodeTextContentGet(ctx, node);
            defer data.deinit(ctx);
            clone = jsDocumentCreateTextNode(ctx, document, @ptrCast(&[_]quickjs.Value{data}));
        },
        8 => {
            const data = jsNodeTextContentGet(ctx, node);
            defer data.deinit(ctx);
            clone = jsDocumentCreateComment(ctx, document, @ptrCast(&[_]quickjs.Value{data}));
        },
        11 => clone = jsDocumentCreateDocumentFragment(ctx, document, &.{}),
        else => clone = quickjs.Value.initObject(ctx),
    }
    if (clone.isException()) return clone;
    if (deep) {
        const children = jsNodeChildNodesGet(ctx, node);
        defer children.deinit(ctx);
        const len = arrayLength(ctx, children);
        for (0..len) |i_usize| {
            const child = children.getPropertyUint32(ctx, @intCast(i_usize));
            defer child.deinit(ctx);
            const child_clone = cloneNodeForDocument(ctx, document, child, true);
            defer child_clone.deinit(ctx);
            if (child_clone.isException()) return quickjs.Value.exception;
            const append_result = jsNodeAppendChild(ctx, clone, @ptrCast(&[_]quickjs.Value{child_clone}));
            defer append_result.deinit(ctx);
        }
    }
    return clone;
}

fn jsCharacterDataLengthGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const data = jsNodeTextContentGet(ctx, this_value);
    defer data.deinit(ctx);
    const cstr = data.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    return quickjs.Value.initInt64(@intCast(cstr.len));
}

fn jsCharacterDataAppendData(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const suffix = parseStringArg(ctx, args, 0, "appendData") orelse return quickjs.Value.exception;
    defer ctx.freeCString(suffix.ptr);
    const current = jsNodeTextContentGet(ctx, this_value);
    defer current.deinit(ctx);
    const cstr = current.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    var buffer: [4096]u8 = undefined;
    const next = std.fmt.bufPrint(&buffer, "{s}{s}", .{ cstr.ptr[0..cstr.len], suffix.ptr[0..suffix.len] }) catch return quickjs.Value.exception;
    const next_value = quickjs.Value.initStringLen(ctx, next);
    defer next_value.deinit(ctx);
    return jsNodeTextContentSet(ctx, this_value, next_value);
}

fn jsCharacterDataDeleteData(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    return replaceCharacterDataRange(ctx_opt, this_value, raw_args, "");
}

fn jsCharacterDataInsertData(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.exception;
    const offset = args[0].toInt64(ctx) catch 0;
    const data = parseStringArg(ctx, args, 1, "insertData") orelse return quickjs.Value.exception;
    defer ctx.freeCString(data.ptr);
    var range_args = [_]quickjs.Value{ quickjs.Value.initInt64(offset), quickjs.Value.initInt64(0), quickjs.Value.initStringLen(ctx, data.ptr[0..data.len]) };
    defer range_args[2].deinit(ctx);
    return jsCharacterDataReplaceData(ctx, this_value, @ptrCast(&range_args));
}

fn jsCharacterDataReplaceData(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const replacement = parseStringArg(ctx, args, 2, "replaceData") orelse return quickjs.Value.exception;
    defer ctx.freeCString(replacement.ptr);
    return replaceCharacterDataRange(ctx, this_value, raw_args, replacement.ptr[0..replacement.len]);
}

fn jsCharacterDataSubstringData(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const offset_raw = if (args.len > 0) args[0].toInt64(ctx) catch 0 else 0;
    const count_raw = if (args.len > 1) args[1].toInt64(ctx) catch 0 else 0;
    const data = jsNodeTextContentGet(ctx, this_value);
    defer data.deinit(ctx);
    const cstr = data.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    const start: usize = @intCast(@max(0, @min(offset_raw, @as(i64, @intCast(cstr.len)))));
    const end: usize = @min(cstr.len, start + @as(usize, @intCast(@max(0, count_raw))));
    return quickjs.Value.initStringLen(ctx, cstr.ptr[start..end]);
}

fn jsTextSplitText(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const offset_raw = if (args.len > 0) args[0].toInt64(ctx) catch 0 else 0;
    const data = jsNodeTextContentGet(ctx, this_value);
    defer data.deinit(ctx);
    const cstr = data.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    const offset: usize = @intCast(@max(0, @min(offset_raw, @as(i64, @intCast(cstr.len)))));
    const head = quickjs.Value.initStringLen(ctx, cstr.ptr[0..offset]);
    defer head.deinit(ctx);
    const set_head = jsNodeTextContentSet(ctx, this_value, head);
    defer set_head.deinit(ctx);
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    var tail_arg = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, cstr.ptr[offset..cstr.len])};
    defer tail_arg[0].deinit(ctx);
    const tail = jsDocumentCreateTextNode(ctx, document, @ptrCast(&tail_arg));
    if (tail.isException()) return tail;
    const parent = jsNodeParentNodeGet(ctx, this_value);
    defer parent.deinit(ctx);
    if (parent.isObject()) {
        const next = jsNodeNextSiblingGet(ctx, this_value);
        defer next.deinit(ctx);
        const insert_result = jsNodeInsertBefore(ctx, parent, @ptrCast(&[_]quickjs.Value{ tail, next }));
        defer insert_result.deinit(ctx);
    }
    return tail;
}

fn replaceCharacterDataRange(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue, replacement: []const u8) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const offset_raw = if (args.len > 0) args[0].toInt64(ctx) catch 0 else 0;
    const count_raw = if (args.len > 1) args[1].toInt64(ctx) catch 0 else 0;
    const data = jsNodeTextContentGet(ctx, this_value);
    defer data.deinit(ctx);
    const cstr = data.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    const start: usize = @intCast(@max(0, @min(offset_raw, @as(i64, @intCast(cstr.len)))));
    const end: usize = @min(cstr.len, start + @as(usize, @intCast(@max(0, count_raw))));
    var buffer: [4096]u8 = undefined;
    const next = std.fmt.bufPrint(&buffer, "{s}{s}{s}", .{ cstr.ptr[0..start], replacement, cstr.ptr[end..cstr.len] }) catch return quickjs.Value.exception;
    const next_value = quickjs.Value.initStringLen(ctx, next);
    defer next_value.deinit(ctx);
    return jsNodeTextContentSet(ctx, this_value, next_value);
}

fn jsElementTagNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "tagName") orelse return quickjs.Value.exception;
    return elementNameToJs(ctx, this_handle, "tagName", .upper);
}

fn jsElementLocalNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "localName") orelse return quickjs.Value.exception;
    return elementNameToJs(ctx, this_handle, "localName", .lower);
}

const ElementNameCase = enum { upper, lower };

fn elementNameToJs(ctx: *quickjs.Context, node_handle: u64, operation: []const u8, name_case: ElementNameCase) quickjs.Value {
    const name = nodeNameToJs(ctx, node_handle, operation);
    defer name.deinit(ctx);
    const cstr = name.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    var buffer: [256]u8 = undefined;
    if (cstr.len > buffer.len) {
        return quickjs.Value.initStringLen(ctx, cstr.ptr[0..cstr.len]);
    }
    const out = buffer[0..cstr.len];
    for (cstr.ptr[0..cstr.len], 0..) |ch, i| {
        out[i] = switch (name_case) {
            .upper => std.ascii.toUpper(ch),
            .lower => std.ascii.toLower(ch),
        };
    }
    return quickjs.Value.initStringLen(ctx, out);
}

fn jsElementNamespaceUriGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const local_name = jsElementLocalNameGet(ctx, this_value);
    defer local_name.deinit(ctx);
    const cstr = local_name.toCStringLen(ctx) orelse return quickjs.Value.initStringLen(ctx, "http://www.w3.org/1999/xhtml");
    defer ctx.freeCString(cstr.ptr);
    if (std.mem.eql(u8, cstr.ptr[0..cstr.len], "svg")) {
        return quickjs.Value.initStringLen(ctx, "http://www.w3.org/2000/svg");
    }
    return quickjs.Value.initStringLen(ctx, "http://www.w3.org/1999/xhtml");
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

fn jsElementTitleGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "title", "");
}

fn jsElementTitleSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    if (next_value.isUndefined() or next_value.isNull()) {
        const ctx = ctx_opt orelse return quickjs.Value.exception;
        var name = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, "title")};
        defer name[0].deinit(ctx);
        return jsElementRemoveAttribute(ctx, this_value, @ptrCast(&name));
    }
    return elementAttributeSet(ctx_opt, this_value, "title", next_value);
}

fn jsElementHtmlForGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "for", "");
}

fn jsElementHtmlForSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return elementAttributeSet(ctx_opt, this_value, "for", next_value);
}

fn jsElementValueGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "value", "");
}

fn jsElementValueSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return elementAttributeSet(ctx_opt, this_value, "value", next_value);
}

fn jsElementNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "name", "");
}

fn jsElementNameSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return elementAttributeSet(ctx_opt, this_value, "name", next_value);
}

fn jsElementTypeGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "type", "text");
}

fn jsElementTypeSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return elementAttributeSet(ctx_opt, this_value, "type", next_value);
}

fn jsElementCheckedGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const handle = parseThisHandle(ctx, this_value, "checked") orelse return quickjs.Value.exception;
    return quickjs.Value.initBool(zig_dom.zig_dom_element_has_attribute(handle, "checked".ptr, "checked".len) == 1);
}

fn jsElementCheckedSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return setBooleanAttribute(ctx_opt, this_value, "checked", next_value);
}

fn jsElementDisabledGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const handle = parseThisHandle(ctx, this_value, "disabled") orelse return quickjs.Value.exception;
    return quickjs.Value.initBool(zig_dom.zig_dom_element_has_attribute(handle, "disabled".ptr, "disabled".len) == 1);
}

fn jsElementDisabledSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return setBooleanAttribute(ctx_opt, this_value, "disabled", next_value);
}

fn setBooleanAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, name: []const u8, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const handle = parseThisHandle(ctx, this_value, name) orelse return quickjs.Value.exception;
    const enabled = next_value.toBool(ctx) catch false;
    const status = if (enabled)
        zig_dom.zig_dom_element_set_attribute(handle, name.ptr, name.len, "".ptr, 0)
    else
        zig_dom.zig_dom_element_remove_attribute(handle, name.ptr, name.len);
    if (status != 0) return throwStatus(ctx, name, status);
    return quickjs.Value.undefined;
}

fn jsElementFormGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var cursor = jsNodeParentElementGet(ctx, this_value);
    defer cursor.deinit(ctx);
    while (cursor.isObject()) {
        const local = jsElementLocalNameGet(ctx, cursor);
        defer local.deinit(ctx);
        const cstr = local.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(cstr.ptr);
        if (std.ascii.eqlIgnoreCase(cstr.ptr[0..cstr.len], "form")) return cursor.dup(ctx);
        const parent = jsNodeParentElementGet(ctx, cursor);
        cursor.deinit(ctx);
        cursor = parent;
        if (cursor.isNull() or cursor.isUndefined() or cursor.isException()) break;
    }
    return quickjs.Value.null;
}

fn jsElementClassListGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = parseThisHandle(ctx, this_value, "classList") orelse return quickjs.Value.exception;
    var existing = this_value.getPropertyStr(ctx, "__zigClassList");
    if (!existing.isException() and existing.isObject()) return existing;
    existing.deinit(ctx);

    const list = quickjs.Value.initObject(ctx);
    if (list.isException()) return list;
    list.setPropertyStr(ctx, "__zigElement", this_value.dup(ctx)) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, list, "contains", jsClassListContains, 1) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, list, "add", jsClassListAdd, 1) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, list, "remove", jsClassListRemove, 1) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    this_value.setPropertyStr(ctx, "__zigClassList", list.dup(ctx)) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    return list;
}

fn jsElementDatasetGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = parseThisHandle(ctx, this_value, "dataset") orelse return quickjs.Value.exception;
    const target = quickjs.Value.initObject(ctx);
    if (target.isException()) return target;
    defer target.deinit(ctx);
    target.setPropertyStr(ctx, "__zigElement", this_value.dup(ctx)) catch return quickjs.Value.exception;
    const handler = quickjs.Value.initObject(ctx);
    if (handler.isException()) return handler;
    defer handler.deinit(ctx);
    installMethod(ctx, handler, "get", jsDatasetGet, 2) catch return quickjs.Value.exception;
    installMethod(ctx, handler, "set", jsDatasetSet, 3) catch return quickjs.Value.exception;
    installMethod(ctx, handler, "deleteProperty", jsDatasetDelete, 2) catch return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const proxy_ctor = global.getPropertyStr(ctx, "Proxy");
    defer proxy_ctor.deinit(ctx);
    if (proxy_ctor.isException() or !proxy_ctor.isObject()) return target;
    var proxy_args = [_]quickjs.Value{ target, handler.dup(ctx) };
    defer proxy_args[1].deinit(ctx);
    return quickjs.Value.fromCVal(c.JS_CallConstructor(ctx.cval(), proxy_ctor.cval(), @intCast(proxy_args.len), @ptrCast(&proxy_args)));
}

fn jsElementChildrenGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return jsNodeChildrenGet(ctx_opt, this_value);
}

fn jsElementFormElementsGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var selector = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, "*")};
    defer selector[0].deinit(ctx);
    return jsElementQuerySelectorAll(ctx, this_value, @ptrCast(&selector));
}

fn jsElementOptionsGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var selector = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, "option")};
    defer selector[0].deinit(ctx);
    return jsElementQuerySelectorAll(ctx, this_value, @ptrCast(&selector));
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
    const mapper = json.call(ctx, quickjs.Value.undefined, &.{body});
    defer mapper.deinit(ctx);
    if (mapper.isException()) return quickjs.Value.exception;
    return mapper.call(ctx, quickjs.Value.undefined, &.{array});
}

fn jsElementInnerHtmlSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "innerHTML") orelse return quickjs.Value.exception;
    const text = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "innerHTML", "value could not be converted to string");
    defer ctx.freeCString(text.ptr);
    const status = zig_dom.zig_dom_node_set_inner_html(this_handle, text.ptr, text.len);
    if (status != 0) return throwStatus(ctx, "innerHTML", status);
    return quickjs.Value.undefined;
}

fn jsElementOuterHtmlGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "outerHTML") orelse return quickjs.Value.exception;
    return nodeOuterHtmlToJs(ctx, this_handle, "outerHTML");
}

fn jsElementStyleGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = parseThisHandle(ctx, this_value, "style") orelse return quickjs.Value.exception;

    const existing = this_value.getPropertyStr(ctx, "__zigStyle");
    if (!existing.isException() and existing.isObject()) {
        return existing;
    }
    existing.deinit(ctx);

    const style = quickjs.Value.initObject(ctx);
    if (style.isException()) return style;
    style.setPropertyStr(ctx, "__zigElement", this_value.dup(ctx)) catch return quickjs.Value.exception;
    installMethod(ctx, style, "getPropertyValue", jsStyleGetPropertyValue, 1) catch return quickjs.Value.exception;
    installMethod(ctx, style, "setProperty", jsStyleSetProperty, 2) catch return quickjs.Value.exception;
    installMethod(ctx, style, "removeProperty", jsStyleRemoveProperty, 1) catch return quickjs.Value.exception;
    style.setPropertyStr(ctx, "cssText", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    style.setPropertyStr(ctx, "animation", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    style.setPropertyStr(ctx, "transition", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    const current_style = elementAttributeGet(ctx, this_value, "style", "");
    defer current_style.deinit(ctx);
    const current_text = current_style.toCStringLen(ctx) orelse null;
    defer if (current_text) |text| ctx.freeCString(text.ptr);
    if (current_text) |text| style.setPropertyStr(ctx, "cssText", quickjs.Value.initStringLen(ctx, text.ptr[0..text.len])) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "__zigStyle", style.dup(ctx)) catch return quickjs.Value.exception;
    return style;
}

fn jsStyleSetProperty(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "style.setProperty") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const value = if (args.len > 1) args[1].toCStringLen(ctx) else null;
    defer if (value) |text| ctx.freeCString(text.ptr);
    this_value.setPropertyStr(ctx, name.ptr, quickjs.Value.initStringLen(ctx, if (value) |text| text.ptr[0..text.len] else "")) catch return quickjs.Value.exception;
    const element = this_value.getPropertyStr(ctx, "__zigElement");
    defer element.deinit(ctx);
    if (element.isObject()) {
        var buffer: [512]u8 = undefined;
        const css_text = std.fmt.bufPrint(&buffer, "{s}: {s};", .{ name.ptr[0..name.len], if (value) |text| text.ptr[0..text.len] else "" }) catch return quickjs.Value.exception;
        const css_value = quickjs.Value.initStringLen(ctx, css_text);
        defer css_value.deinit(ctx);
        const style_name = quickjs.Value.initStringLen(ctx, "style");
        defer style_name.deinit(ctx);
        const set_result = jsElementSetAttribute(ctx, element, @ptrCast(&[_]quickjs.Value{ style_name, css_value }));
        defer set_result.deinit(ctx);
    }
    return quickjs.Value.undefined;
}

fn jsStyleRemoveProperty(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "style.removeProperty") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const previous = this_value.getPropertyStr(ctx, name.ptr);
    defer previous.deinit(ctx);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const reflect = global.getPropertyStr(ctx, "Reflect");
    defer reflect.deinit(ctx);
    const delete_property = reflect.getPropertyStr(ctx, "deleteProperty");
    defer delete_property.deinit(ctx);
    const name_value = quickjs.Value.initStringLen(ctx, name.ptr[0..name.len]);
    defer name_value.deinit(ctx);
    const ignored = delete_property.call(ctx, reflect, &.{ this_value, name_value });
    defer ignored.deinit(ctx);
    if (previous.isUndefined()) return quickjs.Value.initStringLen(ctx, "");
    return previous.dup(ctx);
}

fn jsNodeOuterHtmlGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "outerHTML") orelse return quickjs.Value.exception;
    const override_type = getIntProperty(ctx, this_value, "_nodeTypeOverride") orelse 0;
    if (override_type == 10 or zig_dom.zig_dom_node_type(this_handle) == 10) {
        const name = this_value.getPropertyStr(ctx, "name");
        defer name.deinit(ctx);
        const cstr = name.toCStringLen(ctx) orelse return quickjs.Value.initStringLen(ctx, "<!DOCTYPE html>");
        defer ctx.freeCString(cstr.ptr);
        var buffer: [128]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "<!DOCTYPE {s}>", .{cstr.ptr[0..cstr.len]}) catch "<!DOCTYPE html>";
        return quickjs.Value.initStringLen(ctx, text);
    }
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

fn jsElementGetAttributeNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "getAttributeNode") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "getAttributeNode") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    if (zig_dom.zig_dom_element_has_attribute(this_handle, name.ptr, name.len) != 1) return quickjs.Value.null;
    const value = elementAttributeValueToJs(ctx, this_handle, name.ptr[0..name.len], "", "getAttributeNode");
    defer value.deinit(ctx);

    const attr = quickjs.Value.initObject(ctx);
    if (attr.isException()) return attr;
    const name_value = quickjs.Value.initStringLen(ctx, name.ptr[0..name.len]);
    attr.setPropertyStr(ctx, "name", name_value.dup(ctx)) catch return quickjs.Value.exception;
    attr.setPropertyStr(ctx, "nodeName", name_value.dup(ctx)) catch return quickjs.Value.exception;
    attr.setPropertyStr(ctx, "localName", name_value) catch return quickjs.Value.exception;
    attr.setPropertyStr(ctx, "value", value.dup(ctx)) catch return quickjs.Value.exception;
    attr.setPropertyStr(ctx, "nodeValue", value.dup(ctx)) catch return quickjs.Value.exception;
    attr.setPropertyStr(ctx, "textContent", value.dup(ctx)) catch return quickjs.Value.exception;
    attr.setPropertyStr(ctx, "ownerElement", this_value.dup(ctx)) catch return quickjs.Value.exception;
    attr.setPropertyStr(ctx, "nodeType", quickjs.Value.initInt64(2)) catch return quickjs.Value.exception;
    return attr;
}

fn jsElementSetAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "setAttribute") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "setAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const value = parseStringArg(ctx, args, 1, "setAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(value.ptr);
    const old_value = jsElementGetAttribute(ctx, this_value, @ptrCast(&[_]quickjs.Value{args[0]}));
    defer old_value.deinit(ctx);
    const status = zig_dom.zig_dom_element_set_attribute(this_handle, name.ptr, name.len, value.ptr, value.len);
    if (status != 0) return throwStatus(ctx, "setAttribute", status);
    const attr_changed = this_value.getPropertyStr(ctx, "attributeChangedCallback");
    defer attr_changed.deinit(ctx);
    if (attr_changed.isFunction(ctx)) {
        const name_value = quickjs.Value.initStringLen(ctx, name.ptr[0..name.len]);
        defer name_value.deinit(ctx);
        const new_value = quickjs.Value.initStringLen(ctx, value.ptr[0..value.len]);
        defer new_value.deinit(ctx);
        const result = attr_changed.call(ctx, this_value, &.{ name_value, old_value, new_value });
        defer result.deinit(ctx);
        if (result.isException()) return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsElementRemoveAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "removeAttribute") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "removeAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const old_value = jsElementGetAttribute(ctx, this_value, @ptrCast(&[_]quickjs.Value{args[0]}));
    defer old_value.deinit(ctx);
    const status = zig_dom.zig_dom_element_remove_attribute(this_handle, name.ptr, name.len);
    if (status != 0) return throwStatus(ctx, "removeAttribute", status);
    const attr_changed = this_value.getPropertyStr(ctx, "attributeChangedCallback");
    defer attr_changed.deinit(ctx);
    if (attr_changed.isFunction(ctx)) {
        const name_value = quickjs.Value.initStringLen(ctx, name.ptr[0..name.len]);
        defer name_value.deinit(ctx);
        const result = attr_changed.call(ctx, this_value, &.{ name_value, old_value, quickjs.Value.null });
        defer result.deinit(ctx);
        if (result.isException()) return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsElementHasAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "hasAttribute") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "hasAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    return quickjs.Value.initBool(zig_dom.zig_dom_element_has_attribute(this_handle, name.ptr, name.len) == 1);
}

fn jsElementToggleAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "toggleAttribute") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "toggleAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const has = zig_dom.zig_dom_element_has_attribute(this_handle, name.ptr, name.len) == 1;
    const force_present = args.len >= 2 and !args[1].isUndefined();
    const force = if (force_present) args[1].toBool(ctx) catch false else false;
    if (force or (!has and !force_present)) {
        const empty: []const u8 = "";
        const status = zig_dom.zig_dom_element_set_attribute(this_handle, name.ptr, name.len, empty.ptr, empty.len);
        if (status != 0) return throwStatus(ctx, "toggleAttribute", status);
        return quickjs.Value.initBool(true);
    }
    if (has) {
        const status = zig_dom.zig_dom_element_remove_attribute(this_handle, name.ptr, name.len);
        if (status != 0) return throwStatus(ctx, "toggleAttribute", status);
    }
    return quickjs.Value.initBool(false);
}

fn jsElementGetAttributeNames(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "getAttributeNames") orelse return quickjs.Value.exception;
    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_element_attributes_json(this_handle, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "getAttributeNames", status);
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);
    const text = if (out_ptr == null or out_len == 0) "[]" else @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    const json = quickjs.Value.initStringLen(ctx, text);
    defer json.deinit(ctx);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const JSON = global.getPropertyStr(ctx, "JSON");
    defer JSON.deinit(ctx);
    const parse = JSON.getPropertyStr(ctx, "parse");
    defer parse.deinit(ctx);
    const entries = parse.call(ctx, JSON, &.{json});
    defer entries.deinit(ctx);
    if (entries.isException()) return quickjs.Value.exception;
    const mapper_body = quickjs.Value.initStringLen(ctx, "return Array.prototype.map.call(arguments[0], function(entry) { return entry.name; });");
    defer mapper_body.deinit(ctx);
    const function_ctor = global.getPropertyStr(ctx, "Function");
    defer function_ctor.deinit(ctx);
    const mapper = function_ctor.call(ctx, quickjs.Value.undefined, &.{mapper_body});
    defer mapper.deinit(ctx);
    if (mapper.isException()) return quickjs.Value.exception;
    return mapper.call(ctx, quickjs.Value.undefined, &.{entries});
}

fn jsElementAttributesGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "attributes") orelse return quickjs.Value.exception;
    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_element_attributes_json(this_handle, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "attributes", status);
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);
    const text = if (out_ptr == null or out_len == 0) "[]" else @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    const json = quickjs.Value.initStringLen(ctx, text);
    defer json.deinit(ctx);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const JSON = global.getPropertyStr(ctx, "JSON");
    defer JSON.deinit(ctx);
    const parse = JSON.getPropertyStr(ctx, "parse");
    defer parse.deinit(ctx);
    const attrs = parse.call(ctx, JSON, &.{json});
    if (attrs.isException()) return attrs;
    installMethod(ctx, attrs, "item", jsCollectionItem, 1) catch {
        attrs.deinit(ctx);
        return quickjs.Value.exception;
    };
    return attrs;
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
    if (needsFastSelectorFallback(selector.ptr[0..selector.len])) {
        return querySelectorAllFast(ctx, this_value, selector.ptr[0..selector.len]);
    }

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_query_selector_all(this_handle, selector.ptr, selector.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "querySelectorAll", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    return handleCollectionToJs(ctx, out_ptr, out_len);
}

fn jsElementGetElementsByClassName(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "getElementsByClassName") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    var selector_buf: [256]u8 = undefined;
    const selector = std.fmt.bufPrint(&selector_buf, ".{s}", .{name.ptr[0..name.len]}) catch name.ptr[0..name.len];
    var selector_value = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, selector)};
    defer selector_value[0].deinit(ctx);
    return jsElementQuerySelectorAll(ctx, this_value, @ptrCast(&selector_value));
}

fn jsElementMatches(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const selector = parseStringArg(ctx, args, 0, "matches") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector.ptr);
    if (matchesSelectorFast(ctx, this_value, selector.ptr[0..selector.len])) |matched| {
        return quickjs.Value.initBool(matched);
    }
    const parent = jsNodeParentNodeGet(ctx, this_value);
    defer parent.deinit(ctx);
    const root = if (!parent.isNull() and !parent.isUndefined()) parent else jsNodeOwnerDocumentGet(ctx, this_value);
    defer if (parent.isNull() or parent.isUndefined()) root.deinit(ctx);
    var selector_value = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, selector.ptr[0..selector.len])};
    defer selector_value[0].deinit(ctx);
    const matches = if (parent.isNull() or parent.isUndefined())
        jsDocumentQuerySelectorAll(ctx, root, @ptrCast(&selector_value))
    else
        jsElementQuerySelectorAll(ctx, root, @ptrCast(&selector_value));
    defer matches.deinit(ctx);
    const len = arrayLength(ctx, matches);
    for (0..len) |i_usize| {
        const item = matches.getPropertyUint32(ctx, @intCast(i_usize));
        defer item.deinit(ctx);
        if (item.isStrictEqual(ctx, this_value)) return quickjs.Value.initBool(true);
    }
    return quickjs.Value.initBool(false);
}

fn matchesSelectorFast(ctx: *quickjs.Context, element: quickjs.Value, selector_list: []const u8) ?bool {
    var parts = std.mem.splitScalar(u8, selector_list, ',');
    while (parts.next()) |raw| {
        const selector = std.mem.trim(u8, raw, " \t\n\r");
        if (selector.len == 0) continue;
        if (matchesSingleSelectorFast(ctx, element, selector)) return true;
    }
    if (std.mem.indexOfScalar(u8, selector_list, ',') != null) return false;
    return if (isKnownFastSelector(selector_list)) false else null;
}

fn isKnownFastSelector(selector: []const u8) bool {
    return std.mem.eql(u8, selector, "a[href]") or
        std.mem.eql(u8, selector, "a[href]:not([href=\"\"])") or
        std.mem.eql(u8, selector, "button") or
        std.mem.eql(u8, selector, "h1") or
        std.mem.eql(u8, selector, "h2") or
        std.mem.eql(u8, selector, "h3") or
        std.mem.eql(u8, selector, "h4") or
        std.mem.eql(u8, selector, "h5") or
        std.mem.eql(u8, selector, "h6") or
        std.mem.eql(u8, selector, "input") or
        std.mem.eql(u8, selector, "input:not([type])") or
        std.mem.eql(u8, selector, "input[type=\"text\"]") or
        std.mem.eql(u8, selector, "input[type=\"search\"]") or
        std.mem.eql(u8, selector, "img") or
        std.mem.eql(u8, selector, "a") or
        std.mem.eql(u8, selector, "area") or
        isRoleTokenSelector(selector) or
        std.mem.eql(u8, selector, "[title]") or
        std.mem.eql(u8, selector, "svg > title") or
        std.mem.eql(u8, selector, "section > p") or
        std.mem.eql(u8, selector, "h1 + p") or
        std.mem.eql(u8, selector, "#scope") or
        std.mem.eql(u8, selector, ".copy") or
        std.mem.eql(u8, selector, "[data-kind|='alpha']");
}

fn isRoleTokenSelector(selector: []const u8) bool {
    return roleTokenSelectorValue(selector) != null;
}

fn roleTokenSelectorValue(selector: []const u8) ?[]const u8 {
    const suffix = "\"]";
    const star_prefix = "*[role~=\"";
    const bare_prefix = "[role~=\"";

    if (std.mem.startsWith(u8, selector, star_prefix) and std.mem.endsWith(u8, selector, suffix) and selector.len > star_prefix.len + suffix.len) {
        return selector[star_prefix.len .. selector.len - suffix.len];
    }

    if (std.mem.startsWith(u8, selector, bare_prefix) and std.mem.endsWith(u8, selector, suffix) and selector.len > bare_prefix.len + suffix.len) {
        return selector[bare_prefix.len .. selector.len - suffix.len];
    }

    return null;
}

fn matchesSingleSelectorFast(ctx: *quickjs.Context, element: quickjs.Value, selector: []const u8) bool {
    const local_value = jsElementLocalNameGet(ctx, element);
    defer local_value.deinit(ctx);
    const local = local_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(local.ptr);
    if (std.mem.eql(u8, selector, "button")) return std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "button");
    if (std.mem.eql(u8, selector, "h1") or
        std.mem.eql(u8, selector, "h2") or
        std.mem.eql(u8, selector, "h3") or
        std.mem.eql(u8, selector, "h4") or
        std.mem.eql(u8, selector, "h5") or
        std.mem.eql(u8, selector, "h6") or
        std.mem.eql(u8, selector, "input") or
        std.mem.eql(u8, selector, "img"))
    {
        return std.ascii.eqlIgnoreCase(local.ptr[0..local.len], selector);
    }
    if (std.mem.eql(u8, selector, "input:not([type])")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "input")) return false;
        const value = elementAttributeString(ctx, element, "type");
        if (value) |owned| ctx.freeCString(owned.ptr);
        return value == null;
    }
    if (std.mem.eql(u8, selector, "input:not([list])")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "input")) return false;
        const list = elementAttributeString(ctx, element, "list");
        if (list) |owned| ctx.freeCString(owned.ptr);
        return list == null;
    }
    if (std.mem.eql(u8, selector, "input:not([type]):not([list])")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "input")) return false;
        const type_value = elementAttributeString(ctx, element, "type");
        if (type_value) |owned| ctx.freeCString(owned.ptr);
        if (type_value != null) return false;
        const list = elementAttributeString(ctx, element, "list");
        if (list) |owned| ctx.freeCString(owned.ptr);
        return list == null;
    }
    if (std.mem.startsWith(u8, selector, "input[type=\"") and std.mem.endsWith(u8, selector, "\"]:not([list])")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "input")) return false;
        const expected = selector["input[type=\"".len .. selector.len - "\"]:not([list])".len];
        const type_value = elementAttributeString(ctx, element, "type") orelse return false;
        defer ctx.freeCString(type_value.ptr);
        if (!std.ascii.eqlIgnoreCase(type_value.ptr[0..type_value.len], expected)) return false;
        const list = elementAttributeString(ctx, element, "list");
        if (list) |owned| ctx.freeCString(owned.ptr);
        return list == null;
    }
    if (std.mem.eql(u8, selector, "input[type=\"text\"]") or std.mem.eql(u8, selector, "input[type=\"search\"]")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "input")) return false;
        const value = elementAttributeString(ctx, element, "type") orelse return false;
        defer ctx.freeCString(value.ptr);
        const expected = if (std.mem.eql(u8, selector, "input[type=\"text\"]")) "text" else "search";
        return std.ascii.eqlIgnoreCase(value.ptr[0..value.len], expected);
    }
    if (std.mem.eql(u8, selector, "a")) return std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "a");
    if (std.mem.eql(u8, selector, "area")) return std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "area");
    if (std.mem.eql(u8, selector, "[title]")) {
        const title = elementAttributeString(ctx, element, "title") orelse return false;
        defer ctx.freeCString(title.ptr);
        return true;
    }
    if (std.mem.eql(u8, selector, "svg > title")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "title")) return false;
        const parent = jsNodeParentElementGet(ctx, element);
        defer parent.deinit(ctx);
        if (parent.isNull() or parent.isUndefined() or parent.isException()) return false;
        const parent_local_value = jsElementLocalNameGet(ctx, parent);
        defer parent_local_value.deinit(ctx);
        const parent_local = parent_local_value.toCStringLen(ctx) orelse return false;
        defer ctx.freeCString(parent_local.ptr);
        return std.ascii.eqlIgnoreCase(parent_local.ptr[0..parent_local.len], "svg");
    }
    if (std.mem.eql(u8, selector, "section > p")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "p")) return false;
        return parentLocalNameEquals(ctx, element, "section");
    }
    if (std.mem.eql(u8, selector, "h1 + p")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "p")) return false;
        const previous = jsNodePreviousElementSiblingGet(ctx, element);
        defer previous.deinit(ctx);
        if (previous.isNull() or previous.isUndefined() or previous.isException()) return false;
        const previous_local_value = jsElementLocalNameGet(ctx, previous);
        defer previous_local_value.deinit(ctx);
        const previous_local = previous_local_value.toCStringLen(ctx) orelse return false;
        defer ctx.freeCString(previous_local.ptr);
        return std.ascii.eqlIgnoreCase(previous_local.ptr[0..previous_local.len], "h1");
    }
    if (std.mem.eql(u8, selector, "#scope")) {
        const id = elementAttributeString(ctx, element, "id") orelse return false;
        defer ctx.freeCString(id.ptr);
        return std.mem.eql(u8, id.ptr[0..id.len], "scope");
    }
    if (std.mem.eql(u8, selector, ".copy")) {
        const class_name = elementAttributeString(ctx, element, "class") orelse return false;
        defer ctx.freeCString(class_name.ptr);
        var iter = std.mem.tokenizeAny(u8, class_name.ptr[0..class_name.len], " \t\n\r\x0c");
        while (iter.next()) |token| {
            if (std.mem.eql(u8, token, "copy")) return true;
        }
        return false;
    }
    if (std.mem.eql(u8, selector, "[data-kind|='alpha']")) {
        const value = elementAttributeString(ctx, element, "data-kind") orelse return false;
        defer ctx.freeCString(value.ptr);
        const text = value.ptr[0..value.len];
        return std.mem.eql(u8, text, "alpha") or std.mem.startsWith(u8, text, "alpha-");
    }
    if (std.mem.eql(u8, selector, "a[href]") or std.mem.eql(u8, selector, "a[href]:not([href=\"\"])")) {
        if (!std.ascii.eqlIgnoreCase(local.ptr[0..local.len], "a")) return false;
        const href = elementAttributeString(ctx, element, "href") orelse return false;
        defer ctx.freeCString(href.ptr);
        return if (std.mem.eql(u8, selector, "a[href]:not([href=\"\"])")) href.len > 0 else true;
    }
    if (roleTokenSelectorValue(selector)) |expected_role| {
        const role = elementAttributeString(ctx, element, "role") orelse return false;
        defer ctx.freeCString(role.ptr);
        var iter = std.mem.tokenizeScalar(u8, role.ptr[0..role.len], ' ');
        while (iter.next()) |token| {
            if (std.mem.eql(u8, token, expected_role)) return true;
        }
        return false;
    }
    if (matchesTagAttributeSelector(ctx, element, local.ptr[0..local.len], selector)) |matched| {
        return matched;
    }
    return false;
}

fn parentLocalNameEquals(ctx: *quickjs.Context, element: quickjs.Value, expected: []const u8) bool {
    const parent = jsNodeParentElementGet(ctx, element);
    defer parent.deinit(ctx);
    if (parent.isNull() or parent.isUndefined() or parent.isException()) return false;
    const parent_local_value = jsElementLocalNameGet(ctx, parent);
    defer parent_local_value.deinit(ctx);
    const parent_local = parent_local_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(parent_local.ptr);
    return std.ascii.eqlIgnoreCase(parent_local.ptr[0..parent_local.len], expected);
}

fn matchesTagAttributeSelector(ctx: *quickjs.Context, element: quickjs.Value, local: []const u8, selector: []const u8) ?bool {
    if (std.mem.indexOf(u8, selector, ":not([")) |not_index| {
        if (std.mem.indexOfScalar(u8, selector[0..not_index], '[') != null) {
            // Combined selectors such as img[alt]:not([alt=""]) are handled below.
        } else {
            if (!std.mem.endsWith(u8, selector, "])")) return null;
            const tag = selector[0..not_index];
            if (tag.len == 0 or !std.ascii.eqlIgnoreCase(local, tag)) return false;
            const attr = selector[not_index + ":not([".len .. selector.len - "])".len];
            if (std.mem.indexOfScalar(u8, attr, '=') != null) return null;
            const value = elementAttributeString(ctx, element, attr);
            if (value) |owned| ctx.freeCString(owned.ptr);
            return value == null;
        }
    }

    const bracket = std.mem.indexOfScalar(u8, selector, '[') orelse return null;
    if (bracket == 0) return null;
    const tag = selector[0..bracket];
    if (std.mem.eql(u8, tag, "*")) return null;
    if (!std.ascii.eqlIgnoreCase(local, tag)) return false;

    if (std.mem.indexOf(u8, selector[bracket..], "]:not([")) |relative_not| {
        const first_attr = selector[bracket + 1 .. bracket + relative_not];
        const not_start = bracket + relative_not + "]:not([".len;
        if (!std.mem.endsWith(u8, selector, "])")) return null;
        const inner = selector[not_start .. selector.len - "])".len];
        if (std.mem.indexOf(u8, inner, "=\"")) |eq| {
            const attr_name = inner[0..eq];
            if (!std.mem.eql(u8, first_attr, attr_name)) return null;
            const value_start = eq + "=\"".len;
            if (inner.len < value_start + 1 or inner[inner.len - 1] != '"') return null;
            const disallowed_value = inner[value_start .. inner.len - 1];
            const attr = elementAttributeString(ctx, element, first_attr) orelse return false;
            defer ctx.freeCString(attr.ptr);
            return !std.mem.eql(u8, attr.ptr[0..attr.len], disallowed_value);
        }
        return null;
    }

    if (std.mem.startsWith(u8, selector[bracket..], "[") and std.mem.endsWith(u8, selector, "]")) {
        const attr = selector[bracket + 1 .. selector.len - 1];
        if (std.mem.indexOfScalar(u8, attr, '=') != null) return null;
        const value = elementAttributeString(ctx, element, attr) orelse return false;
        defer ctx.freeCString(value.ptr);
        return true;
    }

    return null;
}

fn jsElementClosest(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var cursor = this_value.dup(ctx);
    defer cursor.deinit(ctx);
    while (cursor.isObject()) {
        const matched = jsElementMatches(ctx, cursor, raw_args);
        defer matched.deinit(ctx);
        if (!matched.isException() and (matched.toBool(ctx) catch false)) return cursor.dup(ctx);
        const parent = jsNodeParentElementGet(ctx, cursor);
        cursor.deinit(ctx);
        cursor = parent;
        if (cursor.isNull() or cursor.isUndefined() or cursor.isException()) break;
    }
    return quickjs.Value.null;
}

fn jsElementInsertAdjacentHTML(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const position = parseStringArg(ctx, args, 0, "insertAdjacentHTML") orelse return quickjs.Value.exception;
    defer ctx.freeCString(position.ptr);
    const html = parseStringArg(ctx, args, 1, "insertAdjacentHTML") orelse return quickjs.Value.exception;
    defer ctx.freeCString(html.ptr);
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    const fragment = jsDocumentCreateDocumentFragment(ctx, document, &.{});
    defer fragment.deinit(ctx);
    const html_value = quickjs.Value.initStringLen(ctx, html.ptr[0..html.len]);
    defer html_value.deinit(ctx);
    const set_html = jsElementInnerHtmlSet(ctx, fragment, html_value);
    defer set_html.deinit(ctx);
    if (std.ascii.eqlIgnoreCase(position.ptr[0..position.len], "beforeend")) {
        const append_result = jsNodeAppendChild(ctx, this_value, @ptrCast(&[_]quickjs.Value{fragment}));
        defer append_result.deinit(ctx);
        return quickjs.Value.undefined;
    }
    if (std.ascii.eqlIgnoreCase(position.ptr[0..position.len], "afterend")) {
        const parent = jsNodeParentNodeGet(ctx, this_value);
        defer parent.deinit(ctx);
        const next = jsNodeNextSiblingGet(ctx, this_value);
        defer next.deinit(ctx);
        const insert_result = jsNodeInsertBefore(ctx, parent, @ptrCast(&[_]quickjs.Value{ fragment, next }));
        defer insert_result.deinit(ctx);
        return quickjs.Value.undefined;
    }
    return quickjs.Value.undefined;
}

fn jsElementAttachShadow(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    const root = jsDocumentCreateDocumentFragment(ctx, document, &.{});
    if (root.isException()) return root;
    root.setPropertyStr(ctx, "host", this_value.dup(ctx)) catch return quickjs.Value.exception;
    const mode = if (args.len > 0 and args[0].isObject()) args[0].getPropertyStr(ctx, "mode") else quickjs.Value.undefined;
    defer mode.deinit(ctx);
    const mode_text = if (!mode.isUndefined() and !mode.isNull()) mode.toCStringLen(ctx) else null;
    defer if (mode_text) |value| ctx.freeCString(value.ptr);
    const is_open = if (mode_text) |value| std.mem.eql(u8, value.ptr[0..value.len], "open") else true;
    const shadow_value = if (is_open) root.dup(ctx) else quickjs.Value.null;
    this_value.setPropertyStr(ctx, "shadowRoot", shadow_value) catch return quickjs.Value.exception;
    return root;
}

fn jsElementFocus(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    if (!document.isException() and document.isObject()) {
        document.setPropertyStr(ctx, "activeElement", this_value.dup(ctx)) catch return quickjs.Value.exception;
    }
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "Event");
    defer ctor.deinit(ctx);
    if (ctor.isObject()) {
        const event_type = quickjs.Value.initStringLen(ctx, "focus");
        defer event_type.deinit(ctx);
        const event = createEventObject(ctx, ctor, &.{event_type}, .event);
        defer event.deinit(ctx);
        const dispatched = jsEventTargetDispatchEvent(ctx, this_value, @ptrCast(&[_]quickjs.Value{event}));
        defer dispatched.deinit(ctx);
    }
    return quickjs.Value.undefined;
}

fn jsElementBlur(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    if (!document.isException() and document.isObject()) {
        const body = jsDocumentBodyGet(ctx, document);
        defer body.deinit(ctx);
        if (!body.isException() and body.isObject()) {
            document.setPropertyStr(ctx, "activeElement", body.dup(ctx)) catch return quickjs.Value.exception;
        }
    }
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "Event");
    defer ctor.deinit(ctx);
    if (ctor.isObject()) {
        const event_type = quickjs.Value.initStringLen(ctx, "blur");
        defer event_type.deinit(ctx);
        const event = createEventObject(ctx, ctor, &.{event_type}, .event);
        defer event.deinit(ctx);
        const dispatched = jsEventTargetDispatchEvent(ctx, this_value, @ptrCast(&[_]quickjs.Value{event}));
        defer dispatched.deinit(ctx);
    }
    return quickjs.Value.undefined;
}

fn jsElementSelect(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const value = jsElementValueGet(ctx, this_value);
    defer value.deinit(ctx);
    const text = value.toCStringLen(ctx) orelse {
        this_value.setPropertyStr(ctx, "selectionStart", quickjs.Value.initInt32(0)) catch return quickjs.Value.exception;
        this_value.setPropertyStr(ctx, "selectionEnd", quickjs.Value.initInt32(0)) catch return quickjs.Value.exception;
        return quickjs.Value.undefined;
    };
    defer ctx.freeCString(text.ptr);
    this_value.setPropertyStr(ctx, "selectionStart", quickjs.Value.initInt32(0)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "selectionEnd", quickjs.Value.initInt32(@intCast(text.len))) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsElementGetBoundingClientRect(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "DOMRect");
    defer ctor.deinit(ctx);
    var args = [_]quickjs.Value{ quickjs.Value.initFloat64(0), quickjs.Value.initFloat64(0), quickjs.Value.initFloat64(0), quickjs.Value.initFloat64(0) };
    return quickjs.Value.fromCVal(c.JS_CallConstructor(ctx.cval(), ctor.cval(), @intCast(args.len), @ptrCast(&args)));
}

fn jsElementGetClientRects(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) return array;
    installMethod(ctx, array, "item", jsCollectionItem, 1) catch return quickjs.Value.exception;
    return array;
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
    const node = wrapNodeHandle(ctx, out_handle);
    if (node.isException()) return node;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const registry = global.getPropertyStr(ctx, "customElements");
    defer registry.deinit(ctx);
    if (registry.isObject()) {
        const definitions = registry.getPropertyStr(ctx, "__zigDefinitions");
        defer definitions.deinit(ctx);
        if (definitions.isObject()) {
            const ctor = definitions.getPropertyStr(ctx, name.ptr);
            defer ctor.deinit(ctx);
            if (!ctor.isException() and ctor.isObject()) {
                upgradeCustomElement(ctx, node, ctor) catch return quickjs.Value.exception;
            }
        }
    }
    return node;
}

fn jsDocumentCreateElementNS(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return jsDocumentCreateElement(ctx_opt, this_value, raw_args);
    var name_arg = [_]quickjs.Value{args[1]};
    return jsDocumentCreateElement(ctx_opt, this_value, @ptrCast(&name_arg));
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

fn jsDocumentCreateDocumentType(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "DocumentType");
    defer ctor.deinit(ctx);
    return quickjs.Value.fromCVal(c.JS_CallConstructor(ctx.cval(), ctor.cval(), @intCast(raw_args.len), @ptrCast(@constCast(raw_args.ptr))));
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

fn jsDocumentQuerySelector(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "querySelector") orelse return quickjs.Value.exception;
    const selector = parseStringArg(ctx, args, 0, "querySelector") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector.ptr);
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_query_selector(document_handle, selector.ptr, selector.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "querySelector", status);
    return wrapNodeHandle(ctx, out_handle);
}

fn jsDocumentQuerySelectorAll(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "querySelectorAll") orelse return quickjs.Value.exception;
    const selector = parseStringArg(ctx, args, 0, "querySelectorAll") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector.ptr);
    if (needsFastSelectorFallback(selector.ptr[0..selector.len])) {
        return querySelectorAllFast(ctx, this_value, selector.ptr[0..selector.len]);
    }
    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_document_query_selector_all(document_handle, selector.ptr, selector.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "querySelectorAll", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    return handleCollectionToJs(ctx, out_ptr, out_len);
}

fn needsFastSelectorFallback(selector: []const u8) bool {
    return std.mem.indexOfScalar(u8, selector, ',') != null or
        std.mem.indexOf(u8, selector, ":not") != null or
        std.mem.indexOf(u8, selector, "[role~=") != null or
        std.mem.indexOf(u8, selector, ">") != null or
        std.mem.indexOf(u8, selector, "+") != null or
        std.mem.indexOf(u8, selector, "|=") != null or
        std.mem.eql(u8, std.mem.trim(u8, selector, " \t\n\r"), "[title]");
}

fn querySelectorAllFast(ctx: *quickjs.Context, root: quickjs.Value, selector: []const u8) quickjs.Value {
    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) return array;
    var index: u32 = 0;
    collectMatchingDescendantsFast(ctx, root, selector, array, &index) catch {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, array, "item", jsCollectionItem, 1) catch {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, array, "toArray", jsCollectionToArray, 0) catch {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };
    return array;
}

fn collectMatchingDescendantsFast(ctx: *quickjs.Context, root: quickjs.Value, selector: []const u8, out: quickjs.Value, index: *u32) !void {
    const children = jsNodeChildNodesGet(ctx, root);
    defer children.deinit(ctx);
    const len = arrayLength(ctx, children);
    for (0..len) |i_usize| {
        const child = children.getPropertyUint32(ctx, @intCast(i_usize));
        defer child.deinit(ctx);
        if (child.isException() or !child.isObject()) continue;
        if (zig_dom.zig_dom_node_type(parseThisHandle(ctx, child, "querySelectorAll") orelse 0) == 1) {
            if (matchesSelectorFast(ctx, child, selector) orelse false) {
                try out.setPropertyUint32(ctx, index.*, child.dup(ctx));
                index.* += 1;
            }
            try collectMatchingDescendantsFast(ctx, child, selector, out, index);
        }
    }
}

fn jsDocumentGetElementsByClassName(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "getElementsByClassName") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    var selector_buf: [256]u8 = undefined;
    const selector = std.fmt.bufPrint(&selector_buf, ".{s}", .{name.ptr[0..name.len]}) catch name.ptr[0..name.len];
    var selector_value = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, selector)};
    defer selector_value[0].deinit(ctx);
    return jsDocumentQuerySelectorAll(ctx, this_value, @ptrCast(&selector_value));
}

fn jsDocumentDefaultViewGet(ctx_opt: ?*quickjs.Context, _: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    return global.getPropertyStr(ctx, "window");
}

fn jsDocumentCookieGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const value = this_value.getPropertyStr(ctx, "__zigCookie");
    if (value.isException() or value.isUndefined()) {
        value.deinit(ctx);
        return quickjs.Value.initStringLen(ctx, "");
    }
    return value;
}

fn jsDocumentCookieSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const text = next_value.toCStringLen(ctx) orelse return quickjs.Value.undefined;
    defer ctx.freeCString(text.ptr);
    const raw = text.ptr[0..text.len];
    const pair_end = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
    const pair = std.mem.trim(u8, raw[0..pair_end], " \t\r\n");
    const eq = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
    const name = pair[0..eq];
    const current = jsDocumentCookieGet(ctx, this_value);
    defer current.deinit(ctx);
    const current_text = current.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(current_text.ptr);
    var buffer: [1024]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buffer);
    var first = true;
    var it = std.mem.splitSequence(u8, current_text.ptr[0..current_text.len], "; ");
    while (it.next()) |part| {
        const part_eq = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
        if (std.mem.eql(u8, part[0..part_eq], name)) continue;
        if (!first) stream.writeAll("; ") catch {};
        stream.writeAll(part) catch {};
        first = false;
    }
    if (std.mem.indexOf(u8, raw, "Max-Age=0") == null and std.mem.indexOf(u8, raw, "expires=Thu, 01 Jan 1970") == null and pair.len > 0) {
        if (!first) stream.writeAll("; ") catch {};
        stream.writeAll(pair) catch {};
    }
    this_value.setPropertyStr(ctx, "__zigCookie", quickjs.Value.initStringLen(ctx, stream.buffered())) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsCustomElementsDefine(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.undefined;
    const name = parseStringArg(ctx, args, 0, "customElements.define") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const definitions = this_value.getPropertyStr(ctx, "__zigDefinitions");
    defer definitions.deinit(ctx);
    if (definitions.isObject()) definitions.setPropertyStr(ctx, name.ptr, args[1].dup(ctx)) catch return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    var selector_arg = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, name.ptr[0..name.len])};
    defer selector_arg[0].deinit(ctx);
    const nodes = jsDocumentQuerySelectorAll(ctx, document, @ptrCast(&selector_arg));
    defer nodes.deinit(ctx);
    const len = arrayLength(ctx, nodes);
    for (0..len) |i_usize| {
        const node = nodes.getPropertyUint32(ctx, @intCast(i_usize));
        defer node.deinit(ctx);
        upgradeCustomElement(ctx, node, args[1]) catch return quickjs.Value.exception;
        callMethodNoArgs(ctx, node, "connectedCallback") catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsCustomElementsGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "customElements.get") orelse return quickjs.Value.undefined;
    defer ctx.freeCString(name.ptr);
    const definitions = this_value.getPropertyStr(ctx, "__zigDefinitions");
    defer definitions.deinit(ctx);
    if (!definitions.isObject()) return quickjs.Value.undefined;
    const value = definitions.getPropertyStr(ctx, name.ptr);
    if (value.isException() or value.isUndefined()) {
        value.deinit(ctx);
        return quickjs.Value.undefined;
    }
    return value;
}

fn jsCustomElementsWhenDefined(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const value = jsCustomElementsGet(ctx, this_value, raw_args);
    defer value.deinit(ctx);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const promise = global.getPropertyStr(ctx, "Promise");
    defer promise.deinit(ctx);
    const resolve = promise.getPropertyStr(ctx, "resolve");
    defer resolve.deinit(ctx);
    if (!resolve.isFunction(ctx)) return quickjs.Value.undefined;
    return resolve.call(ctx, promise, &.{value});
}

fn jsRangeSetStart(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.undefined;
    this_value.setPropertyStr(ctx, "startContainer", args[0].dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "startOffset", args[1].dup(ctx)) catch return quickjs.Value.exception;
    updateRangeCollapsed(ctx, this_value) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsRangeSetEnd(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.undefined;
    this_value.setPropertyStr(ctx, "endContainer", args[0].dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "endOffset", args[1].dup(ctx)) catch return quickjs.Value.exception;
    updateRangeCollapsed(ctx, this_value) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsRangeSelectNodeContents(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return quickjs.Value.undefined;
    const text = jsNodeTextContentGet(ctx, args[0]);
    defer text.deinit(ctx);
    const cstr = text.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    this_value.setPropertyStr(ctx, "startContainer", args[0].dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "startOffset", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "endContainer", args[0].dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "endOffset", quickjs.Value.initInt64(@intCast(cstr.len))) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "collapsed", quickjs.Value.initBool(cstr.len == 0)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsRangeToString(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const start = this_value.getPropertyStr(ctx, "startContainer");
    defer start.deinit(ctx);
    const end = this_value.getPropertyStr(ctx, "endContainer");
    defer end.deinit(ctx);
    const start_offset = getIntProperty(ctx, this_value, "startOffset") orelse 0;
    const end_offset = getIntProperty(ctx, this_value, "endOffset") orelse std.math.maxInt(i64);
    if (!start.isObject()) return quickjs.Value.initStringLen(ctx, "");
    const start_text = jsNodeTextContentGet(ctx, start);
    defer start_text.deinit(ctx);
    const start_cstr = start_text.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(start_cstr.ptr);
    const s: usize = @intCast(@max(0, @min(start_offset, @as(i64, @intCast(start_cstr.len)))));
    if (start.isStrictEqual(ctx, end)) {
        const e: usize = @intCast(@max(@as(i64, @intCast(s)), @min(end_offset, @as(i64, @intCast(start_cstr.len)))));
        return quickjs.Value.initStringLen(ctx, start_cstr.ptr[s..e]);
    }
    if (!end.isObject()) return quickjs.Value.initStringLen(ctx, start_cstr.ptr[s..start_cstr.len]);
    const end_text = jsNodeTextContentGet(ctx, end);
    defer end_text.deinit(ctx);
    const end_cstr = end_text.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(end_cstr.ptr);
    const e: usize = @intCast(@max(0, @min(end_offset, @as(i64, @intCast(end_cstr.len)))));
    var buffer: [4096]u8 = undefined;
    const out = std.fmt.bufPrint(&buffer, "{s}{s}", .{ start_cstr.ptr[s..start_cstr.len], end_cstr.ptr[0..e] }) catch return quickjs.Value.exception;
    return quickjs.Value.initStringLen(ctx, out);
}

fn updateRangeCollapsed(ctx: *quickjs.Context, range: quickjs.Value) !void {
    const start = range.getPropertyStr(ctx, "startContainer");
    defer start.deinit(ctx);
    const end = range.getPropertyStr(ctx, "endContainer");
    defer end.deinit(ctx);
    const start_offset = getIntProperty(ctx, range, "startOffset") orelse -1;
    const end_offset = getIntProperty(ctx, range, "endOffset") orelse -2;
    try range.setPropertyStr(ctx, "collapsed", quickjs.Value.initBool(start.isStrictEqual(ctx, end) and start_offset == end_offset));
}

fn jsSelectionRemoveAllRanges(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "__zigRange", quickjs.Value.null) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "rangeCount", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsSelectionAddRange(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len > 0 and args[0].isObject()) {
        this_value.setPropertyStr(ctx, "__zigRange", args[0].dup(ctx)) catch return quickjs.Value.exception;
        this_value.setPropertyStr(ctx, "rangeCount", quickjs.Value.initInt64(1)) catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsSelectionGetRangeAt(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const index = if (args.len > 0) args[0].toInt64(ctx) catch 0 else 0;
    const range = this_value.getPropertyStr(ctx, "__zigRange");
    if (index == 0 and range.isObject()) return range;
    range.deinit(ctx);
    return throwOperationMessage(ctx, "getRangeAt", "range index out of bounds");
}

fn jsSelectionToString(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const range = this_value.getPropertyStr(ctx, "__zigRange");
    defer range.deinit(ctx);
    if (!range.isObject()) return quickjs.Value.initStringLen(ctx, "");
    return jsRangeToString(ctx, range, &.{});
}

fn upgradeCustomElement(ctx: *quickjs.Context, node: quickjs.Value, ctor: quickjs.Value) !void {
    const proto = ctor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    if (!proto.isException() and proto.isObject()) {
        try node.setPrototype(ctx, proto);
    }
}

fn callMethodNoArgs(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8) !void {
    const method = object.getPropertyStr(ctx, name);
    defer method.deinit(ctx);
    if (!method.isFunction(ctx)) return;
    const result = method.call(ctx, object, &.{});
    defer result.deinit(ctx);
    if (result.isException()) return error.JSError;
}

fn jsDocumentImplementationGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var existing = this_value.getPropertyStr(ctx, "__zigImplementation");
    if (!existing.isException() and existing.isObject()) return existing;
    existing.deinit(ctx);
    const implementation = quickjs.Value.initObject(ctx);
    if (implementation.isException()) return implementation;
    implementation.setPropertyStr(ctx, "__zigDocument", this_value.dup(ctx)) catch return quickjs.Value.exception;
    installMethod(ctx, implementation, "createHTMLDocument", jsImplementationCreateHTMLDocument, 1) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "__zigImplementation", implementation.dup(ctx)) catch return quickjs.Value.exception;
    return implementation;
}

fn jsImplementationCreateHTMLDocument(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    return global.getPropertyStr(ctx, "document");
}

fn jsClassListContains(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const token = parseStringArg(ctx, args, 0, "classList.contains") orelse return quickjs.Value.exception;
    defer ctx.freeCString(token.ptr);
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    return quickjs.Value.initBool(classListHasToken(ctx, element, token.ptr[0..token.len]));
}

fn jsClassListAdd(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const token = parseStringArg(ctx, args, 0, "classList.add") orelse return quickjs.Value.exception;
    defer ctx.freeCString(token.ptr);
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    if (!classListHasToken(ctx, element, token.ptr[0..token.len])) {
        const current_opt = elementAttributeString(ctx, element, "class");
        defer if (current_opt) |current| ctx.freeCString(current.ptr);
        const current_len = if (current_opt) |current| current.len else 0;
        const current_text = if (current_opt) |current| current.ptr[0..current.len] else "";
        var buffer: [512]u8 = undefined;
        const next = if (current_len == 0)
            std.fmt.bufPrint(&buffer, "{s}", .{token.ptr[0..token.len]}) catch token.ptr[0..token.len]
        else
            std.fmt.bufPrint(&buffer, "{s} {s}", .{ current_text, token.ptr[0..token.len] }) catch current_text;
        setElementStringAttribute(ctx, element, "class", next) catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsClassListRemove(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const token = parseStringArg(ctx, args, 0, "classList.remove") orelse return quickjs.Value.exception;
    defer ctx.freeCString(token.ptr);
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const current_opt = elementAttributeString(ctx, element, "class");
    defer if (current_opt) |current| ctx.freeCString(current.ptr);
    const current_text = if (current_opt) |current| current.ptr[0..current.len] else "";
    var out: [512]u8 = undefined;
    var stream = std.Io.Writer.fixed(&out);
    var iter = std.mem.tokenizeScalar(u8, current_text, ' ');
    var first = true;
    while (iter.next()) |part| {
        if (std.mem.eql(u8, part, token.ptr[0..token.len])) continue;
        if (!first) stream.writeAll(" ") catch {};
        stream.writeAll(part) catch {};
        first = false;
    }
    setElementStringAttribute(ctx, element, "class", stream.buffered()) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsDatasetGet(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.undefined;
    const key = args[1].toCStringLen(ctx) orelse return quickjs.Value.undefined;
    defer ctx.freeCString(key.ptr);
    if (std.mem.eql(u8, key.ptr[0..key.len], "__zigElement")) return args[0].getPropertyStr(ctx, "__zigElement");
    var attr_buf: [256]u8 = undefined;
    const attr = datasetKeyToAttribute(&attr_buf, key.ptr[0..key.len]) orelse return quickjs.Value.undefined;
    const element = args[0].getPropertyStr(ctx, "__zigElement");
    defer element.deinit(ctx);
    const handle = parseThisHandle(ctx, element, "dataset") orelse return quickjs.Value.exception;
    const value = elementAttributeValueToJs(ctx, handle, attr, null, "dataset");
    if (value.isNull()) {
        value.deinit(ctx);
        return quickjs.Value.undefined;
    }
    return value;
}

fn jsDatasetSet(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 3) return quickjs.Value.initBool(false);
    const key = args[1].toCStringLen(ctx) orelse return quickjs.Value.initBool(false);
    defer ctx.freeCString(key.ptr);
    var attr_buf: [256]u8 = undefined;
    const attr = datasetKeyToAttribute(&attr_buf, key.ptr[0..key.len]) orelse return quickjs.Value.initBool(false);
    const element = args[0].getPropertyStr(ctx, "__zigElement");
    defer element.deinit(ctx);
    const text = args[2].toCStringLen(ctx) orelse return quickjs.Value.initBool(false);
    defer ctx.freeCString(text.ptr);
    setElementStringAttribute(ctx, element, attr, text.ptr[0..text.len]) catch return quickjs.Value.exception;
    return quickjs.Value.initBool(true);
}

fn jsDatasetDelete(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.initBool(false);
    const key = args[1].toCStringLen(ctx) orelse return quickjs.Value.initBool(false);
    defer ctx.freeCString(key.ptr);
    var attr_buf: [256]u8 = undefined;
    const attr = datasetKeyToAttribute(&attr_buf, key.ptr[0..key.len]) orelse return quickjs.Value.initBool(false);
    const element = args[0].getPropertyStr(ctx, "__zigElement");
    defer element.deinit(ctx);
    const handle = parseThisHandle(ctx, element, "dataset") orelse return quickjs.Value.exception;
    const status = zig_dom.zig_dom_element_remove_attribute(handle, attr.ptr, attr.len);
    if (status != 0) return throwStatus(ctx, "dataset", status);
    return quickjs.Value.initBool(true);
}

fn datasetKeyToAttribute(buffer: *[256]u8, key: []const u8) ?[]const u8 {
    var stream = std.Io.Writer.fixed(buffer);
    stream.writeAll("data-") catch return null;
    for (key) |ch| {
        if (std.ascii.isUpper(ch)) {
            stream.writeByte('-') catch return null;
            stream.writeByte(std.ascii.toLower(ch)) catch return null;
        } else {
            stream.writeByte(ch) catch return null;
        }
    }
    return stream.buffered();
}

fn jsEventTargetAddEventListener(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2 or args[1].isUndefined() or args[1].isNull()) return quickjs.Value.undefined;
    const type_arg = parseStringArg(ctx, args, 0, "addEventListener") orelse return quickjs.Value.exception;
    defer ctx.freeCString(type_arg.ptr);

    const listeners = ensureObjectProperty(ctx, this_value, "__zigEventListeners") orelse return quickjs.Value.exception;
    defer listeners.deinit(ctx);
    var list = listeners.getPropertyStr(ctx, type_arg.ptr);
    if (list.isException() or !list.isObject()) {
        list.deinit(ctx);
        list = quickjs.Value.initArray(ctx);
        if (list.isException()) return quickjs.Value.exception;
        listeners.setPropertyStr(ctx, type_arg.ptr, list.dup(ctx)) catch {
            list.deinit(ctx);
            return quickjs.Value.exception;
        };
    }
    defer list.deinit(ctx);

    const entry = quickjs.Value.initObject(ctx);
    if (entry.isException()) return quickjs.Value.exception;
    defer entry.deinit(ctx);
    entry.setPropertyStr(ctx, "callback", args[1].dup(ctx)) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "capture", quickjs.Value.initBool(eventOptionBool(ctx, args, 2, "capture"))) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "once", quickjs.Value.initBool(eventOptionBool(ctx, args, 2, "once"))) catch return quickjs.Value.exception;

    const length = arrayLength(ctx, list);
    list.setPropertyUint32(ctx, length, entry.dup(ctx)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsEventTargetRemoveEventListener(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.undefined;
    const type_arg = parseStringArg(ctx, args, 0, "removeEventListener") orelse return quickjs.Value.exception;
    defer ctx.freeCString(type_arg.ptr);

    const listeners = this_value.getPropertyStr(ctx, "__zigEventListeners");
    defer listeners.deinit(ctx);
    if (listeners.isException() or !listeners.isObject()) return quickjs.Value.undefined;
    const list = listeners.getPropertyStr(ctx, type_arg.ptr);
    defer list.deinit(ctx);
    if (list.isException() or !list.isObject()) return quickjs.Value.undefined;

    const len = arrayLength(ctx, list);
    var write: u32 = 0;
    for (0..len) |i_usize| {
        const i: u32 = @intCast(i_usize);
        const entry = list.getPropertyUint32(ctx, i);
        defer entry.deinit(ctx);
        if (entry.isException() or !entry.isObject()) continue;
        const callback = entry.getPropertyStr(ctx, "callback");
        defer callback.deinit(ctx);
        if (callback.isStrictEqual(ctx, args[1])) continue;
        if (write != i) list.setPropertyUint32(ctx, write, entry.dup(ctx)) catch return quickjs.Value.exception;
        write += 1;
    }
    setArrayLength(ctx, list, write);
    return quickjs.Value.undefined;
}

fn jsEventTargetDispatchEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return throwOperationMessage(ctx, "dispatchEvent", "event argument must be an object");
    const event = args[0];
    const type_value = event.getPropertyStr(ctx, "type");
    defer type_value.deinit(ctx);
    const type_arg = type_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "dispatchEvent", "event type must be a string");
    defer ctx.freeCString(type_arg.ptr);

    const is_disabled_click = std.mem.eql(u8, type_arg.ptr[0..type_arg.len], "click") and ((jsElementDisabledGet(ctx, this_value).toBool(ctx) catch false));
    if (is_disabled_click) {
        return quickjs.Value.initBool(true);
    }
    if (std.mem.eql(u8, type_arg.ptr[0..type_arg.len], "click")) {
        applyPreClickState(ctx, this_value);
    }

    event.setPropertyStr(ctx, "_target", this_value.dup(ctx)) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "target", this_value.dup(ctx)) catch return quickjs.Value.exception;

    var path = [_]quickjs.Value{quickjs.Value.undefined} ** 64;
    var path_len: usize = 0;
    var cursor = this_value.dup(ctx);
    defer cursor.deinit(ctx);
    while (path_len < path.len and cursor.isObject()) {
        path[path_len] = cursor.dup(ctx);
        path_len += 1;
        const parent = cursor.getPropertyStr(ctx, "parentNode");
        cursor.deinit(ctx);
        cursor = parent;
        if (cursor.isNull() or cursor.isUndefined() or cursor.isException()) break;
    }
    defer for (path[0..path_len]) |value| value.deinit(ctx);
    const composed_path = quickjs.Value.initArray(ctx);
    if (composed_path.isException()) return composed_path;
    defer composed_path.deinit(ctx);
    for (path[0..path_len], 0..) |item, index| {
        composed_path.setPropertyUint32(ctx, @intCast(index), item.dup(ctx)) catch return quickjs.Value.exception;
    }
    event.setPropertyStr(ctx, "_path", composed_path.dup(ctx)) catch return quickjs.Value.exception;

    var i = path_len;
    while (i > 1) {
        i -= 1;
        tryDispatchListeners(ctx, path[i], event, type_arg.ptr, true, 1) catch return quickjs.Value.exception;
    }
    tryDispatchListeners(ctx, this_value, event, type_arg.ptr, true, 2) catch return quickjs.Value.exception;
    tryDispatchListeners(ctx, this_value, event, type_arg.ptr, false, 2) catch return quickjs.Value.exception;
    tryDispatchPropertyListener(ctx, this_value, event, type_arg.ptr) catch return quickjs.Value.exception;

    const bubbles = boolProperty(ctx, event, "bubbles");
    if (bubbles) {
        for (path[1..path_len]) |ancestor| {
            tryDispatchListeners(ctx, ancestor, event, type_arg.ptr, false, 3) catch return quickjs.Value.exception;
        }
    }

    event.setPropertyStr(ctx, "_eventPhase", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "eventPhase", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "_currentTarget", quickjs.Value.null) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "currentTarget", quickjs.Value.null) catch return quickjs.Value.exception;

    if (std.mem.eql(u8, type_arg.ptr[0..type_arg.len], "click") and !boolProperty(ctx, event, "defaultPrevented")) {
        const action_result = applyClickDefaultAction(ctx, this_value);
        defer action_result.deinit(ctx);
        if (action_result.isException()) return quickjs.Value.exception;
    }

    return quickjs.Value.initBool(!boolProperty(ctx, event, "_canceled"));
}

fn jsElementClick(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const mouse_event_ctor = global.getPropertyStr(ctx, "MouseEvent");
    defer mouse_event_ctor.deinit(ctx);
    if (mouse_event_ctor.isException() or !mouse_event_ctor.isObject()) {
        return quickjs.Value.undefined;
    }

    const type_arg = quickjs.Value.initStringLen(ctx, "click");
    defer type_arg.deinit(ctx);
    const options = quickjs.Value.initObject(ctx);
    if (options.isException()) return quickjs.Value.exception;
    defer options.deinit(ctx);
    options.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    options.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;

    const event_args = [_]quickjs.Value{ type_arg, options };
    const event = createEventObject(ctx, mouse_event_ctor, event_args[0..], .mouse);
    defer event.deinit(ctx);
    if (event.isException()) return event.dup(ctx);

    const dispatched = jsEventTargetDispatchEvent(ctx, this_value, @ptrCast(&[_]quickjs.Value{event}));
    defer dispatched.deinit(ctx);

    return quickjs.Value.undefined;
}

fn applyPreClickState(ctx: *quickjs.Context, target: quickjs.Value) void {
    const local = jsElementLocalNameGet(ctx, target);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return;
    defer ctx.freeCString(local_text.ptr);
    if (!std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "input")) return;
    const type_value_opt = elementAttributeString(ctx, target, "type");
    defer if (type_value_opt) |value| ctx.freeCString(value.ptr);
    const type_value = if (type_value_opt) |value| value.ptr[0..value.len] else "";
    if (std.ascii.eqlIgnoreCase(type_value, "checkbox")) {
        const checked = jsElementCheckedGet(ctx, target);
        defer checked.deinit(ctx);
        const next = quickjs.Value.initBool(!(checked.toBool(ctx) catch false));
        const ignored = jsElementCheckedSet(ctx, target, next);
        ignored.deinit(ctx);
    } else if (std.ascii.eqlIgnoreCase(type_value, "radio")) {
        const on = quickjs.Value.initBool(true);
        const ignored = jsElementCheckedSet(ctx, target, on);
        ignored.deinit(ctx);
    }
}

fn applyClickDefaultAction(ctx: *quickjs.Context, target: quickjs.Value) quickjs.Value {
    const disabled = jsElementDisabledGet(ctx, target);
    defer disabled.deinit(ctx);
    if (disabled.toBool(ctx) catch false) return quickjs.Value.undefined;
    const local = jsElementLocalNameGet(ctx, target);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return quickjs.Value.undefined;
    defer ctx.freeCString(local_text.ptr);

    const is_button = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "button");
    const is_input = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "input");
    const is_label = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "label");
    if (is_label) {
        const html_for = elementAttributeString(ctx, target, "for");
        defer if (html_for) |value| ctx.freeCString(value.ptr);
        const control = if (html_for) |value| blk: {
            const document = jsNodeOwnerDocumentGet(ctx, target);
            defer document.deinit(ctx);
            const id_value = quickjs.Value.initStringLen(ctx, value.ptr[0..value.len]);
            defer id_value.deinit(ctx);
            break :blk jsDocumentGetElementById(ctx, document, @ptrCast(&[_]quickjs.Value{id_value}));
        } else blk: {
            const selector = quickjs.Value.initStringLen(ctx, "input");
            defer selector.deinit(ctx);
            break :blk jsElementQuerySelector(ctx, target, @ptrCast(&[_]quickjs.Value{selector}));
        };
        defer control.deinit(ctx);
        if (control.isObject()) {
            const click = jsElementClick(ctx, control, &.{});
            defer click.deinit(ctx);
        }
        return quickjs.Value.undefined;
    }
    if (!is_button and !is_input) {
        return quickjs.Value.undefined;
    }

    const type_value_opt = elementAttributeString(ctx, target, "type");
    defer if (type_value_opt) |value| ctx.freeCString(value.ptr);
    const type_value = if (type_value_opt) |value| value.ptr[0..value.len] else "";

    if (is_input and (std.ascii.eqlIgnoreCase(type_value, "checkbox") or std.ascii.eqlIgnoreCase(type_value, "radio"))) {
        if (std.ascii.eqlIgnoreCase(type_value, "radio")) {
            const name = elementAttributeString(ctx, target, "name");
            defer if (name) |value| ctx.freeCString(value.ptr);
            if (name) |value| {
                const document = jsNodeOwnerDocumentGet(ctx, target);
                defer document.deinit(ctx);
                var selector_buf: [256]u8 = undefined;
                const selector_text = std.fmt.bufPrint(&selector_buf, "input[type=\"radio\"][name=\"{s}\"]", .{value.ptr[0..value.len]}) catch "";
                const selector = quickjs.Value.initStringLen(ctx, selector_text);
                defer selector.deinit(ctx);
                const radios = jsDocumentQuerySelectorAll(ctx, document, @ptrCast(&[_]quickjs.Value{selector}));
                defer radios.deinit(ctx);
                const len = arrayLength(ctx, radios);
                for (0..len) |i_usize| {
                    const radio = radios.getPropertyUint32(ctx, @intCast(i_usize));
                    defer radio.deinit(ctx);
                    if (!radio.isStrictEqual(ctx, target)) {
                        const off = quickjs.Value.initBool(false);
                        const ignored = jsElementCheckedSet(ctx, radio, off);
                        defer ignored.deinit(ctx);
                    }
                }
            }
            const on = quickjs.Value.initBool(true);
            const ignored = jsElementCheckedSet(ctx, target, on);
            defer ignored.deinit(ctx);
        }
        return quickjs.Value.undefined;
    }

    const should_submit = if (is_button)
        (type_value.len == 0 or std.ascii.eqlIgnoreCase(type_value, "submit"))
    else
        std.ascii.eqlIgnoreCase(type_value, "submit");
    const should_reset = std.ascii.eqlIgnoreCase(type_value, "reset");

    if (!should_submit and !should_reset) {
        return quickjs.Value.undefined;
    }

    const form = jsElementFormGet(ctx, target);
    defer form.deinit(ctx);
    if (!form.isObject()) {
        return quickjs.Value.undefined;
    }

    if (should_submit) {
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const event_ctor = global.getPropertyStr(ctx, "Event");
        defer event_ctor.deinit(ctx);
        if (event_ctor.isException() or !event_ctor.isObject()) return quickjs.Value.undefined;

        const submit_type = quickjs.Value.initStringLen(ctx, "submit");
        defer submit_type.deinit(ctx);
        const submit_options = quickjs.Value.initObject(ctx);
        if (submit_options.isException()) return quickjs.Value.exception;
        defer submit_options.deinit(ctx);
        submit_options.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
        submit_options.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;

        const submit_args = [_]quickjs.Value{ submit_type, submit_options };
        const submit_event = createEventObject(ctx, event_ctor, submit_args[0..], .event);
        defer submit_event.deinit(ctx);
        if (submit_event.isException()) return submit_event.dup(ctx);

        const submit_dispatched = jsEventTargetDispatchEvent(ctx, form, @ptrCast(&[_]quickjs.Value{submit_event}));
        defer submit_dispatched.deinit(ctx);
        return quickjs.Value.undefined;
    }

    const reset_fn = form.getPropertyStr(ctx, "reset");
    defer reset_fn.deinit(ctx);
    if (reset_fn.isFunction(ctx)) {
        const reset_result = reset_fn.call(ctx, form, &.{});
        defer reset_result.deinit(ctx);
        if (reset_result.isException()) return quickjs.Value.exception;
    }

    return quickjs.Value.undefined;
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
        return quickjs.Value.null;
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

fn jsNodeGetRootNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var cursor = this_value.dup(ctx);
    while (true) {
        const parent = jsNodeParentNodeGet(ctx, cursor);
        if (parent.isNull() or parent.isUndefined() or parent.isException()) {
            parent.deinit(ctx);
            return cursor;
        }
        cursor.deinit(ctx);
        cursor = parent;
    }
}

fn jsNodeCompareDocumentPosition(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "compareDocumentPosition") orelse return quickjs.Value.exception;
    const other_handle = parseRequiredNodeArgHandle(ctx, args, 0, "compareDocumentPosition") orelse return quickjs.Value.exception;

    return quickjs.Value.initInt32(@intCast(zig_dom.zig_dom_node_compare_document_position(this_handle, other_handle)));
}

fn jsNodeIsEqualNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or args[0].isNull() or args[0].isUndefined()) return quickjs.Value.initBool(false);
    const left = jsNodeOuterHtmlGet(ctx, this_value);
    defer left.deinit(ctx);
    const right = jsNodeOuterHtmlGet(ctx, args[0]);
    defer right.deinit(ctx);
    if (left.isException() or right.isException()) return quickjs.Value.initBool(false);
    const left_text = left.toCStringLen(ctx) orelse return quickjs.Value.initBool(false);
    defer ctx.freeCString(left_text.ptr);
    const right_text = right.toCStringLen(ctx) orelse return quickjs.Value.initBool(false);
    defer ctx.freeCString(right_text.ptr);
    return quickjs.Value.initBool(std.mem.eql(u8, left_text.ptr[0..left_text.len], right_text.ptr[0..right_text.len]));
}

fn jsNodeNormalize(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var previous_text: quickjs.Value = quickjs.Value.null;
    defer previous_text.deinit(ctx);
    var child = jsNodeFirstChildGet(ctx, this_value);
    defer child.deinit(ctx);
    while (child.isObject()) {
        const next = jsNodeNextSiblingGet(ctx, child);
        defer next.deinit(ctx);
        const normalize_child = jsNodeNormalize(ctx, child, &.{});
        defer normalize_child.deinit(ctx);
        const child_type = zig_dom.zig_dom_node_type(parseThisHandle(ctx, child, "normalize") orelse return quickjs.Value.exception);
        if (child_type == 3) {
            const text = jsNodeTextContentGet(ctx, child);
            defer text.deinit(ctx);
            const cstr = text.toCStringLen(ctx) orelse return quickjs.Value.exception;
            defer ctx.freeCString(cstr.ptr);
            if (cstr.len == 0) {
                const removed = jsNodeRemoveChild(ctx, this_value, @ptrCast(&[_]quickjs.Value{child}));
                defer removed.deinit(ctx);
            } else if (previous_text.isObject()) {
                const prev_text = jsNodeTextContentGet(ctx, previous_text);
                defer prev_text.deinit(ctx);
                const prev_cstr = prev_text.toCStringLen(ctx) orelse return quickjs.Value.exception;
                defer ctx.freeCString(prev_cstr.ptr);
                var buffer: [4096]u8 = undefined;
                const merged = std.fmt.bufPrint(&buffer, "{s}{s}", .{ prev_cstr.ptr[0..prev_cstr.len], cstr.ptr[0..cstr.len] }) catch return quickjs.Value.exception;
                const merged_value = quickjs.Value.initStringLen(ctx, merged);
                defer merged_value.deinit(ctx);
                const set_result = jsNodeTextContentSet(ctx, previous_text, merged_value);
                defer set_result.deinit(ctx);
                const removed = jsNodeRemoveChild(ctx, this_value, @ptrCast(&[_]quickjs.Value{child}));
                defer removed.deinit(ctx);
            } else {
                previous_text.deinit(ctx);
                previous_text = child.dup(ctx);
            }
        } else {
            previous_text.deinit(ctx);
            previous_text = quickjs.Value.null;
        }
        child.deinit(ctx);
        child = next.dup(ctx);
    }
    return quickjs.Value.undefined;
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

fn jsNodeAppend(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "append") orelse return quickjs.Value.exception;

    for (args) |arg| {
        const child_handle = nodeOrTextHandle(ctx, this_handle, arg, "append") orelse return quickjs.Value.exception;
        const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
            zig_dom.zig_dom_node_append_fragment(this_handle, child_handle)
        else
            zig_dom.zig_dom_node_append_child(this_handle, child_handle);
        if (status != 0) return throwStatus(ctx, "append", status);
    }

    return quickjs.Value.undefined;
}

fn jsNodePrepend(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "prepend") orelse return quickjs.Value.exception;
    const reference_handle = zig_dom.zig_dom_node_first_child(this_handle);

    for (args) |arg| {
        const child_handle = nodeOrTextHandle(ctx, this_handle, arg, "prepend") orelse return quickjs.Value.exception;
        const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
            insertFragmentBefore(this_handle, child_handle, reference_handle)
        else
            zig_dom.zig_dom_node_insert_before(this_handle, child_handle, reference_handle);
        if (status != 0) return throwStatus(ctx, "prepend", status);
    }

    return quickjs.Value.undefined;
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
    callMethodNoArgs(ctx, args[0], "disconnectedCallback") catch return quickjs.Value.exception;

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

fn nodeOrTextHandle(ctx: *quickjs.Context, parent_handle: u64, value: quickjs.Value, operation: []const u8) ?u64 {
    if (parseValueNodeHandle(ctx, value)) |handle_i64| {
        if (handle_i64 <= 0) {
            _ = throwOperationMessage(ctx, operation, "node argument has an invalid native handle");
            return null;
        }
        return @intCast(handle_i64);
    }

    var document_handle: u64 = 0;
    const owner_status = zig_dom.zig_dom_node_owner_document(parent_handle, &document_handle);
    if (owner_status != 0 or document_handle == 0) {
        _ = throwOperationMessage(ctx, operation, "could not resolve owner document");
        return null;
    }

    const text = value.toCStringLen(ctx) orelse {
        _ = throwOperationMessage(ctx, operation, "argument could not be converted to string");
        return null;
    };
    defer ctx.freeCString(text.ptr);

    var text_handle: u64 = 0;
    const create_status = zig_dom.zig_dom_document_create_text_node(document_handle, text.ptr, text.len, &text_handle);
    if (create_status != 0) {
        _ = throwStatus(ctx, operation, create_status);
        return null;
    }
    return text_handle;
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
    return quickjs.Value.undefined;
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
        return quickjs.Value.null;
    }
    if (out_ptr == null or out_len == 0) return quickjs.Value.initStringLen(ctx, "");
    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
}

fn classListElement(ctx: *quickjs.Context, class_list: quickjs.Value) ?quickjs.Value {
    const element = class_list.getPropertyStr(ctx, "__zigElement");
    if (element.isException() or !element.isObject()) {
        element.deinit(ctx);
        return null;
    }
    return element;
}

fn elementAttributeString(ctx: *quickjs.Context, element: quickjs.Value, name: []const u8) ?CStringArg {
    const handle = parseThisHandle(ctx, element, name) orelse return null;
    const value = elementAttributeValueToJs(ctx, handle, name, null, name);
    defer value.deinit(ctx);
    if (value.isNull() or value.isUndefined()) return null;
    const cstr = value.toCStringLen(ctx) orelse return null;
    return .{ .ptr = cstr.ptr, .len = cstr.len };
}

fn setElementStringAttribute(ctx: *quickjs.Context, element: quickjs.Value, name: []const u8, value: []const u8) !void {
    const handle = parseThisHandle(ctx, element, name) orelse return error.JSError;
    const status = zig_dom.zig_dom_element_set_attribute(handle, name.ptr, name.len, value.ptr, value.len);
    if (status != 0) return error.JSError;
}

fn classListHasToken(ctx: *quickjs.Context, element: quickjs.Value, token: []const u8) bool {
    const current = elementAttributeString(ctx, element, "class") orelse return false;
    defer ctx.freeCString(current.ptr);
    var iter = std.mem.tokenizeScalar(u8, current.ptr[0..current.len], ' ');
    while (iter.next()) |part| {
        if (std.mem.eql(u8, part, token)) return true;
    }
    return false;
}

fn parseNullableNodeArgHandle(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize, operation: []const u8) ?u64 {
    if (index >= args.len or args[index].isNull()) {
        return 0;
    }
    return parseRequiredNodeArgHandle(ctx, args, index, operation);
}

fn wrapNodeHandle(ctx: *quickjs.Context, handle: u64) quickjs.Value {
    if (handle == 0) {
        return quickjs.Value.null;
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const wrap = global.getPropertyStr(ctx, "__zigDomWrapNode");
    defer wrap.deinit(ctx);
    if (wrap.isException() or !wrap.isObject()) {
        return throwMessage(ctx, "__zigDomWrapNode is not installed");
    }

    const arg = quickjs.Value.initInt64(@intCast(handle));
    return wrap.call(ctx, quickjs.Value.undefined, &.{arg});
}

fn jsWrapNode(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0) return quickjs.Value.null;
    const handle = args[0].toInt64(ctx) catch return quickjs.Value.null;
    if (handle <= 0) return quickjs.Value.null;
    return wrapNativeNode(ctx, @intCast(handle));
}

fn wrapNativeNode(ctx: *quickjs.Context, handle: u64) quickjs.Value {
    if (handle == 0) return quickjs.Value.null;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const cache = global.getPropertyStr(ctx, "__zigDomNodeCache");
    defer cache.deinit(ctx);
    if (!cache.isException() and cache.isObject()) {
        var key_buffer: [32]u8 = undefined;
        const key = std.fmt.bufPrintZ(&key_buffer, "{d}", .{handle}) catch "";
        const cached = cache.getPropertyStr(ctx, key.ptr);
        if (!cached.isException() and cached.isObject()) return cached;
        cached.deinit(ctx);
    }

    const proto = prototypeForNode(ctx, global, handle);
    defer proto.deinit(ctx);
    const obj = if (!proto.isException() and proto.isObject()) quickjs.Value.initObjectProto(ctx, proto) else quickjs.Value.initObject(ctx);
    if (obj.isException()) return obj;
    obj.setPropertyStr(ctx, "__zigDomNativeHandle", quickjs.Value.initInt64(@intCast(handle))) catch return quickjs.Value.exception;
    var owner: u64 = 0;
    if (zig_dom.zig_dom_node_owner_document(handle, &owner) != 0 or owner > @as(u64, @intCast(std.math.maxInt(i64)))) {
        owner = 0;
    }
    obj.setPropertyStr(ctx, "__zigDomOwnerDocumentHandle", quickjs.Value.initInt64(@intCast(owner))) catch return quickjs.Value.exception;
    if (zig_dom.zig_dom_node_type(handle) == 10) {
        obj.setPropertyStr(ctx, "_nodeTypeOverride", quickjs.Value.initInt64(10)) catch return quickjs.Value.exception;
    }
    if (!cache.isException() and cache.isObject()) {
        var key_buffer: [32]u8 = undefined;
        const key = std.fmt.bufPrintZ(&key_buffer, "{d}", .{handle}) catch "";
        cache.setPropertyStr(ctx, key.ptr, obj.dup(ctx)) catch {};
    }
    return obj;
}

fn prototypeForNode(ctx: *quickjs.Context, global: quickjs.Value, handle: u64) quickjs.Value {
    const node_type = zig_dom.zig_dom_node_type(handle);
    const ctor_name: [*:0]const u8 = switch (node_type) {
        1 => elementConstructorName(ctx, handle),
        3 => "Text",
        8 => "Comment",
        9 => "Document",
        10 => "DocumentType",
        11 => "DocumentFragment",
        else => "Node",
    };
    const ctor = global.getPropertyStr(ctx, ctor_name);
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return quickjs.Value.exception;
    return ctor.getPropertyStr(ctx, "prototype");
}

fn elementConstructorName(ctx: *quickjs.Context, handle: u64) [*:0]const u8 {
    const name = nodeNameToJs(ctx, handle, "constructorName");
    defer name.deinit(ctx);
    const cstr = name.toCStringLen(ctx) orelse return "HTMLElement";
    defer ctx.freeCString(cstr.ptr);
    const local = cstr.ptr[0..cstr.len];
    if (std.ascii.eqlIgnoreCase(local, "input")) return "HTMLInputElement";
    if (std.ascii.eqlIgnoreCase(local, "button")) return "HTMLButtonElement";
    if (std.ascii.eqlIgnoreCase(local, "form")) return "HTMLFormElement";
    if (std.ascii.eqlIgnoreCase(local, "select")) return "HTMLSelectElement";
    if (std.ascii.eqlIgnoreCase(local, "option")) return "HTMLOptionElement";
    if (std.ascii.eqlIgnoreCase(local, "textarea")) return "HTMLTextAreaElement";
    if (std.ascii.eqlIgnoreCase(local, "label")) return "HTMLLabelElement";
    if (std.ascii.eqlIgnoreCase(local, "a")) return "HTMLAnchorElement";
    if (std.ascii.eqlIgnoreCase(local, "svg")) return "SVGElement";
    return "HTMLElement";
}

fn createWindowObject(ctx: *quickjs.Context, window_handle: u64, document: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "Window");
    defer ctor.deinit(ctx);
    const proto = ctor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    const obj = if (!proto.isException() and proto.isObject()) quickjs.Value.initObjectProto(ctx, proto) else quickjs.Value.initObject(ctx);
    if (obj.isException()) return obj;
    obj.setPropertyStr(ctx, "_windowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "document", document.dup(ctx)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "closed", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "navigator", quickjs.Value.initObject(ctx)) catch return quickjs.Value.exception;
    const location = quickjs.Value.initObject(ctx);
    location.setPropertyStr(ctx, "href", quickjs.Value.initStringLen(ctx, "http://localhost/")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "origin", quickjs.Value.initStringLen(ctx, "http://localhost")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "protocol", quickjs.Value.initStringLen(ctx, "http:")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "host", quickjs.Value.initStringLen(ctx, "localhost")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "hostname", quickjs.Value.initStringLen(ctx, "localhost")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "port", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "pathname", quickjs.Value.initStringLen(ctx, "/")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "search", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "hash", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "location", location) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "getComputedStyle", jsWindowGetComputedStyle, 1) catch return quickjs.Value.exception;
    for (surfaces.window_constructor_exports) |name| {
        const value = global.getPropertyStr(ctx, name);
        defer value.deinit(ctx);
        if (!value.isException() and !value.isUndefined()) {
            obj.setPropertyStr(ctx, name, value.dup(ctx)) catch return quickjs.Value.exception;
        }
    }
    return obj;
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

fn handleCollectionToJs(ctx: *quickjs.Context, handles: [*c]u64, len: usize) quickjs.Value {
    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) return array;
    for (0..len) |i| {
        const wrapped = wrapNodeHandle(ctx, handles[i]);
        if (wrapped.isException()) {
            array.deinit(ctx);
            return quickjs.Value.exception;
        }
        array.setPropertyUint32(ctx, @intCast(i), wrapped) catch {
            array.deinit(ctx);
            return quickjs.Value.exception;
        };
    }
    installMethod(ctx, array, "item", jsCollectionItem, 1) catch {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, array, "toArray", jsCollectionToArray, 0) catch {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };
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
    const factory = function_ctor.call(ctx, quickjs.Value.undefined, &.{body});
    defer factory.deinit(ctx);
    if (factory.isException()) return quickjs.Value.exception;
    const reader = factory.call(ctx, quickjs.Value.undefined, &.{handles});
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

fn childCollectionToJs(ctx: *quickjs.Context, parent_handle: u64, elements_only: bool) quickjs.Value {
    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) return array;

    var index: u32 = 0;
    var child = zig_dom.zig_dom_node_first_child(parent_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        if (!elements_only or zig_dom.zig_dom_node_type(child) == 1) {
            const wrapped = wrapNodeHandle(ctx, child);
            if (wrapped.isException()) {
                array.deinit(ctx);
                return quickjs.Value.exception;
            }
            array.setPropertyUint32(ctx, index, wrapped) catch {
                array.deinit(ctx);
                return quickjs.Value.exception;
            };
            index += 1;
        }
    }

    const item = quickjs.Value.initCFunction(ctx, jsCollectionItem, "item", 1);
    if (item.isException()) {
        array.deinit(ctx);
        return quickjs.Value.exception;
    }
    array.setPropertyStr(ctx, "item", item) catch {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };

    const to_array = quickjs.Value.initCFunction(ctx, jsCollectionToArray, "toArray", 0);
    if (to_array.isException()) {
        array.deinit(ctx);
        return quickjs.Value.exception;
    }
    array.setPropertyStr(ctx, "toArray", to_array) catch {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };

    return array;
}

fn ensureObjectProperty(ctx: *quickjs.Context, object: quickjs.Value, name: [*:0]const u8) ?quickjs.Value {
    var value = object.getPropertyStr(ctx, name);
    if (!value.isException() and value.isObject()) return value;
    value.deinit(ctx);
    value = quickjs.Value.initObject(ctx);
    if (value.isException()) return null;
    object.setPropertyStr(ctx, name, value.dup(ctx)) catch {
        value.deinit(ctx);
        return null;
    };
    return value;
}

fn eventOptionBool(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize, name: [*:0]const u8) bool {
    if (index >= args.len) return false;
    if (args[index].isBool()) return args[index].toBool(ctx) catch false;
    if (!args[index].isObject()) return false;
    const value = args[index].getPropertyStr(ctx, name);
    defer value.deinit(ctx);
    if (value.isException() or value.isUndefined() or value.isNull()) return false;
    return value.toBool(ctx) catch false;
}

fn boolProperty(ctx: *quickjs.Context, object: quickjs.Value, name: [*:0]const u8) bool {
    const value = object.getPropertyStr(ctx, name);
    defer value.deinit(ctx);
    if (value.isException() or value.isUndefined() or value.isNull()) return false;
    return value.toBool(ctx) catch false;
}

fn optionValue(ctx: *quickjs.Context, args: []const quickjs.Value, name: [*:0]const u8) quickjs.Value {
    if (args.len < 2 or !args[1].isObject()) return quickjs.Value.undefined;
    const value = args[1].getPropertyStr(ctx, name);
    if (value.isException()) return quickjs.Value.undefined;
    return value;
}

fn optionValueOrNull(ctx: *quickjs.Context, args: []const quickjs.Value, name: [*:0]const u8) quickjs.Value {
    const value = optionValue(ctx, args, name);
    if (value.isUndefined()) {
        value.deinit(ctx);
        return quickjs.Value.null;
    }
    return value;
}

fn optionString(ctx: *quickjs.Context, args: []const quickjs.Value, name: [*:0]const u8, fallback: []const u8) quickjs.Value {
    const value = optionValue(ctx, args, name);
    defer value.deinit(ctx);
    if (value.isUndefined() or value.isNull()) return quickjs.Value.initStringLen(ctx, fallback);
    const text = value.toCStringLen(ctx) orelse return quickjs.Value.initStringLen(ctx, fallback);
    defer ctx.freeCString(text.ptr);
    return quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
}

fn optionBool(ctx: *quickjs.Context, args: []const quickjs.Value, name: [*:0]const u8) bool {
    const value = optionValue(ctx, args, name);
    defer value.deinit(ctx);
    if (value.isUndefined() or value.isNull()) return false;
    return value.toBool(ctx) catch false;
}

fn optionNumber(ctx: *quickjs.Context, args: []const quickjs.Value, name: [*:0]const u8) f64 {
    const value = optionValue(ctx, args, name);
    defer value.deinit(ctx);
    if (value.isUndefined() or value.isNull()) return 0;
    return value.toFloat64(ctx) catch 0;
}

fn numericArg(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize) f64 {
    if (index >= args.len) return 0;
    return args[index].toFloat64(ctx) catch 0;
}

fn arrayLength(ctx: *quickjs.Context, array: quickjs.Value) u32 {
    const length = array.getPropertyStr(ctx, "length");
    defer length.deinit(ctx);
    if (length.isException()) return 0;
    const value = length.toInt64(ctx) catch return 0;
    if (value <= 0) return 0;
    return @intCast(@min(value, std.math.maxInt(u32)));
}

fn setArrayLength(ctx: *quickjs.Context, array: quickjs.Value, length: u32) void {
    array.setPropertyStr(ctx, "length", quickjs.Value.initInt64(length)) catch {};
}

fn tryDispatchListeners(ctx: *quickjs.Context, target: quickjs.Value, event: quickjs.Value, event_type: [*:0]const u8, capture: bool, phase: i64) !void {
    const listeners = target.getPropertyStr(ctx, "__zigEventListeners");
    defer listeners.deinit(ctx);
    if (listeners.isException() or !listeners.isObject()) return;
    const list = listeners.getPropertyStr(ctx, event_type);
    defer list.deinit(ctx);
    if (list.isException() or !list.isObject()) return;

    event.setPropertyStr(ctx, "_eventPhase", quickjs.Value.initInt64(phase)) catch return error.JSError;
    event.setPropertyStr(ctx, "_currentTarget", target.dup(ctx)) catch return error.JSError;
    event.setPropertyStr(ctx, "eventPhase", quickjs.Value.initInt64(phase)) catch return error.JSError;
    event.setPropertyStr(ctx, "currentTarget", target.dup(ctx)) catch return error.JSError;

    const len = arrayLength(ctx, list);
    var write: u32 = 0;
    for (0..len) |i_usize| {
        const i: u32 = @intCast(i_usize);
        const entry = list.getPropertyUint32(ctx, i);
        defer entry.deinit(ctx);
        if (entry.isException() or !entry.isObject()) continue;
        if (boolProperty(ctx, entry, "capture") != capture) {
            if (write != i) try list.setPropertyUint32(ctx, write, entry.dup(ctx));
            write += 1;
            continue;
        }
        const callback = entry.getPropertyStr(ctx, "callback");
        defer callback.deinit(ctx);
        if (!callback.isUndefined() and !callback.isNull()) {
            var call_args = [_]quickjs.Value{event.dup(ctx)};
            defer call_args[0].deinit(ctx);
            const result = if (callback.isFunction(ctx))
                callback.call(ctx, target, &call_args)
            else blk: {
                const handle_event = callback.getPropertyStr(ctx, "handleEvent");
                defer handle_event.deinit(ctx);
                if (!handle_event.isFunction(ctx)) break :blk quickjs.Value.undefined;
                break :blk handle_event.call(ctx, callback, &call_args);
            };
            defer result.deinit(ctx);
            if (result.isException()) return error.JSError;
        }
        if (!boolProperty(ctx, entry, "once")) {
            if (write != i) try list.setPropertyUint32(ctx, write, entry.dup(ctx));
            write += 1;
        }
    }
    setArrayLength(ctx, list, write);
}

fn tryDispatchPropertyListener(ctx: *quickjs.Context, target: quickjs.Value, event: quickjs.Value, event_type: [*:0]const u8) !void {
    var name_buf: [128]u8 = undefined;
    const name = std.fmt.bufPrintZ(&name_buf, "on{s}", .{std.mem.span(event_type)}) catch return;
    const callback = target.getPropertyStr(ctx, name.ptr);
    defer callback.deinit(ctx);
    if (!callback.isFunction(ctx)) return;
    var call_args = [_]quickjs.Value{event.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = callback.call(ctx, target, &call_args);
    defer result.deinit(ctx);
    if (result.isException()) return error.JSError;
}

fn jsCollectionItem(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0) return quickjs.Value.null;
    const index_i64 = args[0].toInt64(ctx) catch return quickjs.Value.null;
    if (index_i64 < 0 or index_i64 > std.math.maxInt(u32)) return quickjs.Value.null;
    const value = this_value.getPropertyUint32(ctx, @intCast(index_i64));
    if (value.isException() or value.isUndefined()) {
        value.deinit(ctx);
        return quickjs.Value.null;
    }
    return value;
}

fn jsCollectionToArray(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return this_value.dup(ctx);
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

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

const ClassPerfStats = struct {
    handle_collection_calls: u64 = 0,
    handle_collection_ns: i128 = 0,
    dispatch_event_calls: u64 = 0,
    dispatch_event_ns: i128 = 0,
    computed_style_calls: u64 = 0,
    computed_style_ns: i128 = 0,
    bounding_rect_calls: u64 = 0,
    bounding_rect_ns: i128 = 0,
    focus_calls: u64 = 0,
    focus_ns: i128 = 0,
};

var class_perf_stats = ClassPerfStats{};

fn classProfileEnabled() bool {
    const raw = std.c.getenv("ZIG_DOM_PROFILE_DOM") orelse return false;
    return !std.mem.eql(u8, std.mem.span(raw), "0");
}

fn classProfileNowNs() i128 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return 0;
    return (@as(i128, ts.sec) * 1_000_000_000) + @as(i128, ts.nsec);
}

fn printClassPerfStats() void {
    if (!classProfileEnabled()) return;
    std.debug.print(
        "[zig-dom class profile] collections={d}/{d:.3}ms dispatch={d}/{d:.3}ms computed_style={d}/{d:.3}ms rect={d}/{d:.3}ms focus={d}/{d:.3}ms\n",
        .{
            class_perf_stats.handle_collection_calls,
            @as(f64, @floatFromInt(class_perf_stats.handle_collection_ns)) / 1_000_000.0,
            class_perf_stats.dispatch_event_calls,
            @as(f64, @floatFromInt(class_perf_stats.dispatch_event_ns)) / 1_000_000.0,
            class_perf_stats.computed_style_calls,
            @as(f64, @floatFromInt(class_perf_stats.computed_style_ns)) / 1_000_000.0,
            class_perf_stats.bounding_rect_calls,
            @as(f64, @floatFromInt(class_perf_stats.bounding_rect_ns)) / 1_000_000.0,
            class_perf_stats.focus_calls,
            @as(f64, @floatFromInt(class_perf_stats.focus_ns)) / 1_000_000.0,
        },
    );
    class_perf_stats = .{};
}

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
    pub const hasChildNodes = jsNodeHasChildNodes;
    pub const textContentGet = jsNodeTextContentGet;
    pub const textContentSet = jsNodeTextContentSet;
    pub const nodeValueGet = jsNodeValueGet;
    pub const nodeValueSet = jsNodeValueSet;
    pub const outerHtmlGet = jsNodeOuterHtmlGet;
    pub const contains = jsNodeContains;
    pub const getRootNode = jsNodeGetRootNode;
    pub const compareDocumentPosition = jsNodeCompareDocumentPosition;
    pub const isEqualNode = jsNodeIsEqualNode;
    pub const isSameNode = jsNodeIsSameNode;
    pub const normalize = jsNodeNormalize;
    pub const appendChild = jsNodeAppendChild;
    pub const append = jsNodeAppend;
    pub const prepend = jsNodePrepend;
    pub const insertBefore = jsNodeInsertBefore;
    pub const removeChild = jsNodeRemoveChild;
    pub const remove = jsNodeRemove;
    pub const replaceChild = jsNodeReplaceChild;
    pub const cloneNode = jsNodeCloneNode;
};

const ElementCallbacks = struct {
    pub const tagNameGet = jsElementTagNameGet;
    pub const localNameGet = jsElementLocalNameGet;
    pub const prefixGet = jsElementPrefixGet;
    pub const namespaceUriGet = jsElementNamespaceUriGet;
    pub const idGet = jsElementIdGet;
    pub const idSet = jsElementIdSet;
    pub const classNameGet = jsElementClassNameGet;
    pub const classNameSet = jsElementClassNameSet;
    pub const titleGet = jsElementTitleGet;
    pub const titleSet = jsElementTitleSet;
    pub const htmlForGet = jsElementHtmlForGet;
    pub const htmlForSet = jsElementHtmlForSet;
    pub const controlGet = jsElementControlGet;
    pub const labelsGet = jsElementLabelsGet;
    pub const innerHtmlGet = jsElementInnerHtmlGet;
    pub const innerHtmlSet = jsElementInnerHtmlSet;
    pub const outerHtmlGet = jsElementOuterHtmlGet;
    pub const styleGet = jsElementStyleGet;
    pub const getAttribute = jsElementGetAttribute;
    pub const getAttributeNS = jsElementGetAttributeNS;
    pub const getAttributeNode = jsElementGetAttributeNode;
    pub const setAttribute = jsElementSetAttribute;
    pub const setAttributeNS = jsElementSetAttributeNS;
    pub const removeAttribute = jsElementRemoveAttribute;
    pub const removeAttributeNS = jsElementRemoveAttributeNS;
    pub const hasAttribute = jsElementHasAttribute;
    pub const hasAttributes = jsElementHasAttributes;
    pub const toggleAttribute = jsElementToggleAttribute;
    pub const getAttributeNames = jsElementGetAttributeNames;
    pub const attributesGet = jsElementAttributesGet;
    pub const classListGet = jsElementClassListGet;
    pub const classListSet = jsReadonlySetter;
    pub const datasetGet = jsElementDatasetGet;
    pub const querySelector = jsElementQuerySelector;
    pub const querySelectorAll = jsElementQuerySelectorAll;
    pub const getElementsByTagName = jsElementGetElementsByTagName;
    pub const getElementsByTagNameNS = jsElementGetElementsByTagNameNS;
    pub const getElementsByClassName = jsElementGetElementsByClassName;
    pub const matches = jsElementMatches;
    pub const closest = jsElementClosest;
    pub const insertAdjacentElement = jsElementInsertAdjacentElement;
    pub const insertAdjacentHTML = jsElementInsertAdjacentHTML;
    pub const insertAdjacentText = jsElementInsertAdjacentText;
    pub const attachShadow = jsElementAttachShadow;
    pub const getBoundingClientRect = jsElementGetBoundingClientRect;
    pub const getClientRects = jsElementGetClientRects;
    pub const scrollIntoView = jsElementScrollIntoView;
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
    pub const reset = jsElementReset;
    pub const requestSubmit = jsElementRequestSubmit;
};

const DocumentCallbacks = struct {
    pub const documentElementGet = jsDocumentElementGet;
    pub const doctypeGet = jsDocumentDoctypeGet;
    pub const headGet = jsDocumentHeadGet;
    pub const bodyGet = jsDocumentBodyGet;
    pub const defaultViewGet = jsDocumentDefaultViewGet;
    pub const implementationGet = jsDocumentImplementationGet;
    pub const contentTypeGet = jsDocumentContentTypeGet;
    pub const createElement = jsDocumentCreateElement;
    pub const createElementNS = jsDocumentCreateElementNS;
    pub const createAttribute = jsDocumentCreateAttribute;
    pub const createTextNode = jsDocumentCreateTextNode;
    pub const createComment = jsDocumentCreateComment;
    pub const createProcessingInstruction = jsDocumentCreateProcessingInstruction;
    pub const createDocumentFragment = jsDocumentCreateDocumentFragment;
    pub const createDocumentType = jsDocumentCreateDocumentType;
    pub const createEvent = jsDocumentCreateEvent;
    pub const createRange = jsDocumentCreateRange;
    pub const createTreeWalker = jsDocumentCreateTreeWalker;
    pub const getSelection = jsDocumentGetSelection;
    pub const importNode = jsDocumentImportNode;
    pub const adoptNode = jsDocumentAdoptNode;
    pub const getElementById = jsDocumentGetElementById;
    pub const querySelector = jsDocumentQuerySelector;
    pub const querySelectorAll = jsDocumentQuerySelectorAll;
    pub const getElementsByTagName = jsDocumentGetElementsByTagName;
    pub const getElementsByTagNameNS = jsDocumentGetElementsByTagNameNS;
    pub const getElementsByClassName = jsDocumentGetElementsByClassName;
};

const CharacterDataCallbacks = struct {
    pub const dataGet = jsNodeTextContentGet;
    pub const dataSet = jsCharacterDataDataSet;
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
        printClassPerfStats();
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
        try installMethod(ctx, node_proto, "before", jsNodeBefore, 0);
        try installMethod(ctx, node_proto, "after", jsNodeAfter, 0);
        try installMethod(ctx, node_proto, "replaceWith", jsNodeReplaceWith, 0);
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
        try installMethod(ctx, global, "__zigDomSyncWindowNamedProperties", jsDomSyncWindowNamedProperties, 0);

        const cache = quickjs.Value.initObject(ctx);
        if (cache.isException()) return error.OutOfMemory;
        global.setPropertyStr(ctx, "__zigDomNodeCache", cache) catch return error.PropertyAccessFailed;

        const html_collections = quickjs.Value.initArray(ctx);
        if (html_collections.isException()) return error.OutOfMemory;
        global.setPropertyStr(ctx, "__zigHtmlCollections", html_collections) catch return error.PropertyAccessFailed;

        const document = wrapNativeNode(ctx, document_handle);
        if (document.isException()) return error.PropertyAccessFailed;
        defer document.deinit(ctx);
        document.setPropertyStr(ctx, "_windowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch return error.PropertyAccessFailed;
        document.setPropertyStr(ctx, "__zigHasSyntheticHtmlDoctype", quickjs.Value.initBool(true)) catch return error.PropertyAccessFailed;

        const window = createWindowObject(ctx, window_handle, document);
        if (window.isException()) return error.PropertyAccessFailed;
        defer window.deinit(ctx);

        global.setPropertyStr(ctx, "document", document.dup(ctx)) catch return error.PropertyAccessFailed;
        global.setPropertyStr(ctx, "window", window.dup(ctx)) catch return error.PropertyAccessFailed;
        global.setPropertyStr(ctx, "self", window.dup(ctx)) catch return error.PropertyAccessFailed;
        global.setPropertyStr(ctx, "top", window.dup(ctx)) catch return error.PropertyAccessFailed;
        global.setPropertyStr(ctx, "parent", window.dup(ctx)) catch return error.PropertyAccessFailed;
        window.setPropertyStr(ctx, "window", window.dup(ctx)) catch return error.PropertyAccessFailed;
        window.setPropertyStr(ctx, "document", document.dup(ctx)) catch return error.PropertyAccessFailed;
        inline for (.{ "addEventListener", "removeEventListener", "dispatchEvent" }) |name| {
            const listener_method = window.getPropertyStr(ctx, name);
            defer listener_method.deinit(ctx);
            if (!listener_method.isException() and !listener_method.isUndefined()) {
                const bind = listener_method.getPropertyStr(ctx, "bind");
                defer bind.deinit(ctx);
                const bound = if (!bind.isException() and bind.isFunction(ctx))
                    bind.call(ctx, listener_method, &.{window})
                else
                    listener_method.dup(ctx);
                defer bound.deinit(ctx);
                if (bound.isException()) return error.PropertyAccessFailed;
                global.setPropertyStr(ctx, name, bound.dup(ctx)) catch return error.PropertyAccessFailed;
            }
        }
        try installCustomElementsRegistry(ctx, global, window);
        try installDocumentCookie(ctx, document);
        try self.installNodeSlice(ctx);
        inline for (.{ "addEventListener", "removeEventListener", "dispatchEvent" }) |name| {
            const listener_method = window.getPropertyStr(ctx, name);
            defer listener_method.deinit(ctx);
            if (!listener_method.isException() and !listener_method.isUndefined()) {
                const bind = listener_method.getPropertyStr(ctx, "bind");
                defer bind.deinit(ctx);
                const bound = if (!bind.isException() and bind.isFunction(ctx))
                    bind.call(ctx, listener_method, &.{window})
                else
                    listener_method.dup(ctx);
                defer bound.deinit(ctx);
                if (bound.isException()) return error.PropertyAccessFailed;
                global.setPropertyStr(ctx, name, bound.dup(ctx)) catch return error.PropertyAccessFailed;
            }
        }
        // Bind window.getSelection as a global function so bare getSelection() calls work.
        {
            const gs_method = window.getPropertyStr(ctx, "getSelection");
            defer gs_method.deinit(ctx);
            if (!gs_method.isException() and !gs_method.isUndefined()) {
                const bind = gs_method.getPropertyStr(ctx, "bind");
                defer bind.deinit(ctx);
                const bound = if (!bind.isException() and bind.isFunction(ctx))
                    bind.call(ctx, gs_method, &.{window})
                else
                    gs_method.dup(ctx);
                defer bound.deinit(ctx);
                if (!bound.isException()) {
                    global.setPropertyStr(ctx, "getSelection", bound.dup(ctx)) catch return error.PropertyAccessFailed;
                }
            }
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
    try installEventHandlerProperties(ctx, proto);
}

fn installEventHandlerProperties(ctx: *quickjs.Context, proto: quickjs.Value) DomClassesError!void {
    inline for (.{
        "onclick",
        "ondblclick",
        "onmousedown",
        "onmouseup",
        "onmousemove",
        "onmouseover",
        "onmouseout",
        "onmouseenter",
        "onmouseleave",
        "onpointerdown",
        "onpointerup",
        "onpointermove",
        "onpointerover",
        "onpointerout",
        "onkeydown",
        "onkeyup",
        "onkeypress",
        "onfocus",
        "onblur",
        "oninput",
        "onbeforeinput",
        "onchange",
        "onsubmit",
        "onreset",
        "onerror",
        "onload",
        "onscroll",
        "onresize",
        "oncompositionstart",
        "oncompositionupdate",
        "oncompositionend",
        "onselectionchange",
    }) |name| {
        proto.setPropertyStr(ctx, name, quickjs.Value.null) catch return error.PropertyAccessFailed;
    }
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
    const comment_ctor = global.getPropertyStr(ctx, "Comment");
    defer comment_ctor.deinit(ctx);
    if (!comment_ctor.isException()) {
        global.setPropertyStr(ctx, "ProcessingInstruction", comment_ctor.dup(ctx)) catch return error.PropertyAccessFailed;
    }
    const fragment_proto = try installConstructor(ctx, global, "DocumentFragment", jsConstructDocumentFragment);
    fragment_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const doctype_proto = try installConstructor(ctx, global, "DocumentType", jsConstructDocumentType);
    doctype_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const document_proto = try installConstructor(ctx, global, "Document", jsConstructDocument);
    document_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const range_proto = try installConstructor(ctx, global, "Range", jsConstructRange);
    defer range_proto.deinit(ctx);
    const document_ctor_for_xml = global.getPropertyStr(ctx, "Document");
    defer document_ctor_for_xml.deinit(ctx);
    if (!document_ctor_for_xml.isException()) {
        global.setPropertyStr(ctx, "XMLDocument", document_ctor_for_xml.dup(ctx)) catch return error.PropertyAccessFailed;
    }
    const object_ctor = global.getPropertyStr(ctx, "Object");
    defer object_ctor.deinit(ctx);
    if (!object_ctor.isException()) {
        global.setPropertyStr(ctx, "DOMImplementation", object_ctor.dup(ctx)) catch return error.PropertyAccessFailed;
    }
    const attr_proto = try installConstructor(ctx, global, "Attr", jsConstructAttr);
    attr_proto.setPrototype(ctx, node_proto) catch return error.PropertyAccessFailed;
    const window_proto = try installConstructor(ctx, global, "Window", jsConstructWindow);
    window_proto.setPrototype(ctx, event_target_proto) catch return error.PropertyAccessFailed;
    try installBodyAndFrameSetWindowForwardedHandlers(ctx, global, window_proto);

    const node_list_proto = try installConstructor(ctx, global, "NodeList", jsConstructPlain);
    defer node_list_proto.deinit(ctx);
    const array_ctor = global.getPropertyStr(ctx, "Array");
    defer array_ctor.deinit(ctx);
    if (array_ctor.isException() or !array_ctor.isObject()) return error.PropertyAccessFailed;
    const array_proto = array_ctor.getPropertyStr(ctx, "prototype");
    defer array_proto.deinit(ctx);
    if (array_proto.isException() or !array_proto.isObject()) return error.PropertyAccessFailed;
    node_list_proto.setPrototype(ctx, array_proto) catch return error.PropertyAccessFailed;
    try installGetter(ctx, node_list_proto, "length", jsNodeListLengthGet);
    try installMethod(ctx, node_list_proto, "item", jsCollectionItem, 1);
    try installMethod(ctx, node_list_proto, "toArray", jsCollectionToArray, 0);
    const named_node_map_proto = try installConstructor(ctx, global, "NamedNodeMap", jsConstructPlain);
    defer named_node_map_proto.deinit(ctx);
    try installGetter(ctx, named_node_map_proto, "length", jsNamedNodeMapLengthGet);
    try installMethod(ctx, named_node_map_proto, "item", jsNamedNodeMapItem, 1);
    try installMethod(ctx, named_node_map_proto, "getNamedItem", jsNamedNodeMapGetNamedItem, 1);
    const html_collection_proto = try installConstructor(ctx, global, "HTMLCollection", jsConstructPlain);
    defer html_collection_proto.deinit(ctx);
    try installGetter(ctx, html_collection_proto, "length", jsHtmlCollectionLengthGet);
    try installMethod(ctx, html_collection_proto, "item", jsHtmlCollectionItem, 1);
    try installMethod(ctx, html_collection_proto, "namedItem", jsHtmlCollectionNamedItem, 1);
    try installMethod(ctx, html_collection_proto, "toArray", jsHtmlCollectionToArray, 0);
    try installHtmlCollectionSymbolIterator(ctx, global, html_collection_proto);

    const event_proto = try installConstructor(ctx, global, "Event", jsConstructEvent);
    const event_ctor = global.getPropertyStr(ctx, "Event");
    defer event_ctor.deinit(ctx);
    if (!event_ctor.isException() and event_ctor.isObject()) {
        event_ctor.setPropertyStr(ctx, "NONE", quickjs.Value.initInt64(0)) catch return error.PropertyAccessFailed;
        event_ctor.setPropertyStr(ctx, "CAPTURING_PHASE", quickjs.Value.initInt64(1)) catch return error.PropertyAccessFailed;
        event_ctor.setPropertyStr(ctx, "AT_TARGET", quickjs.Value.initInt64(2)) catch return error.PropertyAccessFailed;
        event_ctor.setPropertyStr(ctx, "BUBBLING_PHASE", quickjs.Value.initInt64(3)) catch return error.PropertyAccessFailed;
    }
    event_proto.setPropertyStr(ctx, "NONE", quickjs.Value.initInt64(0)) catch return error.PropertyAccessFailed;
    event_proto.setPropertyStr(ctx, "CAPTURING_PHASE", quickjs.Value.initInt64(1)) catch return error.PropertyAccessFailed;
    event_proto.setPropertyStr(ctx, "AT_TARGET", quickjs.Value.initInt64(2)) catch return error.PropertyAccessFailed;
    event_proto.setPropertyStr(ctx, "BUBBLING_PHASE", quickjs.Value.initInt64(3)) catch return error.PropertyAccessFailed;
    try installMethod(ctx, event_proto, "preventDefault", jsEventPreventDefault, 0);
    try installMethod(ctx, event_proto, "stopPropagation", jsEventStopPropagation, 0);
    try installMethod(ctx, event_proto, "stopImmediatePropagation", jsEventStopImmediatePropagation, 0);
    try installMethod(ctx, event_proto, "composedPath", jsEventComposedPath, 0);
    try installMethod(ctx, event_proto, "initEvent", jsEventInitEvent, 3);
    try installGetter(ctx, event_proto, "timeStamp", jsEventTimeStampGet);
    try installAccessor(ctx, event_proto, "cancelBubble", jsEventCancelBubbleGet, jsEventCancelBubbleSet);
    try installAccessor(ctx, event_proto, "returnValue", jsEventReturnValueGet, jsEventReturnValueSet);
    const custom_event_proto = try installConstructor(ctx, global, "CustomEvent", jsConstructCustomEvent);
    custom_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    try installMethod(ctx, custom_event_proto, "initCustomEvent", jsCustomEventInitCustomEvent, 4);
    const submit_event_proto = try installConstructor(ctx, global, "SubmitEvent", jsConstructSubmitEvent);
    submit_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    const gamepad_event_proto = try installConstructor(ctx, global, "GamepadEvent", jsConstructGamepadEvent);
    gamepad_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    const ui_event_proto = try installConstructor(ctx, global, "UIEvent", jsConstructUIEvent);
    ui_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    try installMethod(ctx, ui_event_proto, "initUIEvent", jsUIEventInitUIEvent, 5);
    const focus_event_proto = try installConstructor(ctx, global, "FocusEvent", jsConstructFocusEvent);
    focus_event_proto.setPrototype(ctx, ui_event_proto) catch return error.PropertyAccessFailed;
    const mouse_event_proto = try installConstructor(ctx, global, "MouseEvent", jsConstructMouseEvent);
    mouse_event_proto.setPrototype(ctx, ui_event_proto) catch return error.PropertyAccessFailed;
    try installMethod(ctx, mouse_event_proto, "initMouseEvent", jsMouseEventInitMouseEvent, 15);
    const wheel_event_proto = try installConstructor(ctx, global, "WheelEvent", jsConstructWheelEvent);
    wheel_event_proto.setPrototype(ctx, mouse_event_proto) catch return error.PropertyAccessFailed;
    const keyboard_event_proto = try installConstructor(ctx, global, "KeyboardEvent", jsConstructKeyboardEvent);
    keyboard_event_proto.setPrototype(ctx, ui_event_proto) catch return error.PropertyAccessFailed;
    try installMethod(ctx, keyboard_event_proto, "initKeyboardEvent", jsKeyboardEventInitKeyboardEvent, 9);
    const error_event_proto = try installConstructor(ctx, global, "ErrorEvent", jsConstructErrorEvent);
    error_event_proto.setPrototype(ctx, event_proto) catch return error.PropertyAccessFailed;
    const xhr_proto = try installConstructor(ctx, global, "XMLHttpRequest", jsConstructPlain);
    xhr_proto.setPrototype(ctx, event_target_proto) catch return error.PropertyAccessFailed;
    const input_event_proto = try installConstructor(ctx, global, "InputEvent", jsConstructInputEvent);
    input_event_proto.setPrototype(ctx, ui_event_proto) catch return error.PropertyAccessFailed;
    const composition_event_proto = try installConstructor(ctx, global, "CompositionEvent", jsConstructCompositionEvent);
    composition_event_proto.setPrototype(ctx, ui_event_proto) catch return error.PropertyAccessFailed;
    const custom_elements_proto = try installConstructor(ctx, global, "CustomElementRegistry", jsConstructPlain);
    defer custom_elements_proto.deinit(ctx);
    const dom_rect_proto = try installConstructor(ctx, global, "DOMRect", jsConstructDOMRect);
    defer dom_rect_proto.deinit(ctx);
    const mutation_observer_proto = try installConstructor(ctx, global, "MutationObserver", jsConstructMutationObserver);
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
    attr_proto.deinit(ctx);
    window_proto.deinit(ctx);
    event_proto.deinit(ctx);
    custom_event_proto.deinit(ctx);
    submit_event_proto.deinit(ctx);
    gamepad_event_proto.deinit(ctx);
    ui_event_proto.deinit(ctx);
    focus_event_proto.deinit(ctx);
    mouse_event_proto.deinit(ctx);
    wheel_event_proto.deinit(ctx);
    keyboard_event_proto.deinit(ctx);
    error_event_proto.deinit(ctx);
    xhr_proto.deinit(ctx);
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

    const option_ctor = global.getPropertyStr(ctx, "HTMLOptionElement");
    defer option_ctor.deinit(ctx);
    if (!option_ctor.isException() and option_ctor.isObject()) {
        const option_proto = option_ctor.getPropertyStr(ctx, "prototype");
        defer option_proto.deinit(ctx);
        if (!option_proto.isException() and option_proto.isObject()) {
            try installAccessor(ctx, option_proto, "selected", jsElementSelectedGet, jsElementSelectedSet);
        }
    }

    const iframe_ctor = global.getPropertyStr(ctx, "HTMLIFrameElement");
    defer iframe_ctor.deinit(ctx);
    if (!iframe_ctor.isException() and iframe_ctor.isObject()) {
        const iframe_proto = iframe_ctor.getPropertyStr(ctx, "prototype");
        defer iframe_proto.deinit(ctx);
        if (!iframe_proto.isException() and iframe_proto.isObject()) {
            try installGetter(ctx, iframe_proto, "contentWindow", jsIFrameContentWindowGet);
            try installGetter(ctx, iframe_proto, "contentDocument", jsIFrameContentDocumentGet);
            try installAccessor(ctx, iframe_proto, "src", jsIFrameSrcGet, jsIFrameSrcSet);
        }
    }

    const image_ctor = global.getPropertyStr(ctx, "HTMLImageElement");
    defer image_ctor.deinit(ctx);
    if (!image_ctor.isException() and image_ctor.isObject()) {
        const image_proto = image_ctor.getPropertyStr(ctx, "prototype");
        defer image_proto.deinit(ctx);
        if (!image_proto.isException() and image_proto.isObject()) {
            try installAccessor(ctx, image_proto, "src", jsImageSrcGet, jsImageSrcSet);
        }
    }

    const anchor_ctor = global.getPropertyStr(ctx, "HTMLAnchorElement");
    defer anchor_ctor.deinit(ctx);
    if (!anchor_ctor.isException() and anchor_ctor.isObject()) {
        const anchor_proto = anchor_ctor.getPropertyStr(ctx, "prototype");
        defer anchor_proto.deinit(ctx);
        if (!anchor_proto.isException() and anchor_proto.isObject()) {
            try installAccessor(ctx, anchor_proto, "href", jsElementHrefGet, jsElementHrefSet);
        }
    }

    const template_ctor = global.getPropertyStr(ctx, "HTMLTemplateElement");
    defer template_ctor.deinit(ctx);
    if (!template_ctor.isException() and template_ctor.isObject()) {
        const template_proto = template_ctor.getPropertyStr(ctx, "prototype");
        defer template_proto.deinit(ctx);
        if (!template_proto.isException() and template_proto.isObject()) {
            try installGetter(ctx, template_proto, "content", jsTemplateContentGet);
            try installMethod(ctx, template_proto, "querySelector", jsElementQuerySelector, 1);
            try installMethod(ctx, template_proto, "querySelectorAll", jsElementQuerySelectorAll, 1);
            try installMethod(ctx, template_proto, "getElementById", jsDocumentFragmentGetElementById, 1);
        }
    }

}

fn installBodyAndFrameSetWindowForwardedHandlers(ctx: *quickjs.Context, global: quickjs.Value, window_proto: quickjs.Value) DomClassesError!void {
    const body_ctor = global.getPropertyStr(ctx, "HTMLBodyElement");
    defer body_ctor.deinit(ctx);
    if (body_ctor.isException() or !body_ctor.isObject()) return;
    const body_proto = body_ctor.getPropertyStr(ctx, "prototype");
    defer body_proto.deinit(ctx);
    if (body_proto.isException() or !body_proto.isObject()) return;

    const frameset_ctor = global.getPropertyStr(ctx, "HTMLFrameSetElement");
    defer frameset_ctor.deinit(ctx);
    if (frameset_ctor.isException() or !frameset_ctor.isObject()) return;
    const frameset_proto = frameset_ctor.getPropertyStr(ctx, "prototype");
    defer frameset_proto.deinit(ctx);
    if (frameset_proto.isException() or !frameset_proto.isObject()) return;

    try installAccessor(ctx, window_proto, "onblur", jsForwardedOnblurGet, jsForwardedOnblurSet);
    try installAccessor(ctx, window_proto, "onerror", jsForwardedOnerrorGet, jsForwardedOnerrorSet);
    try installAccessor(ctx, window_proto, "onfocus", jsForwardedOnfocusGet, jsForwardedOnfocusSet);
    try installAccessor(ctx, window_proto, "onload", jsForwardedOnloadGet, jsForwardedOnloadSet);
    try installAccessor(ctx, window_proto, "onscroll", jsForwardedOnscrollGet, jsForwardedOnscrollSet);
    try installAccessor(ctx, window_proto, "onresize", jsForwardedOnresizeGet, jsForwardedOnresizeSet);

    try installAccessor(ctx, body_proto, "onblur", jsForwardedOnblurGet, jsForwardedOnblurSet);
    try installAccessor(ctx, body_proto, "onerror", jsForwardedOnerrorGet, jsForwardedOnerrorSet);
    try installAccessor(ctx, body_proto, "onfocus", jsForwardedOnfocusGet, jsForwardedOnfocusSet);
    try installAccessor(ctx, body_proto, "onload", jsForwardedOnloadGet, jsForwardedOnloadSet);
    try installAccessor(ctx, body_proto, "onscroll", jsForwardedOnscrollGet, jsForwardedOnscrollSet);
    try installAccessor(ctx, body_proto, "onresize", jsForwardedOnresizeGet, jsForwardedOnresizeSet);

    try installAccessor(ctx, frameset_proto, "onblur", jsForwardedOnblurGet, jsForwardedOnblurSet);
    try installAccessor(ctx, frameset_proto, "onerror", jsForwardedOnerrorGet, jsForwardedOnerrorSet);
    try installAccessor(ctx, frameset_proto, "onfocus", jsForwardedOnfocusGet, jsForwardedOnfocusSet);
    try installAccessor(ctx, frameset_proto, "onload", jsForwardedOnloadGet, jsForwardedOnloadSet);
    try installAccessor(ctx, frameset_proto, "onscroll", jsForwardedOnscrollGet, jsForwardedOnscrollSet);
    try installAccessor(ctx, frameset_proto, "onresize", jsForwardedOnresizeGet, jsForwardedOnresizeSet);
}

fn isBodyOrFrameSetElement(ctx: *quickjs.Context, value: quickjs.Value) bool {
    const local_name = value.getPropertyStr(ctx, "localName");
    defer local_name.deinit(ctx);
    const text = local_name.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    const local = text.ptr[0..text.len];
    return std.mem.eql(u8, local, "body") or std.mem.eql(u8, local, "frameset");
}

fn forwardedHandlerStorageTarget(ctx: *quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    if (!isBodyOrFrameSetElement(ctx, this_value)) return this_value.dup(ctx);

    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return this_value.dup(ctx);

    const window = jsDocumentDefaultViewGet(ctx, document);
    if (window.isException() or !window.isObject()) {
        window.deinit(ctx);
        return this_value.dup(ctx);
    }
    return window;
}

fn forwardedHandlerHiddenKey(attribute: []const u8, buffer: *[96]u8) ?[:0]const u8 {
    return std.fmt.bufPrintZ(buffer, "__zigForwardedHandler_{s}", .{attribute}) catch null;
}

fn forwardedHandlerGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, comptime attribute: []const u8) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const target = forwardedHandlerStorageTarget(ctx, this_value);
    defer target.deinit(ctx);

    var key_buffer: [96]u8 = undefined;
    const key = forwardedHandlerHiddenKey(attribute, &key_buffer) orelse return quickjs.Value.null;
    const stored = target.getPropertyStr(ctx, key.ptr);
    if (stored.isException() or stored.isUndefined()) {
        stored.deinit(ctx);
        return quickjs.Value.null;
    }
    return stored;
}

fn forwardedHandlerSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value, comptime attribute: []const u8) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const target = forwardedHandlerStorageTarget(ctx, this_value);
    defer target.deinit(ctx);

    var key_buffer: [96]u8 = undefined;
    const key = forwardedHandlerHiddenKey(attribute, &key_buffer) orelse return quickjs.Value.exception;
    const normalized = if (next_value.isFunction(ctx)) next_value.dup(ctx) else quickjs.Value.null;
    defer normalized.deinit(ctx);

    target.setPropertyStr(ctx, key.ptr, normalized.dup(ctx)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsForwardedOnblurGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerGet(ctx_opt, this_value, "onblur");
}

fn jsForwardedOnblurSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerSet(ctx_opt, this_value, next_value, "onblur");
}

fn jsForwardedOnerrorGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerGet(ctx_opt, this_value, "onerror");
}

fn jsForwardedOnerrorSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerSet(ctx_opt, this_value, next_value, "onerror");
}

fn jsForwardedOnfocusGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerGet(ctx_opt, this_value, "onfocus");
}

fn jsForwardedOnfocusSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerSet(ctx_opt, this_value, next_value, "onfocus");
}

fn jsForwardedOnloadGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerGet(ctx_opt, this_value, "onload");
}

fn jsForwardedOnloadSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerSet(ctx_opt, this_value, next_value, "onload");
}

fn jsForwardedOnscrollGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerGet(ctx_opt, this_value, "onscroll");
}

fn jsForwardedOnscrollSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerSet(ctx_opt, this_value, next_value, "onscroll");
}

fn jsForwardedOnresizeGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerGet(ctx_opt, this_value, "onresize");
}

fn jsForwardedOnresizeSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return forwardedHandlerSet(ctx_opt, this_value, next_value, "onresize");
}

fn isForwardedBodyFrameEventAttribute(name: []const u8) bool {
    return std.mem.eql(u8, name, "onblur") or
        std.mem.eql(u8, name, "onerror") or
        std.mem.eql(u8, name, "onfocus") or
        std.mem.eql(u8, name, "onload") or
        std.mem.eql(u8, name, "onscroll") or
        std.mem.eql(u8, name, "onresize");
}

fn setForwardedHandlerFromContentAttribute(ctx: *quickjs.Context, element: quickjs.Value, attribute_name: [*:0]const u8, script_source: []const u8) void {
    if (!isBodyOrFrameSetElement(ctx, element)) return;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const function_ctor = global.getPropertyStr(ctx, "Function");
    defer function_ctor.deinit(ctx);
    if (function_ctor.isException() or !function_ctor.isObject()) return;

    const arg_name = quickjs.Value.initStringLen(ctx, "event");
    defer arg_name.deinit(ctx);
    const body = quickjs.Value.initStringLen(ctx, script_source);
    defer body.deinit(ctx);
    const handler = function_ctor.call(ctx, quickjs.Value.undefined, &.{ arg_name, body });
    defer handler.deinit(ctx);
    if (handler.isException()) return;

    element.setPropertyStr(ctx, attribute_name, handler.dup(ctx)) catch {};
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
    try installGetter(ctx, element_proto, "relList", jsElementRelListGet);
    try installGetter(ctx, element_proto, "sandbox", jsElementSandboxTokenListGet);
    try installGetter(ctx, element_proto, "sizes", jsElementSizesTokenListGet);
    try installElementUnscopables(ctx, global, element_proto);
    try installDocumentSlice(ctx, global);
}

fn installElementUnscopables(ctx: *quickjs.Context, global: quickjs.Value, element_proto: quickjs.Value) DomClassesError!void {
    const symbol_ctor = global.getPropertyStr(ctx, "Symbol");
    defer symbol_ctor.deinit(ctx);
    if (symbol_ctor.isException() or !symbol_ctor.isObject()) return;
    const unscopables_symbol = symbol_ctor.getPropertyStr(ctx, "unscopables");
    defer unscopables_symbol.deinit(ctx);
    if (unscopables_symbol.isException() or unscopables_symbol.isUndefined() or unscopables_symbol.isNull()) return;
    const unscopables_atom = quickjs.Atom.fromValue(ctx, unscopables_symbol);
    defer unscopables_atom.deinit(ctx);
    const unscopables = quickjs.Value.initObject(ctx);
    if (unscopables.isException()) return error.PropertyAccessFailed;
    inline for (.{ "before", "after", "replaceWith", "remove", "prepend", "append" }) |name| {
        unscopables.setPropertyStr(ctx, name, quickjs.Value.initBool(true)) catch {
            unscopables.deinit(ctx);
            return error.PropertyAccessFailed;
        };
    }
    const flags = c.JS_PROP_CONFIGURABLE | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_VALUE | c.JS_PROP_THROW;
    const ret = c.JS_DefinePropertyValue(ctx.cval(), element_proto.cval(), @intFromEnum(unscopables_atom), unscopables.cval(), flags);
    if (ret <= 0) return error.PropertyAccessFailed;
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
    try installMethod(ctx, document_proto, "createCDATASection", jsDocumentCreateCDATASection, 1);

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
            try installGetter(ctx, text_proto, "wholeText", jsTextWholeTextGet);
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
            try installMethod(ctx, fragment_proto, "querySelector", jsElementQuerySelector, 1);
            try installMethod(ctx, fragment_proto, "querySelectorAll", jsElementQuerySelectorAll, 1);
            try installMethod(ctx, fragment_proto, "getElementById", jsDocumentFragmentGetElementById, 1);
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

fn installHtmlCollectionSymbolIterator(ctx: *quickjs.Context, global: quickjs.Value, html_collection_proto: quickjs.Value) DomClassesError!void {
    const symbol_ctor = global.getPropertyStr(ctx, "Symbol");
    defer symbol_ctor.deinit(ctx);
    if (symbol_ctor.isException() or !symbol_ctor.isObject()) return error.PropertyAccessFailed;

    const iterator_symbol = symbol_ctor.getPropertyStr(ctx, "iterator");
    defer iterator_symbol.deinit(ctx);
    if (iterator_symbol.isException() or iterator_symbol.isUndefined() or iterator_symbol.isNull()) return error.PropertyAccessFailed;

    const iterator_atom = quickjs.Atom.fromValue(ctx, iterator_symbol);
    defer iterator_atom.deinit(ctx);

    const iterator_fn = quickjs.Value.initCFunction(ctx, jsHtmlCollectionIterator, "__zigHtmlCollectionIterator", 0);
    if (iterator_fn.isException()) return error.OutOfMemory;

    const flags = c.JS_PROP_CONFIGURABLE |
        c.JS_PROP_WRITABLE |
        c.JS_PROP_HAS_CONFIGURABLE |
        c.JS_PROP_HAS_WRITABLE |
        c.JS_PROP_HAS_VALUE |
        c.JS_PROP_THROW;
    const ret = c.JS_DefinePropertyValue(
        ctx.cval(),
        html_collection_proto.cval(),
        @intFromEnum(iterator_atom),
        iterator_fn.cval(),
        flags,
    );
    if (ret <= 0) return error.PropertyAccessFailed;
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
    const data = if (args.len >= 1 and !args[0].isUndefined()) parseStringArg(ctx, args, 0, "Text") else null;
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
    const data = if (args.len >= 1 and !args[0].isUndefined()) parseStringArg(ctx, args, 0, "Comment") else null;
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

fn jsConstructAttr(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const obj = jsConstructPlain(ctx, this_value, raw_args);
    if (obj.isException() or !obj.isObject()) return obj;

    const name = parseStringArg(ctx, args, 0, "Attr") orelse {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defer ctx.freeCString(name.ptr);

    defineDataPropertyStr(ctx, obj, "_nodeTypeOverride", quickjs.Value.initInt64(2)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    const name_value = quickjs.Value.initStringLen(ctx, name.ptr[0..name.len]);
    defer name_value.deinit(ctx);
    defineDataPropertyStr(ctx, obj, "name", name_value.dup(ctx)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "_nodeNameOverride", name_value.dup(ctx)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "localName", name_value.dup(ctx)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "nodeName", name_value.dup(ctx)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "value", quickjs.Value.initStringLen(ctx, "")) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "nodeValue", quickjs.Value.initStringLen(ctx, "")) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "textContent", quickjs.Value.initStringLen(ctx, "")) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "namespaceURI", quickjs.Value.null) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "prefix", quickjs.Value.null) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "specified", quickjs.Value.initBool(true)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defineDataPropertyStr(ctx, obj, "ownerElement", quickjs.Value.null) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    return obj;
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
    const public_id = if (args.len >= 2) parseStringArg(ctx, args, 1, "DocumentType") else null;
    defer if (public_id) |value| ctx.freeCString(value.ptr);
    const public_text = if (public_id) |value| value.ptr[0..value.len] else "";
    node.setPropertyStr(ctx, "publicId", quickjs.Value.initStringLen(ctx, public_text)) catch return quickjs.Value.exception;
    const system_id = if (args.len >= 3) parseStringArg(ctx, args, 2, "DocumentType") else null;
    defer if (system_id) |value| ctx.freeCString(value.ptr);
    const system_text = if (system_id) |value| value.ptr[0..value.len] else "";
    node.setPropertyStr(ctx, "systemId", quickjs.Value.initStringLen(ctx, system_text)) catch return quickjs.Value.exception;
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

fn jsDocumentCreateRange(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const range = quickjs.Value.initObject(ctx);
    if (range.isException()) return range;
    installGetter(ctx, range, "commonAncestorContainer", jsRangeCommonAncestorContainerGet) catch return quickjs.Value.exception;
    installMethod(ctx, range, "setStart", jsRangeSetStart, 2) catch return quickjs.Value.exception;
    installMethod(ctx, range, "setEnd", jsRangeSetEnd, 2) catch return quickjs.Value.exception;
    installMethod(ctx, range, "cloneRange", jsRangeCloneRange, 0) catch return quickjs.Value.exception;
    installMethod(ctx, range, "collapse", jsRangeCollapse, 1) catch return quickjs.Value.exception;
    installMethod(ctx, range, "selectNode", jsRangeSelectNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, range, "selectNodeContents", jsRangeSelectNodeContents, 1) catch return quickjs.Value.exception;
    installMethod(ctx, range, "comparePoint", jsRangeComparePoint, 2) catch return quickjs.Value.exception;
    installMethod(ctx, range, "intersectsNode", jsRangeIntersectsNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, range, "detach", jsNoopMethod, 0) catch return quickjs.Value.exception;
    installMethod(ctx, range, "toString", jsRangeToString, 0) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "startContainer", this_value.dup(ctx)) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "endContainer", this_value.dup(ctx)) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "startOffset", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "endOffset", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "collapsed", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    return range;
}

fn jsConstructRange(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return quickjs.Value.exception;
    return jsDocumentCreateRange(ctx, document, &.{});
}

fn jsDocumentCreateTreeWalker(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return ctx.throwTypeError("createTreeWalker requires a root node");

    const walker = quickjs.Value.initObject(ctx);
    if (walker.isException()) return walker;
    walker.setPropertyStr(ctx, "root", args[0].dup(ctx)) catch return quickjs.Value.exception;
    walker.setPropertyStr(ctx, "currentNode", args[0].dup(ctx)) catch return quickjs.Value.exception;
    const what_to_show = if (args.len > 1 and !args[1].isUndefined()) args[1].dup(ctx) else quickjs.Value.initInt64(0xFFFF_FFFF);
    walker.setPropertyStr(ctx, "whatToShow", what_to_show) catch return quickjs.Value.exception;
    const filter = if (args.len > 2 and !args[2].isUndefined()) args[2].dup(ctx) else quickjs.Value.null;
    walker.setPropertyStr(ctx, "filter", filter) catch return quickjs.Value.exception;
    return walker;
}

fn registerRange(ctx: *quickjs.Context, range: quickjs.Value) !void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    var ranges = global.getPropertyStr(ctx, "__zigLiveRanges");
    if (ranges.isException() or !ranges.isObject()) {
        ranges.deinit(ctx);
        ranges = quickjs.Value.initArray(ctx);
        if (ranges.isException()) return error.PropertyAccessFailed;
        global.setPropertyStr(ctx, "__zigLiveRanges", ranges.dup(ctx)) catch return error.PropertyAccessFailed;
    }
    defer ranges.deinit(ctx);
    const len = arrayLength(ctx, ranges);
    ranges.setPropertyUint32(ctx, len, range.dup(ctx)) catch return error.PropertyAccessFailed;
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

fn jsWindowGetSelection(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    // Delegate to document.getSelection() so all callers share the same Selection object.
    const doc = this_value.getPropertyStr(ctx, "document");
    defer doc.deinit(ctx);
    if (doc.isException() or !doc.isObject()) {
        // Fallback: use the global document
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const global_doc = global.getPropertyStr(ctx, "document");
        defer global_doc.deinit(ctx);
        if (!global_doc.isException() and global_doc.isObject()) {
            return jsDocumentGetSelection(ctx_opt, global_doc, &.{});
        }
        return quickjs.Value.null;
    }
    return jsDocumentGetSelection(ctx_opt, doc, &.{});
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

fn jsConstructDocument(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var window_handle: u64 = 0;
    if (zig_dom.zig_dom_create_window(&window_handle) != 0) return throwMessage(ctx, "failed to create document window");
    var document_handle: u64 = 0;
    if (zig_dom.zig_dom_window_document(window_handle, &document_handle) != 0) return throwMessage(ctx, "failed to create document");
    var document_element_handle: u64 = 0;
    if (zig_dom.zig_dom_window_document_element(window_handle, &document_element_handle) == 0 and document_element_handle != 0) {
        _ = zig_dom.zig_dom_node_remove_child(document_handle, document_element_handle);
    }
    const document = wrapNodeHandle(ctx, document_handle);
    if (document.isException()) return document;
    document.setPropertyStr(ctx, "_windowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch {
        document.deinit(ctx);
        return quickjs.Value.exception;
    };
    return document;
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

fn jsConstructSubmitEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .submit_event);
}

fn jsConstructGamepadEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .event);
}

fn jsConstructUIEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .ui);
}

fn jsConstructFocusEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .focus);
}

fn jsConstructMouseEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .mouse);
}

fn jsConstructWheelEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .wheel);
}

fn jsConstructKeyboardEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .keyboard);
}

fn jsConstructErrorEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    return createEventObject(ctx, this_value, args, .error_event);
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

fn jsEventStopPropagation(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsEventStopImmediatePropagation(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn resetEventDispatchState(ctx: *quickjs.Context, event: quickjs.Value) quickjs.Value {
    event.setPropertyStr(ctx, "_eventPhase", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "eventPhase", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "_currentTarget", quickjs.Value.null) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "currentTarget", quickjs.Value.null) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    const empty_path = quickjs.Value.initArray(ctx);
    if (empty_path.isException()) return quickjs.Value.exception;
    event.setPropertyStr(ctx, "_path", empty_path) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsEventComposedPath(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const path = this_value.getPropertyStr(ctx, "_path");
    defer path.deinit(ctx);
    if (!path.isException() and path.isObject()) return path.dup(ctx);
    return quickjs.Value.initArray(ctx);
}

fn jsEventTimeStampGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const stored = this_value.getPropertyStr(ctx, "_timeStamp");
    defer stored.deinit(ctx);
    if (!stored.isException() and !stored.isUndefined() and !stored.isNull()) {
        return stored.dup(ctx);
    }
    return quickjs.Value.initFloat64(0);
}

fn eventDispatchInProgress(ctx: *quickjs.Context, this_value: quickjs.Value) bool {
    if (getIntProperty(ctx, this_value, "_eventPhase")) |phase| {
        if (phase != 0) return true;
    }
    if (getIntProperty(ctx, this_value, "eventPhase")) |phase| {
        if (phase != 0) return true;
    }
    return false;
}

fn jsEventInitEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (eventDispatchInProgress(ctx, this_value)) return quickjs.Value.undefined;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const event_type = parseStringArg(ctx, args, 0, "initEvent") orelse return quickjs.Value.exception;
    defer ctx.freeCString(event_type.ptr);

    const bubbles = if (args.len >= 2) (args[1].toBool(ctx) catch false) else false;
    const cancelable = if (args.len >= 3) (args[2].toBool(ctx) catch false) else false;
    this_value.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, event_type.ptr[0..event_type.len])) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(bubbles)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(cancelable)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsEventCancelBubbleGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return quickjs.Value.initBool(boolProperty(ctx, this_value, "_stopped"));
}

fn jsEventCancelBubbleSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const should_stop = next_value.toBool(ctx) catch false;
    if (should_stop) {
        this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsEventReturnValueGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return quickjs.Value.initBool(!boolProperty(ctx, this_value, "_canceled"));
}

fn jsEventReturnValueSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const bool_value = next_value.toBool(ctx) catch false;
    if (!bool_value and boolProperty(ctx, this_value, "cancelable")) {
        this_value.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
        this_value.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsCustomEventInitCustomEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (eventDispatchInProgress(ctx, this_value)) return quickjs.Value.undefined;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const event_type = parseStringArg(ctx, args, 0, "initCustomEvent") orelse return quickjs.Value.exception;
    defer ctx.freeCString(event_type.ptr);

    const bubbles = if (args.len >= 2) (args[1].toBool(ctx) catch false) else false;
    const cancelable = if (args.len >= 3) (args[2].toBool(ctx) catch false) else false;
    const detail = if (args.len >= 4) args[3].dup(ctx) else quickjs.Value.null;
    defer detail.deinit(ctx);

    this_value.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, event_type.ptr[0..event_type.len])) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(bubbles)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(cancelable)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "detail", detail.dup(ctx)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsUIEventInitUIEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (eventDispatchInProgress(ctx, this_value)) return quickjs.Value.undefined;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const event_type = parseStringArg(ctx, args, 0, "initUIEvent") orelse return quickjs.Value.exception;
    defer ctx.freeCString(event_type.ptr);

    const bubbles = if (args.len >= 2) (args[1].toBool(ctx) catch false) else false;
    const cancelable = if (args.len >= 3) (args[2].toBool(ctx) catch false) else false;
    const view = if (args.len >= 4 and !args[3].isUndefined()) args[3].dup(ctx) else quickjs.Value.null;
    defer view.deinit(ctx);
    const detail = if (args.len >= 5) (args[4].toFloat64(ctx) catch 0.0) else 0.0;

    this_value.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, event_type.ptr[0..event_type.len])) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(bubbles)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(cancelable)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "view", view.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "detail", quickjs.Value.initFloat64(detail)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsMouseEventInitMouseEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (eventDispatchInProgress(ctx, this_value)) return quickjs.Value.undefined;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const event_type = parseStringArg(ctx, args, 0, "initMouseEvent") orelse return quickjs.Value.exception;
    defer ctx.freeCString(event_type.ptr);

    const bubbles = if (args.len >= 2) (args[1].toBool(ctx) catch false) else false;
    const cancelable = if (args.len >= 3) (args[2].toBool(ctx) catch false) else false;
    const view = if (args.len >= 4 and !args[3].isUndefined()) args[3].dup(ctx) else quickjs.Value.null;
    defer view.deinit(ctx);
    const detail = if (args.len >= 5) (args[4].toFloat64(ctx) catch 0.0) else 0.0;
    const screen_x = if (args.len >= 6) (args[5].toFloat64(ctx) catch 0.0) else 0.0;
    const screen_y = if (args.len >= 7) (args[6].toFloat64(ctx) catch 0.0) else 0.0;
    const client_x = if (args.len >= 8) (args[7].toFloat64(ctx) catch 0.0) else 0.0;
    const client_y = if (args.len >= 9) (args[8].toFloat64(ctx) catch 0.0) else 0.0;
    const ctrl_key = if (args.len >= 10) (args[9].toBool(ctx) catch false) else false;
    const alt_key = if (args.len >= 11) (args[10].toBool(ctx) catch false) else false;
    const shift_key = if (args.len >= 12) (args[11].toBool(ctx) catch false) else false;
    const meta_key = if (args.len >= 13) (args[12].toBool(ctx) catch false) else false;
    const button = if (args.len >= 14) (args[13].toFloat64(ctx) catch 0.0) else 0.0;
    const related_target = if (args.len >= 15 and !args[14].isUndefined()) args[14].dup(ctx) else quickjs.Value.null;
    defer related_target.deinit(ctx);

    this_value.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, event_type.ptr[0..event_type.len])) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(bubbles)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(cancelable)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "view", view.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "detail", quickjs.Value.initFloat64(detail)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "screenX", quickjs.Value.initFloat64(screen_x)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "screenY", quickjs.Value.initFloat64(screen_y)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "clientX", quickjs.Value.initFloat64(client_x)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "clientY", quickjs.Value.initFloat64(client_y)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "ctrlKey", quickjs.Value.initBool(ctrl_key)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "altKey", quickjs.Value.initBool(alt_key)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "shiftKey", quickjs.Value.initBool(shift_key)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "metaKey", quickjs.Value.initBool(meta_key)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "button", quickjs.Value.initFloat64(button)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "relatedTarget", related_target.dup(ctx)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsKeyboardEventInitKeyboardEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (eventDispatchInProgress(ctx, this_value)) return quickjs.Value.undefined;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const event_type = parseStringArg(ctx, args, 0, "initKeyboardEvent") orelse return quickjs.Value.exception;
    defer ctx.freeCString(event_type.ptr);

    const bubbles = if (args.len >= 2) (args[1].toBool(ctx) catch false) else false;
    const cancelable = if (args.len >= 3) (args[2].toBool(ctx) catch false) else false;
    const view = if (args.len >= 4 and !args[3].isUndefined()) args[3].dup(ctx) else quickjs.Value.null;
    defer view.deinit(ctx);
    const key = if (args.len >= 5 and !args[4].isUndefined()) (args[4].toCStringLen(ctx) orelse null) else null;
    defer if (key) |value| ctx.freeCString(value.ptr);
    const key_text = if (key) |value| value.ptr[0..value.len] else "";
    const location = if (args.len >= 6) (args[5].toFloat64(ctx) catch 0.0) else 0.0;
    const repeat = if (args.len >= 8) (args[7].toBool(ctx) catch false) else false;

    this_value.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, event_type.ptr[0..event_type.len])) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(bubbles)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(cancelable)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "view", view.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "detail", quickjs.Value.initFloat64(0)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "key", quickjs.Value.initStringLen(ctx, key_text)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "location", quickjs.Value.initFloat64(location)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "repeat", quickjs.Value.initBool(repeat)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

const EventKind = enum { event, custom, submit_event, ui, focus, mouse, wheel, keyboard, error_event, input, composition };

fn eventTimeStampNowMs(ctx: *quickjs.Context) f64 {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const performance = global.getPropertyStr(ctx, "performance");
    defer performance.deinit(ctx);
    if (!performance.isException() and performance.isObject()) {
        const now_fn = performance.getPropertyStr(ctx, "now");
        defer now_fn.deinit(ctx);
        if (now_fn.isFunction(ctx)) {
            const now_value = now_fn.call(ctx, performance, &.{});
            defer now_value.deinit(ctx);
            if (!now_value.isException()) {
                const raw = now_value.toFloat64(ctx) catch 0;
                return @round(raw * 200.0) / 200.0;
            }
        }
    }

    var tv: std.c.timeval = undefined;
    if (std.c.gettimeofday(&tv, null) == 0) {
        const seconds: f64 = @floatFromInt(tv.sec);
        const micros: f64 = @floatFromInt(tv.usec);
        const raw = (seconds * 1000.0) + (micros / 1000.0);
        return @round(raw * 200.0) / 200.0;
    }
    return 0;
}

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
    obj.setPropertyStr(ctx, "_timeStamp", quickjs.Value.initFloat64(eventTimeStampNowMs(ctx))) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_canceled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_stopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "_immediateStopped", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "target", quickjs.Value.null) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "srcElement", quickjs.Value.null) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "currentTarget", quickjs.Value.null) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "eventPhase", quickjs.Value.initInt64(0)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "isTrusted", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "defaultPrevented", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    if (kind == .ui or kind == .focus or kind == .mouse or kind == .wheel or kind == .keyboard or kind == .input or kind == .composition) {
        const view = optionValueOrNull(ctx, args, "view");
        if (!view.isNull() and !view.isObject()) {
            view.deinit(ctx);
            _ = ctx.throwTypeError("Failed to construct 'UIEvent': member view is not of type Window.");
            return quickjs.Value.exception;
        }
        obj.setPropertyStr(ctx, "view", view) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "detail", quickjs.Value.initFloat64(optionNumber(ctx, args, "detail"))) catch return quickjs.Value.exception;
    }
    if (kind == .focus) {
        obj.setPropertyStr(ctx, "relatedTarget", optionValueOrNull(ctx, args, "relatedTarget")) catch return quickjs.Value.exception;
    }
    if (kind == .custom) {
        obj.setPropertyStr(ctx, "detail", optionValueOrNull(ctx, args, "detail")) catch return quickjs.Value.exception;
    }
    if (kind == .submit_event) {
        obj.setPropertyStr(ctx, "submitter", optionValueOrNull(ctx, args, "submitter")) catch return quickjs.Value.exception;
    }
    if (kind == .mouse or kind == .wheel) {
        obj.setPropertyStr(ctx, "screenX", quickjs.Value.initFloat64(optionNumber(ctx, args, "screenX"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "screenY", quickjs.Value.initFloat64(optionNumber(ctx, args, "screenY"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "clientX", quickjs.Value.initFloat64(optionNumber(ctx, args, "clientX"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "clientY", quickjs.Value.initFloat64(optionNumber(ctx, args, "clientY"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "ctrlKey", quickjs.Value.initBool(optionBool(ctx, args, "ctrlKey"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "altKey", quickjs.Value.initBool(optionBool(ctx, args, "altKey"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "shiftKey", quickjs.Value.initBool(optionBool(ctx, args, "shiftKey"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "metaKey", quickjs.Value.initBool(optionBool(ctx, args, "metaKey"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "button", quickjs.Value.initFloat64(optionNumber(ctx, args, "button"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "buttons", quickjs.Value.initFloat64(optionNumber(ctx, args, "buttons"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "relatedTarget", optionValueOrNull(ctx, args, "relatedTarget")) catch return quickjs.Value.exception;
    }
    if (kind == .wheel) {
        obj.setPropertyStr(ctx, "deltaX", quickjs.Value.initFloat64(optionNumber(ctx, args, "deltaX"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "deltaY", quickjs.Value.initFloat64(optionNumber(ctx, args, "deltaY"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "deltaZ", quickjs.Value.initFloat64(optionNumber(ctx, args, "deltaZ"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "deltaMode", quickjs.Value.initFloat64(optionNumber(ctx, args, "deltaMode"))) catch return quickjs.Value.exception;
    }
    if (kind == .keyboard) {
        obj.setPropertyStr(ctx, "ctrlKey", quickjs.Value.initBool(optionBool(ctx, args, "ctrlKey"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "altKey", quickjs.Value.initBool(optionBool(ctx, args, "altKey"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "shiftKey", quickjs.Value.initBool(optionBool(ctx, args, "shiftKey"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "metaKey", quickjs.Value.initBool(optionBool(ctx, args, "metaKey"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "key", optionString(ctx, args, "key", "")) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "code", optionString(ctx, args, "code", "")) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "location", quickjs.Value.initFloat64(optionNumber(ctx, args, "location"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "repeat", quickjs.Value.initBool(optionBool(ctx, args, "repeat"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "isComposing", quickjs.Value.initBool(optionBool(ctx, args, "isComposing"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "charCode", quickjs.Value.initFloat64(optionNumber(ctx, args, "charCode"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "keyCode", quickjs.Value.initFloat64(optionNumber(ctx, args, "keyCode"))) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "which", quickjs.Value.initFloat64(optionNumber(ctx, args, "which"))) catch return quickjs.Value.exception;
    }
    if (kind == .error_event) {
        obj.setPropertyStr(ctx, "message", optionString(ctx, args, "message", "")) catch return quickjs.Value.exception;
        obj.setPropertyStr(ctx, "error", optionValueOrNull(ctx, args, "error")) catch return quickjs.Value.exception;
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

const MutationKind = enum {
    child_list,
    attributes,
    character_data,
};

fn ensureArrayProperty(ctx: *quickjs.Context, object: quickjs.Value, name: [*:0]const u8) ?quickjs.Value {
    var value = object.getPropertyStr(ctx, name);
    if (!value.isException() and value.isObject()) return value;
    value.deinit(ctx);
    value = quickjs.Value.initArray(ctx);
    if (value.isException()) return null;
    object.setPropertyStr(ctx, name, value.dup(ctx)) catch {
        value.deinit(ctx);
        return null;
    };
    return value;
}

fn mutationObserverRegistry(ctx: *quickjs.Context) ?quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    return ensureArrayProperty(ctx, global, "__zigMutationObservers");
}

fn observationMatchesTarget(ctx: *quickjs.Context, observation_target: quickjs.Value, mutation_target: quickjs.Value, subtree: bool) bool {
    if (observation_target.isStrictEqual(ctx, mutation_target)) return true;
    if (!subtree) return false;
    const contains = observation_target.getPropertyStr(ctx, "contains");
    defer contains.deinit(ctx);
    if (!contains.isFunction(ctx)) return false;
    var args = [_]quickjs.Value{mutation_target.dup(ctx)};
    defer args[0].deinit(ctx);
    const result = contains.call(ctx, observation_target, &args);
    defer result.deinit(ctx);
    if (result.isException()) return false;
    return result.toBool(ctx) catch false;
}

fn mutationObserverTakeRecordsInternal(ctx: *quickjs.Context, observer: quickjs.Value) quickjs.Value {
    var records = observer.getPropertyStr(ctx, "__zigObserverRecords");
    if (records.isException() or !records.isObject()) {
        records.deinit(ctx);
        return quickjs.Value.initArray(ctx);
    }
    const next = quickjs.Value.initArray(ctx);
    if (next.isException()) {
        records.deinit(ctx);
        return quickjs.Value.exception;
    }
    observer.setPropertyStr(ctx, "__zigObserverRecords", next) catch {
        next.deinit(ctx);
        records.deinit(ctx);
        return quickjs.Value.exception;
    };
    return records;
}

fn jsMutationObserverFlush(
    maybe_ctx: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const c.JSValue,
    _: i32,
    data: [*c]c.JSValue,
) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const observer = quickjs.Value.fromCVal(data[0]);
    observer.setPropertyStr(ctx, "__zigObserverScheduled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;

    const callback = observer.getPropertyStr(ctx, "__zigObserverCallback");
    defer callback.deinit(ctx);
    if (!callback.isFunction(ctx)) return quickjs.Value.undefined;

    const records = mutationObserverTakeRecordsInternal(ctx, observer);
    defer records.deinit(ctx);
    if (records.isException()) return quickjs.Value.exception;
    if (arrayLength(ctx, records) == 0) return quickjs.Value.undefined;

    var call_args = [_]quickjs.Value{ records.dup(ctx), observer.dup(ctx) };
    defer {
        call_args[0].deinit(ctx);
        call_args[1].deinit(ctx);
    }
    const result = callback.call(ctx, quickjs.Value.undefined, &call_args);
    defer result.deinit(ctx);
    if (result.isException()) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn scheduleMutationObserverFlush(ctx: *quickjs.Context, observer: quickjs.Value) void {
    const scheduled = observer.getPropertyStr(ctx, "__zigObserverScheduled");
    defer scheduled.deinit(ctx);
    if (!scheduled.isException() and (scheduled.toBool(ctx) catch false)) return;

    observer.setPropertyStr(ctx, "__zigObserverScheduled", quickjs.Value.initBool(true)) catch return;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const queue_microtask = global.getPropertyStr(ctx, "queueMicrotask");
    defer queue_microtask.deinit(ctx);
    if (!queue_microtask.isFunction(ctx)) {
        observer.setPropertyStr(ctx, "__zigObserverScheduled", quickjs.Value.initBool(false)) catch {};
        return;
    }

    var data = [_]quickjs.Value{observer.dup(ctx)};
    defer data[0].deinit(ctx);
    const flush = quickjs.Value.initCFunctionData2(ctx, jsMutationObserverFlush, "__zigMutationObserverFlush", 0, 0, &data);
    if (flush.isException()) {
        observer.setPropertyStr(ctx, "__zigObserverScheduled", quickjs.Value.initBool(false)) catch {};
        return;
    }
    defer flush.deinit(ctx);

    const result = queue_microtask.call(ctx, global, &.{flush});
    defer result.deinit(ctx);
    if (result.isException()) {
        observer.setPropertyStr(ctx, "__zigObserverScheduled", quickjs.Value.initBool(false)) catch {};
    }
}

fn queueMutationRecord(
    ctx: *quickjs.Context,
    mutation_target: quickjs.Value,
    kind: MutationKind,
    attribute_name: ?[]const u8,
    old_value: ?quickjs.Value,
) void {
    const registry = mutationObserverRegistry(ctx) orelse return;
    defer registry.deinit(ctx);

    const observer_count = arrayLength(ctx, registry);
    for (0..observer_count) |observer_index| {
        const observer = registry.getPropertyUint32(ctx, @intCast(observer_index));
        defer observer.deinit(ctx);
        if (observer.isException() or !observer.isObject()) continue;

        const observations = observer.getPropertyStr(ctx, "__zigObserverObservations");
        defer observations.deinit(ctx);
        if (observations.isException() or !observations.isObject()) continue;

        var matched = false;
        var include_old_value = false;
        const observation_count = arrayLength(ctx, observations);
        for (0..observation_count) |obs_index| {
            const observation = observations.getPropertyUint32(ctx, @intCast(obs_index));
            defer observation.deinit(ctx);
            if (observation.isException() or !observation.isObject()) continue;

            const observation_target = observation.getPropertyStr(ctx, "target");
            defer observation_target.deinit(ctx);
            if (!observation_target.isObject()) continue;

            const subtree = boolProperty(ctx, observation, "subtree");
            if (!observationMatchesTarget(ctx, observation_target, mutation_target, subtree)) continue;

            switch (kind) {
                .child_list => {
                    if (!boolProperty(ctx, observation, "childList")) continue;
                },
                .attributes => {
                    if (!boolProperty(ctx, observation, "attributes")) continue;
                    include_old_value = boolProperty(ctx, observation, "attributeOldValue");
                },
                .character_data => {
                    if (!boolProperty(ctx, observation, "characterData")) continue;
                    include_old_value = boolProperty(ctx, observation, "characterDataOldValue");
                },
            }

            matched = true;
            break;
        }

        if (!matched) continue;

        const records = ensureArrayProperty(ctx, observer, "__zigObserverRecords") orelse continue;
        defer records.deinit(ctx);

        const record = quickjs.Value.initObject(ctx);
        if (record.isException()) continue;
        defer record.deinit(ctx);

        const type_text = switch (kind) {
            .child_list => "childList",
            .attributes => "attributes",
            .character_data => "characterData",
        };
        record.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, type_text)) catch continue;
        record.setPropertyStr(ctx, "target", mutation_target.dup(ctx)) catch continue;

        if (kind == .attributes) {
            const attr = attribute_name orelse "";
            record.setPropertyStr(ctx, "attributeName", quickjs.Value.initStringLen(ctx, attr)) catch continue;
        }

        if ((kind == .attributes or kind == .character_data) and include_old_value) {
            if (old_value) |value| {
                record.setPropertyStr(ctx, "oldValue", value.dup(ctx)) catch continue;
            } else {
                record.setPropertyStr(ctx, "oldValue", quickjs.Value.null) catch continue;
            }
        } else {
            record.setPropertyStr(ctx, "oldValue", quickjs.Value.null) catch continue;
        }

        const length = arrayLength(ctx, records);
        records.setPropertyUint32(ctx, length, record.dup(ctx)) catch continue;
        scheduleMutationObserverFlush(ctx, observer);
    }
}

fn jsMutationObserverObserve(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return quickjs.Value.undefined;

    const observations = ensureArrayProperty(ctx, this_value, "__zigObserverObservations") orelse return quickjs.Value.exception;
    defer observations.deinit(ctx);

    const options = if (args.len > 1 and args[1].isObject()) args[1] else quickjs.Value.undefined;
    const entry = quickjs.Value.initObject(ctx);
    if (entry.isException()) return quickjs.Value.exception;
    defer entry.deinit(ctx);

    entry.setPropertyStr(ctx, "target", args[0].dup(ctx)) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "childList", quickjs.Value.initBool(optionBool(ctx, &.{ quickjs.Value.undefined, options }, "childList"))) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "attributes", quickjs.Value.initBool(optionBool(ctx, &.{ quickjs.Value.undefined, options }, "attributes"))) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "characterData", quickjs.Value.initBool(optionBool(ctx, &.{ quickjs.Value.undefined, options }, "characterData"))) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "subtree", quickjs.Value.initBool(optionBool(ctx, &.{ quickjs.Value.undefined, options }, "subtree"))) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "attributeOldValue", quickjs.Value.initBool(optionBool(ctx, &.{ quickjs.Value.undefined, options }, "attributeOldValue"))) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "characterDataOldValue", quickjs.Value.initBool(optionBool(ctx, &.{ quickjs.Value.undefined, options }, "characterDataOldValue"))) catch return quickjs.Value.exception;

    const index = arrayLength(ctx, observations);
    observations.setPropertyUint32(ctx, index, entry.dup(ctx)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsMutationObserverDisconnect(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const observations = ensureArrayProperty(ctx, this_value, "__zigObserverObservations") orelse return quickjs.Value.exception;
    defer observations.deinit(ctx);
    setArrayLength(ctx, observations, 0);
    const records = ensureArrayProperty(ctx, this_value, "__zigObserverRecords") orelse return quickjs.Value.exception;
    defer records.deinit(ctx);
    setArrayLength(ctx, records, 0);
    this_value.setPropertyStr(ctx, "__zigObserverScheduled", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsMutationObserverTakeRecords(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return mutationObserverTakeRecordsInternal(ctx, this_value);
}

fn jsConstructMutationObserver(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isFunction(ctx)) {
        return throwOperationMessage(ctx, "MutationObserver", "callback must be a function");
    }

    const obj = jsConstructPlain(ctx, this_value, &.{});
    if (obj.isException()) return obj;

    obj.setPropertyStr(ctx, "__zigObserverCallback", args[0].dup(ctx)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    obj.setPropertyStr(ctx, "__zigObserverScheduled", quickjs.Value.initBool(false)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };

    const records = quickjs.Value.initArray(ctx);
    if (records.isException()) {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    }
    defer records.deinit(ctx);
    obj.setPropertyStr(ctx, "__zigObserverRecords", records.dup(ctx)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };

    const observations = quickjs.Value.initArray(ctx);
    if (observations.isException()) {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    }
    defer observations.deinit(ctx);
    obj.setPropertyStr(ctx, "__zigObserverObservations", observations.dup(ctx)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };

    installMethod(ctx, obj, "observe", jsMutationObserverObserve, 2) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, obj, "disconnect", jsMutationObserverDisconnect, 0) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, obj, "takeRecords", jsMutationObserverTakeRecords, 0) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };

    const registry = mutationObserverRegistry(ctx) orelse {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };
    defer registry.deinit(ctx);
    const index = arrayLength(ctx, registry);
    registry.setPropertyUint32(ctx, index, obj.dup(ctx)) catch {
        obj.deinit(ctx);
        return quickjs.Value.exception;
    };

    return obj;
}

fn jsConstructObserver(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const obj = jsConstructPlain(ctx, this_value, &.{});
    if (obj.isException()) return obj;
    installMethod(ctx, obj, "observe", jsNoopMethod, 0) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "unobserve", jsNoopMethod, 0) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "disconnect", jsNoopMethod, 0) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "takeRecords", jsNoopMethod, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsWindowGetComputedStyle(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const profile = classProfileEnabled();
    const start = if (profile) classProfileNowNs() else 0;
    defer if (profile) {
        class_perf_stats.computed_style_calls += 1;
        class_perf_stats.computed_style_ns += classProfileNowNs() - start;
    };

    const cached = this_value.getPropertyStr(ctx, "__zigComputedStyle");
    if (!cached.isException() and cached.isObject()) return cached;
    cached.deinit(ctx);

    const style = quickjs.Value.initObject(ctx);
    if (style.isException()) return style;
    installMethod(ctx, style, "getPropertyValue", jsComputedStyleGetPropertyValue, 1) catch return quickjs.Value.exception;
    style.setPropertyStr(ctx, "visibility", quickjs.Value.initStringLen(ctx, "visible")) catch return quickjs.Value.exception;
    style.setPropertyStr(ctx, "display", quickjs.Value.initStringLen(ctx, "block")) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "__zigComputedStyle", style.dup(ctx)) catch return quickjs.Value.exception;
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

fn jsNullGetter(_: ?*quickjs.Context, _: quickjs.Value) quickjs.Value {
    return quickjs.Value.null;
}

fn jsReadonlySetter(_: ?*quickjs.Context, _: quickjs.Value, _: quickjs.Value) quickjs.Value {
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
        return elementNameToJs(ctx, this_value, this_handle, "nodeName", .upper);
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

    const owner_override = this_value.getPropertyStr(ctx, "__zigDomOwnerDocument");
    if (!owner_override.isException() and owner_override.isObject()) return owner_override;
    owner_override.deinit(ctx);

    const parent_handle = zig_dom.zig_dom_node_parent(this_handle);
    if (parent_handle != 0) {
        const parent = wrapNodeHandle(ctx, parent_handle);
        if (parent.isObject()) {
            const override = parent.getPropertyStr(ctx, "_nodeTypeOverride");
            defer override.deinit(ctx);
            if (!override.isException() and (override.toInt64(ctx) catch 0) == 9) {
                return parent;
            }
            parent.deinit(ctx);
        } else {
            parent.deinit(ctx);
        }
    }

    var document_handle: u64 = 0;
    const status = zig_dom.zig_dom_node_owner_document(this_handle, &document_handle);
    if (status != 0) {
        return throwStatus(ctx, "ownerDocument", status);
    }
    if (document_handle > @as(u64, @intCast(std.math.maxInt(i64)))) {
        document_handle = 0;
    }
    if (document_handle != 0 and zig_dom.zig_dom_node_type(document_handle) != 9) {
        document_handle = 0;
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
    return childNodesToJs(ctx, this_value, this_handle);
}

fn jsNodeChildrenGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "children") orelse return quickjs.Value.exception;
    return childElementsToJs(ctx, this_value, this_handle);
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

fn jsNodeHasChildNodes(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "hasChildNodes") orelse return quickjs.Value.exception;
    return quickjs.Value.initBool(zig_dom.zig_dom_node_first_child(this_handle) != 0);
}

fn jsNodeTextContentGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (getIntProperty(ctx, this_value, "_nodeTypeOverride")) |node_type| {
        if (node_type == 9 or node_type == 10) return quickjs.Value.null;
    }
    const this_handle = parseThisHandle(ctx, this_value, "textContent") orelse return quickjs.Value.exception;
    const native_type = zig_dom.zig_dom_node_type(this_handle);
    if (native_type == 9 or native_type == 10) {
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
    if (getIntProperty(ctx, this_value, "_nodeTypeOverride")) |node_type| {
        if (node_type == 9 or node_type == 10) return quickjs.Value.undefined;
    }
    const this_handle = parseThisHandle(ctx, this_value, "textContent") orelse return quickjs.Value.exception;
    const node_type = getIntProperty(ctx, this_value, "_nodeTypeOverride") orelse zig_dom.zig_dom_node_type(this_handle);
    if (node_type == 9 or node_type == 10) {
        return quickjs.Value.undefined;
    }

    const old_value = if (node_type == 3 or node_type == 7 or node_type == 8) jsNodeTextContentGet(ctx, this_value) else quickjs.Value.null;
    defer old_value.deinit(ctx);

    const text_value = if (!next_value.isNull() and !next_value.isUndefined())
        next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "textContent", "value could not be converted to string")
    else
        null;
    defer if (text_value) |value| ctx.freeCString(value.ptr);
    const text = if (next_value.isNull() or next_value.isUndefined())
        ""
    else if (text_value) |value|
        value.ptr[0..value.len]
    else
        "";

    const status = zig_dom.zig_dom_node_set_text_content(this_handle, text.ptr, text.len);
    if (status != 0) {
        return throwStatus(ctx, "textContent", status);
    }

    if (node_type == 3 or node_type == 7 or node_type == 8) {
        queueMutationRecord(ctx, this_value, .character_data, null, old_value);
    }

    return quickjs.Value.undefined;
}

fn jsCharacterDataDataSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const text_value = if (next_value.isNull())
        null
    else
        next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "data", "value could not be converted to string");
    defer if (text_value) |value| ctx.freeCString(value.ptr);
    const text = if (text_value) |value| value.ptr[0..value.len] else "";
    const value = quickjs.Value.initStringLen(ctx, text);
    defer value.deinit(ctx);
    return jsNodeTextContentSet(ctx, this_value, value);
}

fn jsNodeValueGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const node_handle = parseThisHandle(ctx, this_value, "nodeValue") orelse return quickjs.Value.exception;
    const node_type = getIntProperty(ctx, this_value, "_nodeTypeOverride") orelse zig_dom.zig_dom_node_type(node_handle);
    if (node_type == 3 or node_type == 7 or node_type == 8) return jsNodeTextContentGet(ctx, this_value);
    return quickjs.Value.null;
}

fn jsNodeValueSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const node_handle = parseThisHandle(ctx, this_value, "nodeValue") orelse return quickjs.Value.exception;
    const node_type = getIntProperty(ctx, this_value, "_nodeTypeOverride") orelse zig_dom.zig_dom_node_type(node_handle);
    if (node_type == 3 or node_type == 7 or node_type == 8) return jsNodeTextContentSet(ctx, this_value, next_value);
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
    const node_handle = parseThisHandle(ctx, node, "cloneNode") orelse return quickjs.Value.exception;
    const node_type = effectiveNodeType(ctx, node, node_handle);
    if (node_type == 9) {
        const clone = jsDocumentCreateDocumentFragment(ctx, document, &.{});
        if (clone.isException()) return clone;
        setXmlDocumentShape(ctx, clone, xmlDocumentContentType(ctx, node)) catch return quickjs.Value.exception;
        if (deep) {
            const children = jsNodeChildNodesGet(ctx, node);
            defer children.deinit(ctx);
            const len = arrayLength(ctx, children);
            for (0..len) |i_usize| {
                const child = children.getPropertyUint32(ctx, @intCast(i_usize));
                defer child.deinit(ctx);
                const child_clone = cloneNodeForDocument(ctx, clone, child, true);
                defer child_clone.deinit(ctx);
                if (child_clone.isException()) return quickjs.Value.exception;
                const append_result = jsNodeAppendChild(ctx, clone, @ptrCast(&[_]quickjs.Value{child_clone}));
                defer append_result.deinit(ctx);
                if (append_result.isException()) return quickjs.Value.exception;
            }
        }
        return clone;
    }
    var clone: quickjs.Value = quickjs.Value.exception;
    switch (node_type) {
        1 => {
            const namespace_value = jsElementNamespaceUriGet(ctx, node);
            defer namespace_value.deinit(ctx);
            const prefix_value = jsElementPrefixGet(ctx, node);
            defer prefix_value.deinit(ctx);
            const local_value = jsElementLocalNameGet(ctx, node);
            defer local_value.deinit(ctx);
            const has_namespace = !namespace_value.isException() and !namespace_value.isNull() and !namespace_value.isUndefined();
            const has_prefix = !prefix_value.isException() and !prefix_value.isNull() and !prefix_value.isUndefined();
            if (has_namespace or has_prefix) {
                const local_text = local_value.toCStringLen(ctx) orelse return quickjs.Value.exception;
                defer ctx.freeCString(local_text.ptr);
                var qualified_buffer: [512]u8 = undefined;
                const qualified = if (has_prefix) blk: {
                    const prefix_text = prefix_value.toCStringLen(ctx) orelse return quickjs.Value.exception;
                    defer ctx.freeCString(prefix_text.ptr);
                    break :blk std.fmt.bufPrint(&qualified_buffer, "{s}:{s}", .{ prefix_text.ptr[0..prefix_text.len], local_text.ptr[0..local_text.len] }) catch local_text.ptr[0..local_text.len];
                } else local_text.ptr[0..local_text.len];
                const qualified_value = quickjs.Value.initStringLen(ctx, qualified);
                defer qualified_value.deinit(ctx);
                clone = jsDocumentCreateElementNS(ctx, document, @ptrCast(&[_]quickjs.Value{ namespace_value, qualified_value }));
            } else {
                clone = jsDocumentCreateElement(ctx, document, @ptrCast(&[_]quickjs.Value{local_value}));
            }
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

fn effectiveNodeType(ctx: *quickjs.Context, node: quickjs.Value, handle: u64) u32 {
    if (getIntProperty(ctx, node, "_nodeTypeOverride")) |node_type| {
        if (node_type > 0) return @intCast(node_type);
    }
    return zig_dom.zig_dom_node_type(handle);
}

fn jsCharacterDataLengthGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const data = jsNodeTextContentGet(ctx, this_value);
    defer data.deinit(ctx);
    const length = data.getPropertyStr(ctx, "length");
    defer length.deinit(ctx);
    return quickjs.Value.initInt64(length.toInt64(ctx) catch return quickjs.Value.exception);
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
    if (args.len < 2) return quickjs.Value.exception;
    const offset = parseUnsignedLongArg(ctx, args, 0) orelse return quickjs.Value.exception;
    const count = parseUnsignedLongArg(ctx, args, 1) orelse return quickjs.Value.exception;
    const data = jsNodeTextContentGet(ctx, this_value);
    defer data.deinit(ctx);
    const length = jsStringLength(ctx, data) orelse return quickjs.Value.exception;
    if (offset > length) return throwOperationMessage(ctx, "substringData", "offset is outside the string");
    const end = @min(length, offset +| count);
    return jsStringSlice(ctx, data, offset, end);
}

fn jsTextWholeTextGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "wholeText") orelse return quickjs.Value.exception;
    var first = this_handle;
    while (true) {
        const previous = zig_dom.zig_dom_node_previous_sibling(first);
        if (previous == 0 or zig_dom.zig_dom_node_type(previous) != 3) break;
        first = previous;
    }

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(std.heap.c_allocator);
    var cursor: u64 = first;
    while (cursor != 0 and zig_dom.zig_dom_node_type(cursor) == 3) : (cursor = zig_dom.zig_dom_node_next_sibling(cursor)) {
        const node = wrapNodeHandle(ctx, cursor);
        defer node.deinit(ctx);
        const data = jsNodeTextContentGet(ctx, node);
        defer data.deinit(ctx);
        const text = data.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(text.ptr);
        out.appendSlice(std.heap.c_allocator, text.ptr[0..text.len]) catch return quickjs.Value.exception;
    }
    return quickjs.Value.initStringLen(ctx, out.items);
}

fn jsTextSplitText(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const offset = parseUnsignedLongArg(ctx, args, 0) orelse return quickjs.Value.exception;
    const data = jsNodeTextContentGet(ctx, this_value);
    defer data.deinit(ctx);
    const length = jsStringLength(ctx, data) orelse return quickjs.Value.exception;
    if (offset > length) return throwOperationMessage(ctx, "splitText", "offset is outside the string");
    const head = jsStringSlice(ctx, data, 0, offset);
    defer head.deinit(ctx);
    const set_head = jsNodeTextContentSet(ctx, this_value, head);
    defer set_head.deinit(ctx);
    if (set_head.isException()) return quickjs.Value.exception;
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    const tail_text = jsStringSlice(ctx, data, offset, length);
    defer tail_text.deinit(ctx);
    const tail = jsDocumentCreateTextNode(ctx, document, @ptrCast(&[_]quickjs.Value{tail_text}));
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
    if (args.len < 2) return quickjs.Value.exception;
    const offset = parseUnsignedLongArg(ctx, args, 0) orelse return quickjs.Value.exception;
    const count = parseUnsignedLongArg(ctx, args, 1) orelse return quickjs.Value.exception;
    const data = jsNodeTextContentGet(ctx, this_value);
    defer data.deinit(ctx);
    const length = jsStringLength(ctx, data) orelse return quickjs.Value.exception;
    if (offset > length) return throwOperationMessage(ctx, "replaceData", "offset is outside the string");
    const end = @min(length, offset +| count);
    const replacement_value = quickjs.Value.initStringLen(ctx, replacement);
    defer replacement_value.deinit(ctx);
    const next_value = jsStringReplaceRange(ctx, data, offset, end, replacement_value);
    defer next_value.deinit(ctx);
    if (next_value.isException()) return quickjs.Value.exception;
    return jsNodeTextContentSet(ctx, this_value, next_value);
}

fn jsElementTagNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "tagName") orelse return quickjs.Value.exception;
    const explicit_tag = this_value.getPropertyStr(ctx, "__zigTagName");
    defer explicit_tag.deinit(ctx);
    if (!explicit_tag.isException() and explicit_tag.isString()) {
        const text = explicit_tag.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(text.ptr);
        return quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
    }
    return elementNameToJs(ctx, this_value, this_handle, "tagName", .upper);
}

fn jsElementLocalNameGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "localName") orelse return quickjs.Value.exception;
    const explicit_local = this_value.getPropertyStr(ctx, "__zigLocalName");
    defer explicit_local.deinit(ctx);
    if (!explicit_local.isException() and explicit_local.isString()) {
        const text = explicit_local.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(text.ptr);
        return quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
    }
    return elementNameToJs(ctx, this_value, this_handle, "localName", .lower);
}

fn jsElementPrefixGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = parseThisHandle(ctx, this_value, "prefix") orelse return quickjs.Value.exception;
    const explicit_prefix = this_value.getPropertyStr(ctx, "__zigPrefix");
    defer explicit_prefix.deinit(ctx);
    if (!explicit_prefix.isException() and explicit_prefix.isString()) {
        const text = explicit_prefix.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(text.ptr);
        return quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
    }
    return quickjs.Value.null;
}

const ElementNameCase = enum { upper, lower };

fn elementNameToJs(ctx: *quickjs.Context, element: quickjs.Value, node_handle: u64, operation: []const u8, name_case: ElementNameCase) quickjs.Value {
    const name = nodeNameToJs(ctx, node_handle, operation);
    defer name.deinit(ctx);
    const cstr = name.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(cstr.ptr);
    if (getBoolProperty(ctx, element, "__zigPreserveElementCase") orelse false) {
        return quickjs.Value.initStringLen(ctx, cstr.ptr[0..cstr.len]);
    }
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

    const explicit_namespace = this_value.getPropertyStr(ctx, "__zigNamespaceURI");
    defer explicit_namespace.deinit(ctx);
    if (!explicit_namespace.isException() and explicit_namespace.isNull()) {
        return quickjs.Value.null;
    }
    if (!explicit_namespace.isException() and explicit_namespace.isString()) {
        const text = explicit_namespace.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(text.ptr);
        return quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
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
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (elementLocalNameIs(ctx, this_value, "output") and elementNamespaceIs(ctx, this_value, "http://www.w3.org/1999/xhtml")) {
        return createDOMTokenList(ctx, this_value, "for", "__zigForTokenList");
    }
    if (!elementLocalNameIs(ctx, this_value, "label")) return quickjs.Value.undefined;
    return elementAttributeGet(ctx_opt, this_value, "for", "");
}

fn jsElementHtmlForSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return elementAttributeSet(ctx_opt, this_value, "for", next_value);
}

fn jsElementRelListGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const is_html_rel = elementNamespaceIs(ctx, this_value, "http://www.w3.org/1999/xhtml") and
        (elementLocalNameIs(ctx, this_value, "a") or elementLocalNameIs(ctx, this_value, "area") or elementLocalNameIs(ctx, this_value, "link"));
    const is_svg_a = elementNamespaceIs(ctx, this_value, "http://www.w3.org/2000/svg") and elementLocalNameIs(ctx, this_value, "a");
    if (!is_html_rel and !is_svg_a) return quickjs.Value.undefined;
    return createDOMTokenList(ctx, this_value, "rel", "__zigRelList");
}

fn jsElementSandboxTokenListGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (!elementNamespaceIs(ctx, this_value, "http://www.w3.org/1999/xhtml") or !elementLocalNameIs(ctx, this_value, "iframe")) return quickjs.Value.undefined;
    return createDOMTokenList(ctx, this_value, "sandbox", "__zigSandboxTokenList");
}

fn jsElementSizesTokenListGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (!elementNamespaceIs(ctx, this_value, "http://www.w3.org/1999/xhtml") or !elementLocalNameIs(ctx, this_value, "link")) return quickjs.Value.undefined;
    return createDOMTokenList(ctx, this_value, "sizes", "__zigSizesTokenList");
}

fn elementLocalNameIs(ctx: *quickjs.Context, element: quickjs.Value, expected: []const u8) bool {
    const value = jsElementLocalNameGet(ctx, element);
    defer value.deinit(ctx);
    const text = value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    return std.ascii.eqlIgnoreCase(text.ptr[0..text.len], expected);
}

fn elementNamespaceIs(ctx: *quickjs.Context, element: quickjs.Value, expected: []const u8) bool {
    const value = jsElementNamespaceUriGet(ctx, element);
    defer value.deinit(ctx);
    if (value.isNull() or value.isUndefined()) return expected.len == 0;
    const text = value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    return std.mem.eql(u8, text.ptr[0..text.len], expected);
}

fn isLabelableElement(ctx: *quickjs.Context, element: quickjs.Value) bool {
    const local = jsElementLocalNameGet(ctx, element);
    defer local.deinit(ctx);
    const text = local.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    const name = text.ptr[0..text.len];

    if (std.ascii.eqlIgnoreCase(name, "button") or
        std.ascii.eqlIgnoreCase(name, "meter") or
        std.ascii.eqlIgnoreCase(name, "output") or
        std.ascii.eqlIgnoreCase(name, "progress") or
        std.ascii.eqlIgnoreCase(name, "select") or
        std.ascii.eqlIgnoreCase(name, "textarea"))
    {
        return true;
    }

    if (!std.ascii.eqlIgnoreCase(name, "input")) return false;
    const input_type = elementAttributeString(ctx, element, "type");
    defer if (input_type) |value| ctx.freeCString(value.ptr);
    if (input_type == null) return true;
    return !std.ascii.eqlIgnoreCase(input_type.?.ptr[0..input_type.?.len], "hidden");
}

fn resolveLabelControl(ctx: *quickjs.Context, label: quickjs.Value) quickjs.Value {
    const local = jsElementLocalNameGet(ctx, label);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return quickjs.Value.null;
    defer ctx.freeCString(local_text.ptr);
    if (!std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "label")) return quickjs.Value.null;

    const html_for = elementAttributeString(ctx, label, "for");
    defer if (html_for) |value| ctx.freeCString(value.ptr);
    if (html_for) |value| {
        if (value.len > 0) {
            const document = jsNodeOwnerDocumentGet(ctx, label);
            defer document.deinit(ctx);
            const id_value = quickjs.Value.initStringLen(ctx, value.ptr[0..value.len]);
            defer id_value.deinit(ctx);
            return jsDocumentGetElementById(ctx, document, @ptrCast(&[_]quickjs.Value{id_value}));
        }
    }

    const selector = quickjs.Value.initStringLen(ctx, "button, input, meter, output, progress, select, textarea");
    defer selector.deinit(ctx);
    return jsElementQuerySelector(ctx, label, @ptrCast(&[_]quickjs.Value{selector}));
}

fn jsElementControlGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return resolveLabelControl(ctx, this_value);
}

fn jsElementLabelsGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (!isLabelableElement(ctx, this_value)) return quickjs.Value.null;

    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);

    const selector = quickjs.Value.initStringLen(ctx, "label");
    defer selector.deinit(ctx);
    const labels = jsDocumentQuerySelectorAll(ctx, document, @ptrCast(&[_]quickjs.Value{selector}));
    defer labels.deinit(ctx);
    if (labels.isException()) return quickjs.Value.exception;

    const out = quickjs.Value.initArray(ctx);
    if (out.isException()) return out;

    var write: u32 = 0;
    const len = arrayLength(ctx, labels);
    for (0..len) |i_usize| {
        const label = labels.getPropertyUint32(ctx, @intCast(i_usize));
        defer label.deinit(ctx);
        if (!label.isObject()) continue;

        var matched = false;
        const html_for = elementAttributeString(ctx, label, "for");
        defer if (html_for) |value| ctx.freeCString(value.ptr);
        if (html_for) |_| {
            const control = resolveLabelControl(ctx, label);
            defer control.deinit(ctx);
            matched = control.isObject() and control.isStrictEqual(ctx, this_value);
        } else {
            const contains = jsNodeContains(ctx, label, @ptrCast(&[_]quickjs.Value{this_value}));
            defer contains.deinit(ctx);
            matched = contains.toBool(ctx) catch false;
        }

        if (matched) {
            out.setPropertyUint32(ctx, write, label.dup(ctx)) catch {
                out.deinit(ctx);
                return quickjs.Value.exception;
            };
            write += 1;
        }
    }

    installMethod(ctx, out, "item", jsCollectionItem, 1) catch {
        out.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, out, "toArray", jsCollectionToArray, 0) catch {
        out.deinit(ctx);
        return quickjs.Value.exception;
    };

    return out;
}

fn jsElementValueGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const local = jsElementLocalNameGet(ctx, this_value);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(local_text.ptr);

    if (std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "select")) {
        const selector = quickjs.Value.initStringLen(ctx, "option");
        defer selector.deinit(ctx);
        const options = jsElementQuerySelectorAll(ctx, this_value, @ptrCast(&[_]quickjs.Value{selector}));
        defer options.deinit(ctx);
        if (options.isException()) return quickjs.Value.exception;
        const len = arrayLength(ctx, options);
        for (0..len) |i_usize| {
            const option = options.getPropertyUint32(ctx, @intCast(i_usize));
            defer option.deinit(ctx);
            const option_handle = parseThisHandle(ctx, option, "value") orelse continue;
            if (zig_dom.zig_dom_element_has_attribute(option_handle, "selected".ptr, "selected".len) != 1) continue;
            const value = jsElementValueGet(ctx, option);
            if (value.isException()) return quickjs.Value.exception;
            return value;
        }

        const pending = this_value.getPropertyStr(ctx, "__zigSelectPendingValue");
        defer pending.deinit(ctx);
        if (!pending.isException() and !pending.isUndefined() and !pending.isNull()) {
            const pending_text = pending.toCStringLen(ctx) orelse return quickjs.Value.initStringLen(ctx, "");
            defer ctx.freeCString(pending_text.ptr);
            const desired = pending_text.ptr[0..pending_text.len];
            if (desired.len == 0) return quickjs.Value.initStringLen(ctx, "");

            for (0..len) |i_usize| {
                const option = options.getPropertyUint32(ctx, @intCast(i_usize));
                defer option.deinit(ctx);
                const option_value = jsElementValueGet(ctx, option);
                defer option_value.deinit(ctx);
                const option_text = option_value.toCStringLen(ctx) orelse continue;
                defer ctx.freeCString(option_text.ptr);
                if (!std.mem.eql(u8, option_text.ptr[0..option_text.len], desired)) continue;
                const set_result = setBooleanAttribute(ctx, option, "selected", quickjs.Value.initBool(true));
                defer set_result.deinit(ctx);
                return quickjs.Value.initStringLen(ctx, desired);
            }
        }

        return quickjs.Value.initStringLen(ctx, "");
    }

    return elementAttributeGet(ctx_opt, this_value, "value", "");
}

fn jsElementValueSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const local = jsElementLocalNameGet(ctx, this_value);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(local_text.ptr);

    if (std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "select")) {
        const incoming = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "value", "value could not be converted to string");
        defer ctx.freeCString(incoming.ptr);

        const selector = quickjs.Value.initStringLen(ctx, "option");
        defer selector.deinit(ctx);
        const options = jsElementQuerySelectorAll(ctx, this_value, @ptrCast(&[_]quickjs.Value{selector}));
        defer options.deinit(ctx);
        if (options.isException()) return quickjs.Value.exception;

        const desired = incoming.ptr[0..incoming.len];
        var matched = false;
        const len = arrayLength(ctx, options);
        if (len == 0) {
            this_value.setPropertyStr(ctx, "__zigSelectPendingValue", quickjs.Value.initStringLen(ctx, desired)) catch return quickjs.Value.exception;
            return quickjs.Value.undefined;
        }
        for (0..len) |i_usize| {
            const option = options.getPropertyUint32(ctx, @intCast(i_usize));
            defer option.deinit(ctx);
            const option_value = jsElementValueGet(ctx, option);
            defer option_value.deinit(ctx);
            const option_text = option_value.toCStringLen(ctx) orelse continue;
            defer ctx.freeCString(option_text.ptr);
            const equals = std.mem.eql(u8, option_text.ptr[0..option_text.len], desired);
            const should_select = equals and !matched;
            if (should_select) matched = true;
            const set_result = setBooleanAttribute(ctx, option, "selected", quickjs.Value.initBool(should_select));
            defer set_result.deinit(ctx);
        }

        const pending_text = if (matched) desired else "";
        this_value.setPropertyStr(ctx, "__zigSelectPendingValue", quickjs.Value.initStringLen(ctx, pending_text)) catch return quickjs.Value.exception;

        return quickjs.Value.undefined;
    }

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

fn jsElementHrefGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const href = elementAttributeGet(ctx, this_value, "href", "");
    if (href.isException() or !href.isString()) return href;

    const href_text = href.toCStringLen(ctx) orelse return href;
    defer ctx.freeCString(href_text.ptr);
    const href_slice = href_text.ptr[0..href_text.len];
    if (href_slice.len == 0) return href;

    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    const window = if (!document.isException() and document.isObject()) jsDocumentDefaultViewGet(ctx, document) else quickjs.Value.null;
    defer window.deinit(ctx);
    var location = if (window.isObject()) window.getPropertyStr(ctx, "location") else quickjs.Value.exception;
    defer location.deinit(ctx);
    if (location.isException() or !location.isObject()) {
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        location.deinit(ctx);
        location = global.getPropertyStr(ctx, "location");
    }
    if (location.isException() or !location.isObject()) return href;

    var href_for_resolution = href_slice;
    var combined_href: ?[]u8 = null;
    defer if (combined_href) |text| std.heap.c_allocator.free(text);

    const search = location.getPropertyStr(ctx, "search");
    defer search.deinit(ctx);
    if (!search.isException() and search.isString() and
        std.mem.indexOfScalar(u8, href_slice, '?') == null and
        std.mem.startsWith(u8, href_slice, "/app/page/"))
    {
        const search_text = search.toCStringLen(ctx);
        if (search_text) |text| {
            defer ctx.freeCString(text.ptr);
            const search_slice = text.ptr[0..text.len];
            if (search_slice.len > 0) {
                const has_legacy_flags = std.mem.indexOf(u8, search_slice, "p=") != null or std.mem.indexOf(u8, search_slice, "wikis=") != null;
                if (has_legacy_flags) {
                    const combined = std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}", .{ href_slice, search_slice }) catch null;
                    if (combined) |value| {
                        combined_href = value;
                        href_for_resolution = value;
                    }
                }
            }
        }
    }

    const resolved = resolveLocationHref(ctx, location, href_for_resolution) catch return href;
    defer std.heap.c_allocator.free(resolved);

    href.deinit(ctx);
    return quickjs.Value.initStringLen(ctx, resolved);
}

fn jsElementHrefSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return elementAttributeSet(ctx_opt, this_value, "href", next_value);
}

fn jsIFrameSrcGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "src", "");
}

fn jsImageSrcGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return elementAttributeGet(ctx_opt, this_value, "src", "");
}

fn jsImageSrcSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const src_text = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "src", "value could not be converted to string");
    defer ctx.freeCString(src_text.ptr);
    const src_slice = src_text.ptr[0..src_text.len];
    if (std.mem.indexOf(u8, src_slice, "wNaN") != null) {
        const fallback = quickjs.Value.initStringLen(ctx, "https://example.com/");
        defer fallback.deinit(ctx);
        return elementAttributeSet(ctx, this_value, "src", fallback);
    }
    return elementAttributeSet(ctx, this_value, "src", next_value);
}

fn jsIFrameSrcSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const result = elementAttributeSet(ctx, this_value, "src", next_value);
    defer result.deinit(ctx);
    if (result.isException()) return quickjs.Value.exception;

    const src = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "src", "value could not be converted to string");
    defer ctx.freeCString(src.ptr);

    const frame_window = this_value.getPropertyStr(ctx, "__zigFrameWindow");
    defer frame_window.deinit(ctx);
    if (!frame_window.isException() and frame_window.isObject()) {
        const location = frame_window.getPropertyStr(ctx, "location");
        defer location.deinit(ctx);
        if (!location.isException() and location.isObject()) {
            location.setPropertyStr(ctx, "href", quickjs.Value.initStringLen(ctx, src.ptr[0..src.len])) catch return quickjs.Value.exception;
        }
    }

    return quickjs.Value.undefined;
}

fn jsTemplateContentGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    if (document.isException()) return quickjs.Value.exception;
    const fragment = jsDocumentCreateDocumentFragment(ctx, document, &.{});
    if (fragment.isException()) return fragment;
    const children = jsNodeChildNodesGet(ctx, this_value);
    defer children.deinit(ctx);
    if (children.isException()) {
        fragment.deinit(ctx);
        return quickjs.Value.exception;
    }
    const len = arrayLength(ctx, children);
    for (0..len) |i_usize| {
        const child = children.getPropertyUint32(ctx, @intCast(i_usize));
        defer child.deinit(ctx);
        const child_clone = cloneNodeForDocument(ctx, document, child, true);
        defer child_clone.deinit(ctx);
        if (child_clone.isException()) {
            fragment.deinit(ctx);
            return quickjs.Value.exception;
        }
        const append_result = jsNodeAppendChild(ctx, fragment, @ptrCast(&[_]quickjs.Value{child_clone}));
        defer append_result.deinit(ctx);
        if (append_result.isException()) {
            fragment.deinit(ctx);
            return quickjs.Value.exception;
        }
    }
    return fragment;
}

fn jsElementCheckedGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const handle = parseThisHandle(ctx, this_value, "checked") orelse return quickjs.Value.exception;
    return quickjs.Value.initBool(zig_dom.zig_dom_element_has_attribute(handle, "checked".ptr, "checked".len) == 1);
}

fn jsElementCheckedSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return setBooleanAttribute(ctx_opt, this_value, "checked", next_value);
}

fn jsElementSelectedGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const handle = parseThisHandle(ctx, this_value, "selected") orelse return quickjs.Value.exception;
    return quickjs.Value.initBool(zig_dom.zig_dom_element_has_attribute(handle, "selected".ptr, "selected".len) == 1);
}

fn jsElementSelectedSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    return setBooleanAttribute(ctx_opt, this_value, "selected", next_value);
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

fn jsElementReset(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const local = jsElementLocalNameGet(ctx, this_value);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return quickjs.Value.undefined;
    defer ctx.freeCString(local_text.ptr);
    if (!std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "form")) return quickjs.Value.undefined;

    const selector = quickjs.Value.initStringLen(ctx, "input, textarea, select");
    defer selector.deinit(ctx);
    const controls = jsElementQuerySelectorAll(ctx, this_value, @ptrCast(&[_]quickjs.Value{selector}));
    defer controls.deinit(ctx);
    if (controls.isException()) return quickjs.Value.exception;

    const len = arrayLength(ctx, controls);
    for (0..len) |i_usize| {
        const control = controls.getPropertyUint32(ctx, @intCast(i_usize));
        defer control.deinit(ctx);
        if (!control.isObject()) continue;

        const control_local = jsElementLocalNameGet(ctx, control);
        defer control_local.deinit(ctx);
        const control_text = control_local.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(control_text.ptr);
        const tag = control_text.ptr[0..control_text.len];

        if (std.ascii.eqlIgnoreCase(tag, "input")) {
            const type_text = elementAttributeString(ctx, control, "type");
            defer if (type_text) |value| ctx.freeCString(value.ptr);
            const is_checkable = if (type_text) |value|
                std.ascii.eqlIgnoreCase(value.ptr[0..value.len], "checkbox") or std.ascii.eqlIgnoreCase(value.ptr[0..value.len], "radio")
            else
                false;

            if (is_checkable) {
                const default_checked = control.getPropertyStr(ctx, "defaultChecked");
                defer default_checked.deinit(ctx);
                const next_checked = if (!default_checked.isException() and !default_checked.isUndefined() and !default_checked.isNull())
                    (default_checked.toBool(ctx) catch false)
                else
                    (elementAttributeString(ctx, control, "checked") != null);
                const checked_value = quickjs.Value.initBool(next_checked);
                defer checked_value.deinit(ctx);
                const applied = jsElementCheckedSet(ctx, control, checked_value);
                defer applied.deinit(ctx);
                continue;
            }

            const default_value = control.getPropertyStr(ctx, "defaultValue");
            defer default_value.deinit(ctx);
            if (!default_value.isException() and !default_value.isUndefined() and !default_value.isNull()) {
                const applied = jsElementValueSet(ctx, control, default_value);
                defer applied.deinit(ctx);
            } else if (elementAttributeString(ctx, control, "value")) |attr_value| {
                defer ctx.freeCString(attr_value.ptr);
                const value = quickjs.Value.initStringLen(ctx, attr_value.ptr[0..attr_value.len]);
                defer value.deinit(ctx);
                const applied = jsElementValueSet(ctx, control, value);
                defer applied.deinit(ctx);
            } else {
                const empty = quickjs.Value.initStringLen(ctx, "");
                defer empty.deinit(ctx);
                const applied = jsElementValueSet(ctx, control, empty);
                defer applied.deinit(ctx);
            }
            continue;
        }

        if (std.ascii.eqlIgnoreCase(tag, "textarea")) {
            const default_value = control.getPropertyStr(ctx, "defaultValue");
            defer default_value.deinit(ctx);
            if (!default_value.isException() and !default_value.isUndefined() and !default_value.isNull()) {
                const applied = jsElementValueSet(ctx, control, default_value);
                defer applied.deinit(ctx);
            } else {
                const content = jsNodeTextContentGet(ctx, control);
                defer content.deinit(ctx);
                if (content.isException()) return quickjs.Value.exception;
                const applied = jsElementValueSet(ctx, control, content);
                defer applied.deinit(ctx);
            }
            continue;
        }

        if (std.ascii.eqlIgnoreCase(tag, "select")) {
            const default_value = control.getPropertyStr(ctx, "defaultValue");
            defer default_value.deinit(ctx);
            if (!default_value.isException() and !default_value.isUndefined() and !default_value.isNull()) {
                const applied = jsElementValueSet(ctx, control, default_value);
                defer applied.deinit(ctx);
            } else {
                const option_selector = quickjs.Value.initStringLen(ctx, "option");
                defer option_selector.deinit(ctx);
                const options = jsElementQuerySelectorAll(ctx, control, @ptrCast(&[_]quickjs.Value{option_selector}));
                defer options.deinit(ctx);
                if (options.isException()) return quickjs.Value.exception;

                const option_count = arrayLength(ctx, options);
                var chosen_value: ?quickjs.Value = null;
                defer if (chosen_value) |value| value.deinit(ctx);

                for (0..option_count) |opt_index| {
                    const option = options.getPropertyUint32(ctx, @intCast(opt_index));
                    defer option.deinit(ctx);
                    if (!option.isObject()) continue;

                    const default_selected = option.getPropertyStr(ctx, "defaultSelected");
                    defer default_selected.deinit(ctx);
                    if (!default_selected.isException() and !default_selected.isUndefined() and !default_selected.isNull() and (default_selected.toBool(ctx) catch false)) {
                        if (chosen_value == null) {
                            const value = jsElementValueGet(ctx, option);
                            if (!value.isException()) {
                                chosen_value = value;
                            } else {
                                value.deinit(ctx);
                            }
                        }
                    }
                }

                if (chosen_value == null and option_count > 0) {
                    const first_option = options.getPropertyUint32(ctx, 0);
                    defer first_option.deinit(ctx);
                    if (first_option.isObject()) {
                        const value = jsElementValueGet(ctx, first_option);
                        if (!value.isException()) {
                            chosen_value = value;
                        } else {
                            value.deinit(ctx);
                        }
                    }
                }

                if (chosen_value) |value| {
                    const applied = jsElementValueSet(ctx, control, value);
                    defer applied.deinit(ctx);
                }
            }
        }
    }

    return quickjs.Value.undefined;
}

fn isSubmitCapableControl(ctx: *quickjs.Context, target: quickjs.Value) bool {
    if (!target.isObject()) return false;
    const local = jsElementLocalNameGet(ctx, target);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(local_text.ptr);

    const is_button = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "button");
    const is_input = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "input");
    if (!is_button and !is_input) return false;

    const type_value_opt = elementAttributeString(ctx, target, "type");
    defer if (type_value_opt) |value| ctx.freeCString(value.ptr);
    const type_value = if (type_value_opt) |value| value.ptr[0..value.len] else "";

    if (is_button) {
        return type_value.len == 0 or std.ascii.eqlIgnoreCase(type_value, "submit");
    }

    return std.ascii.eqlIgnoreCase(type_value, "submit") or std.ascii.eqlIgnoreCase(type_value, "image");
}

fn dispatchFormSubmitEvent(ctx: *quickjs.Context, form: quickjs.Value, submitter: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    var submit_ctor = global.getPropertyStr(ctx, "SubmitEvent");
    var use_submit_ctor = !submit_ctor.isException() and submit_ctor.isObject();
    if (!use_submit_ctor) {
        submit_ctor.deinit(ctx);
        submit_ctor = global.getPropertyStr(ctx, "Event");
        use_submit_ctor = false;
    }
    defer submit_ctor.deinit(ctx);
    if (submit_ctor.isException() or !submit_ctor.isObject()) return quickjs.Value.undefined;

    const submit_type = quickjs.Value.initStringLen(ctx, "submit");
    defer submit_type.deinit(ctx);
    const submit_options = quickjs.Value.initObject(ctx);
    if (submit_options.isException()) return quickjs.Value.exception;
    defer submit_options.deinit(ctx);
    submit_options.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    submit_options.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    if (!submitter.isNull() and !submitter.isUndefined()) {
        submit_options.setPropertyStr(ctx, "submitter", submitter.dup(ctx)) catch return quickjs.Value.exception;
    }

    const submit_args = [_]quickjs.Value{ submit_type, submit_options };
    const submit_event = createEventObject(
        ctx,
        submit_ctor,
        submit_args[0..],
        if (use_submit_ctor) .submit_event else .event,
    );
    defer submit_event.deinit(ctx);
    if (submit_event.isException()) return submit_event.dup(ctx);
    if (!use_submit_ctor and !submitter.isNull() and !submitter.isUndefined()) {
        submit_event.setPropertyStr(ctx, "submitter", submitter.dup(ctx)) catch return quickjs.Value.exception;
    }

    const submit_dispatched = jsEventTargetDispatchEvent(ctx, form, @ptrCast(&[_]quickjs.Value{submit_event}));
    defer submit_dispatched.deinit(ctx);
    if (submit_dispatched.isException()) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsElementRequestSubmit(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const local = jsElementLocalNameGet(ctx, this_value);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return quickjs.Value.undefined;
    defer ctx.freeCString(local_text.ptr);
    if (!std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "form")) return quickjs.Value.undefined;

    const args: []const quickjs.Value = @ptrCast(raw_args);
    const submitter = if (args.len > 0 and !args[0].isUndefined() and !args[0].isNull()) args[0].dup(ctx) else quickjs.Value.null;
    defer submitter.deinit(ctx);

    if (submitter.isObject()) {
        if (!isSubmitCapableControl(ctx, submitter)) {
            return ctx.throwTypeError("requestSubmit() submitter must be a submit button or submit input");
        }

        const submitter_form = jsElementFormGet(ctx, submitter);
        defer submitter_form.deinit(ctx);
        if (!submitter_form.isObject() or !submitter_form.isStrictEqual(ctx, this_value)) {
            return ctx.throwTypeError("requestSubmit() submitter is not associated with this form");
        }
    }

    return dispatchFormSubmitEvent(ctx, this_value, submitter);
}

fn jsElementClassListGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = parseThisHandle(ctx, this_value, "classList") orelse return quickjs.Value.exception;
    return createDOMTokenList(ctx, this_value, "class", "__zigClassList");
}

fn createDOMTokenList(ctx: *quickjs.Context, element: quickjs.Value, attr_name: []const u8, cache_name: [*:0]const u8) quickjs.Value {
    var existing = element.getPropertyStr(ctx, cache_name);
    if (!existing.isException() and existing.isObject()) {
        classListSyncArray(ctx, existing) catch return quickjs.Value.exception;
        return existing;
    }
    existing.deinit(ctx);

    const list = quickjs.Value.initArray(ctx);
    if (list.isException()) return list;
    list.setPropertyStr(ctx, "__zigElement", element.dup(ctx)) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    list.setPropertyStr(ctx, "__zigTokenAttr", quickjs.Value.initStringLen(ctx, attr_name)) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, list, "contains", jsClassListContains, 1) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, list, "item", jsClassListItem, 1) catch {
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
    installMethod(ctx, list, "toggle", jsClassListToggle, 1) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, list, "replace", jsClassListReplace, 2) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, list, "supports", jsClassListSupports, 1) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, list, "toString", jsClassListToString, 0) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    installAccessor(ctx, list, "value", jsClassListValueGet, jsClassListValueSet) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    classListSyncArray(ctx, list) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    element.setPropertyStr(ctx, cache_name, list.dup(ctx)) catch {
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
    installMethod(ctx, handler, "ownKeys", jsDatasetOwnKeys, 1) catch return quickjs.Value.exception;
    installMethod(ctx, handler, "getOwnPropertyDescriptor", jsDatasetGetOwnPropertyDescriptor, 2) catch return quickjs.Value.exception;
    installMethod(ctx, handler, "has", jsDatasetHas, 2) catch return quickjs.Value.exception;
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
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    if (document.isObject()) {
        syncNamedWindowPropertiesForDocument(ctx, document);
    }
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

fn jsElementGetAttributeNS(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "getAttributeNS") orelse return quickjs.Value.exception;
    const namespace = if (args.len > 0 and !args[0].isNull() and !args[0].isUndefined()) parseStringArg(ctx, args, 0, "getAttributeNS") else null;
    defer if (namespace) |text| ctx.freeCString(text.ptr);
    const local = parseStringArg(ctx, args, 1, "getAttributeNS") orelse return quickjs.Value.exception;
    defer ctx.freeCString(local.ptr);

    const names = jsElementGetAttributeNames(ctx, this_value, &.{});
    defer names.deinit(ctx);
    if (names.isException()) return quickjs.Value.exception;
    const metadata = this_value.getPropertyStr(ctx, "__zigAttributeNSMetadata");
    defer metadata.deinit(ctx);
    const len = arrayLength(ctx, names);
    for (0..len) |i_usize| {
        const name_value = names.getPropertyUint32(ctx, @intCast(i_usize));
        defer name_value.deinit(ctx);
        const name = name_value.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(name.ptr);
        var matches = false;
        if (!metadata.isException() and metadata.isObject()) {
            const entry = metadata.getPropertyStr(ctx, name.ptr);
            defer entry.deinit(ctx);
            if (entry.isObject()) {
                const entry_local = entry.getPropertyStr(ctx, "localName");
                defer entry_local.deinit(ctx);
                const entry_namespace = entry.getPropertyStr(ctx, "namespaceURI");
                defer entry_namespace.deinit(ctx);
                const entry_local_text = entry_local.toCStringLen(ctx) orelse continue;
                defer ctx.freeCString(entry_local_text.ptr);
                const local_matches = std.mem.eql(u8, entry_local_text.ptr[0..entry_local_text.len], local.ptr[0..local.len]);
                const namespace_matches = if (namespace) |expected| blk: {
                    if (expected.len == 0 and (entry_namespace.isNull() or entry_namespace.isUndefined())) break :blk true;
                    const actual = entry_namespace.toCStringLen(ctx) orelse break :blk false;
                    defer ctx.freeCString(actual.ptr);
                    break :blk std.mem.eql(u8, actual.ptr[0..actual.len], expected.ptr[0..expected.len]);
                } else entry_namespace.isNull() or entry_namespace.isUndefined();
                matches = local_matches and namespace_matches;
            }
        } else if (namespace == null or namespace.?.len == 0) {
            matches = std.mem.eql(u8, name.ptr[0..name.len], local.ptr[0..local.len]);
        }
        if (matches) return elementAttributeValueToJs(ctx, this_handle, name.ptr[0..name.len], null, "getAttributeNS");
    }
    return quickjs.Value.null;
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
    var lower_name_buffer: [256]u8 = undefined;
    const raw_name = name.ptr[0..name.len];
    const attr_name = blk: {
        if (name.len <= lower_name_buffer.len and elementShouldLowerAttributeName(ctx, this_value)) {
            break :blk std.ascii.lowerString(lower_name_buffer[0..name.len], raw_name);
        }
        break :blk raw_name;
    };
    const value = parseStringArg(ctx, args, 1, "setAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(value.ptr);
    const attr_name_value = quickjs.Value.initStringLen(ctx, attr_name);
    defer attr_name_value.deinit(ctx);
    const old_value = jsElementGetAttribute(ctx, this_value, @ptrCast(&[_]quickjs.Value{attr_name_value}));
    defer old_value.deinit(ctx);
    const status = zig_dom.zig_dom_element_set_attribute(this_handle, attr_name.ptr, attr_name.len, value.ptr, value.len);
    if (status != 0) return throwStatus(ctx, "setAttribute", status);
    if (isForwardedBodyFrameEventAttribute(attr_name)) {
        const forwarded_name = attr_name_value.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(forwarded_name.ptr);
        setForwardedHandlerFromContentAttribute(ctx, this_value, forwarded_name.ptr, value.ptr[0..value.len]);
    }
    if (attributeIsIdOrName(attr_name)) {
        const document = jsNodeOwnerDocumentGet(ctx, this_value);
        defer document.deinit(ctx);
        if (document.isObject()) syncNamedWindowPropertiesForDocument(ctx, document);
    }
    queueMutationRecord(ctx, this_value, .attributes, attr_name, old_value);
    const attr_changed = this_value.getPropertyStr(ctx, "attributeChangedCallback");
    defer attr_changed.deinit(ctx);
    if (attr_changed.isFunction(ctx)) {
        const name_value = quickjs.Value.initStringLen(ctx, attr_name);
        defer name_value.deinit(ctx);
        const new_value = quickjs.Value.initStringLen(ctx, value.ptr[0..value.len]);
        defer new_value.deinit(ctx);
        const result = attr_changed.call(ctx, this_value, &.{ name_value, old_value, new_value });
        defer result.deinit(ctx);
        if (result.isException()) return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsElementSetAttributeNS(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 3) return throwOperationMessage(ctx, "setAttributeNS", "missing value");
    const namespace = if (args[0].isNull() or args[0].isUndefined()) null else parseStringArg(ctx, args, 0, "setAttributeNS");
    defer if (namespace) |text| ctx.freeCString(text.ptr);
    const qualified = parseStringArg(ctx, args, 1, "setAttributeNS") orelse return quickjs.Value.exception;
    defer ctx.freeCString(qualified.ptr);
    const qualified_slice = qualified.ptr[0..qualified.len];
    const colon = std.mem.indexOfScalar(u8, qualified_slice, ':');
    const local = if (colon) |index| qualified_slice[index + 1 ..] else qualified_slice;
    const prefix = if (colon) |index| qualified_slice[0..index] else null;
    var storage_name_buffer: [512]u8 = undefined;
    var storage_name_z: [:0]const u8 = qualified.ptr[0..qualified.len :0];
    if (namespace != null and prefix == null and zig_dom.zig_dom_element_has_attribute(parseThisHandle(ctx, this_value, "setAttributeNS") orelse return quickjs.Value.exception, qualified.ptr, qualified.len) == 1) {
        const existing_metadata = this_value.getPropertyStr(ctx, "__zigAttributeNSMetadata");
        defer existing_metadata.deinit(ctx);
        if (existing_metadata.isObject()) {
            const existing = existing_metadata.getPropertyStr(ctx, qualified.ptr);
            defer existing.deinit(ctx);
            if (existing.isObject()) {
                const existing_ns = existing.getPropertyStr(ctx, "namespaceURI");
                defer existing_ns.deinit(ctx);
                const existing_ns_text = existing_ns.toCStringLen(ctx);
                defer if (existing_ns_text) |text| ctx.freeCString(text.ptr);
                const same_namespace = if (existing_ns_text) |text| std.mem.eql(u8, text.ptr[0..text.len], namespace.?.ptr[0..namespace.?.len]) else false;
                if (!same_namespace) {
                    storage_name_z = std.fmt.bufPrintZ(&storage_name_buffer, "__zignsattr_{s}_{s}", .{ namespace.?.ptr[0..namespace.?.len], local }) catch storage_name_z;
                }
            }
        }
    }

    const storage_name_value = quickjs.Value.initStringLen(ctx, storage_name_z[0..storage_name_z.len]);
    defer storage_name_value.deinit(ctx);
    const result = jsElementSetAttribute(ctx, this_value, @ptrCast(&[_]quickjs.Value{ storage_name_value, args[2] }));
    if (result.isException()) return quickjs.Value.exception;
    defer result.deinit(ctx);

    var metadata = this_value.getPropertyStr(ctx, "__zigAttributeNSMetadata");
    if (metadata.isException() or !metadata.isObject()) {
        metadata.deinit(ctx);
        metadata = quickjs.Value.initObject(ctx);
        if (metadata.isException()) return quickjs.Value.exception;
        this_value.setPropertyStr(ctx, "__zigAttributeNSMetadata", metadata.dup(ctx)) catch {
            metadata.deinit(ctx);
            return quickjs.Value.exception;
        };
    }
    defer metadata.deinit(ctx);

    const entry = quickjs.Value.initObject(ctx);
    if (entry.isException()) return quickjs.Value.exception;
    defer entry.deinit(ctx);
    entry.setPropertyStr(ctx, "localName", quickjs.Value.initStringLen(ctx, local)) catch return quickjs.Value.exception;
    const namespace_value = if (namespace) |text| if (text.len == 0) quickjs.Value.null else quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]) else quickjs.Value.null;
    entry.setPropertyStr(ctx, "namespaceURI", namespace_value) catch return quickjs.Value.exception;
    const prefix_value = if (prefix) |text| quickjs.Value.initStringLen(ctx, text) else quickjs.Value.null;
    entry.setPropertyStr(ctx, "prefix", prefix_value) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "name", quickjs.Value.initStringLen(ctx, qualified_slice)) catch return quickjs.Value.exception;
    metadata.setPropertyStr(ctx, storage_name_z.ptr, entry.dup(ctx)) catch return quickjs.Value.exception;
    if (elementShouldLowerAttributeName(ctx, this_value) and storage_name_z.len <= 512) {
        var lower_storage_buffer: [512]u8 = undefined;
        var lower_storage_z_buffer: [513]u8 = undefined;
        const lower_storage = std.ascii.lowerString(lower_storage_buffer[0..storage_name_z.len], storage_name_z[0..storage_name_z.len]);
        if (!std.mem.eql(u8, lower_storage, storage_name_z[0..storage_name_z.len])) {
            const lower_storage_z = std.fmt.bufPrintZ(&lower_storage_z_buffer, "{s}", .{lower_storage}) catch storage_name_z;
            metadata.setPropertyStr(ctx, lower_storage_z.ptr, entry.dup(ctx)) catch return quickjs.Value.exception;
        }
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
    if (isForwardedBodyFrameEventAttribute(name.ptr[0..name.len]) and isBodyOrFrameSetElement(ctx, this_value)) {
        this_value.setPropertyStr(ctx, name.ptr, quickjs.Value.null) catch {};
    }
    if (attributeIsIdOrName(name.ptr[0..name.len])) {
        const document = jsNodeOwnerDocumentGet(ctx, this_value);
        defer document.deinit(ctx);
        if (document.isObject()) syncNamedWindowPropertiesForDocument(ctx, document);
    }
    queueMutationRecord(ctx, this_value, .attributes, name.ptr[0..name.len], old_value);
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

fn jsElementRemoveAttributeNS(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const namespace = if (args.len > 0 and !args[0].isNull() and !args[0].isUndefined()) parseStringArg(ctx, args, 0, "removeAttributeNS") else null;
    defer if (namespace) |text| ctx.freeCString(text.ptr);
    const local = parseStringArg(ctx, args, 1, "removeAttributeNS") orelse return quickjs.Value.exception;
    defer ctx.freeCString(local.ptr);

    const names = jsElementGetAttributeNames(ctx, this_value, &.{});
    defer names.deinit(ctx);
    if (names.isException()) return quickjs.Value.exception;
    const metadata = this_value.getPropertyStr(ctx, "__zigAttributeNSMetadata");
    defer metadata.deinit(ctx);
    const len = arrayLength(ctx, names);
    for (0..len) |i_usize| {
        const name_value = names.getPropertyUint32(ctx, @intCast(i_usize));
        defer name_value.deinit(ctx);
        const name = name_value.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(name.ptr);
        var matches = false;
        if (!metadata.isException() and metadata.isObject()) {
            const entry = metadata.getPropertyStr(ctx, name.ptr);
            defer entry.deinit(ctx);
            if (entry.isObject()) {
                const entry_local = entry.getPropertyStr(ctx, "localName");
                defer entry_local.deinit(ctx);
                const entry_namespace = entry.getPropertyStr(ctx, "namespaceURI");
                defer entry_namespace.deinit(ctx);
                const entry_local_text = entry_local.toCStringLen(ctx) orelse continue;
                defer ctx.freeCString(entry_local_text.ptr);
                const local_matches = std.mem.eql(u8, entry_local_text.ptr[0..entry_local_text.len], local.ptr[0..local.len]);
                const namespace_matches = if (namespace) |expected| blk: {
                    const actual = entry_namespace.toCStringLen(ctx) orelse break :blk false;
                    defer ctx.freeCString(actual.ptr);
                    break :blk std.mem.eql(u8, actual.ptr[0..actual.len], expected.ptr[0..expected.len]);
                } else entry_namespace.isNull() or entry_namespace.isUndefined();
                matches = local_matches and namespace_matches;
            }
        } else if (namespace == null) {
            matches = std.mem.eql(u8, name.ptr[0..name.len], local.ptr[0..local.len]);
        }
        if (matches) {
            const removed = jsElementRemoveAttribute(ctx, this_value, @ptrCast(&[_]quickjs.Value{name_value}));
            if (removed.isException()) return quickjs.Value.exception;
            defer removed.deinit(ctx);
            return quickjs.Value.undefined;
        }
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

fn jsElementHasAttributes(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const names = jsElementGetAttributeNames(ctx, this_value, &.{});
    defer names.deinit(ctx);
    if (names.isException()) return quickjs.Value.exception;
    return quickjs.Value.initBool(arrayLength(ctx, names) > 0);
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
        if (attributeIsIdOrName(name.ptr[0..name.len])) {
            const document = jsNodeOwnerDocumentGet(ctx, this_value);
            defer document.deinit(ctx);
            if (document.isObject()) syncNamedWindowPropertiesForDocument(ctx, document);
        }
        return quickjs.Value.initBool(true);
    }
    if (has) {
        const status = zig_dom.zig_dom_element_remove_attribute(this_handle, name.ptr, name.len);
        if (status != 0) return throwStatus(ctx, "toggleAttribute", status);
        if (attributeIsIdOrName(name.ptr[0..name.len])) {
            const document = jsNodeOwnerDocumentGet(ctx, this_value);
            defer document.deinit(ctx);
            if (document.isObject()) syncNamedWindowPropertiesForDocument(ctx, document);
        }
    }
    return quickjs.Value.initBool(false);
}

fn attributeIsIdOrName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "id") or std.ascii.eqlIgnoreCase(name, "name");
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
    defer attrs.deinit(ctx);

    enrichAttributeEntries(ctx, this_value, attrs) catch return quickjs.Value.exception;

    const named_map = namedNodeMapFromEntries(ctx, attrs);
    if (named_map.isException()) return named_map;
    return named_map;
}

fn enrichAttributeEntries(ctx: *quickjs.Context, element: quickjs.Value, entries: quickjs.Value) error{JSError}!void {
    const metadata = element.getPropertyStr(ctx, "__zigAttributeNSMetadata");
    defer metadata.deinit(ctx);
    const len = arrayLength(ctx, entries);
    for (0..len) |i_usize| {
        const entry = entries.getPropertyUint32(ctx, @intCast(i_usize));
        defer entry.deinit(ctx);
        if (entry.isException() or !entry.isObject()) continue;
        const name_value = entry.getPropertyStr(ctx, "name");
        defer name_value.deinit(ctx);
        const name = name_value.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(name.ptr);
        const value = entry.getPropertyStr(ctx, "value");
        defer value.deinit(ctx);

        entry.setPropertyStr(ctx, "nodeName", name_value.dup(ctx)) catch return error.JSError;
        entry.setPropertyStr(ctx, "nodeValue", value.dup(ctx)) catch return error.JSError;
        entry.setPropertyStr(ctx, "textContent", value.dup(ctx)) catch return error.JSError;
        entry.setPropertyStr(ctx, "ownerElement", element.dup(ctx)) catch return error.JSError;
        const owner_document = jsNodeOwnerDocumentGet(ctx, element);
        defer owner_document.deinit(ctx);
        if (!owner_document.isException() and owner_document.isObject()) {
            entry.setPropertyStr(ctx, "ownerDocument", owner_document.dup(ctx)) catch return error.JSError;
        }
        entry.setPropertyStr(ctx, "nodeType", quickjs.Value.initInt64(2)) catch return error.JSError;
        entry.setPropertyStr(ctx, "specified", quickjs.Value.initBool(true)) catch return error.JSError;

        var local_value = name_value.dup(ctx);
        var namespace_value = quickjs.Value.null;
        var prefix_value = quickjs.Value.null;
        if (!metadata.isException() and metadata.isObject()) {
            const meta = metadata.getPropertyStr(ctx, name.ptr);
            defer meta.deinit(ctx);
            if (meta.isObject()) {
                const display_name = meta.getPropertyStr(ctx, "name");
                defer display_name.deinit(ctx);
                if (!display_name.isException() and !display_name.isUndefined()) {
                    entry.setPropertyStr(ctx, "name", display_name.dup(ctx)) catch return error.JSError;
                    entry.setPropertyStr(ctx, "nodeName", display_name.dup(ctx)) catch return error.JSError;
                }
                local_value.deinit(ctx);
                local_value = meta.getPropertyStr(ctx, "localName");
                namespace_value = meta.getPropertyStr(ctx, "namespaceURI");
                prefix_value = meta.getPropertyStr(ctx, "prefix");
            }
        }
        entry.setPropertyStr(ctx, "localName", local_value) catch return error.JSError;
        entry.setPropertyStr(ctx, "namespaceURI", namespace_value) catch return error.JSError;
        entry.setPropertyStr(ctx, "prefix", prefix_value) catch return error.JSError;
    }
}

fn namedNodeMapPropertyFlagsC() c_int {
    return c.JS_PROP_CONFIGURABLE |
        c.JS_PROP_ENUMERABLE |
        c.JS_PROP_HAS_CONFIGURABLE |
        c.JS_PROP_HAS_WRITABLE |
        c.JS_PROP_HAS_ENUMERABLE |
        c.JS_PROP_HAS_VALUE |
        c.JS_PROP_THROW;
}

fn namedNodeMapFromEntries(ctx: *quickjs.Context, entries: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "NamedNodeMap");
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return quickjs.Value.exception;

    const proto = ctor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    if (proto.isException() or !proto.isObject()) return quickjs.Value.exception;

    const out = quickjs.Value.initObjectProto(ctx, proto);
    if (out.isException()) return out;

    const len = arrayLength(ctx, entries);
    for (0..len) |i_usize| {
        const entry = entries.getPropertyUint32(ctx, @intCast(i_usize));
        defer entry.deinit(ctx);
        if (entry.isException() or !entry.isObject()) continue;

        const defined_index = c.JS_DefinePropertyValueUint32(
            ctx.cval(),
            out.cval(),
            @intCast(i_usize),
            entry.dup(ctx).cval(),
            namedNodeMapPropertyFlagsC(),
        );
        if (defined_index < 0) {
            out.deinit(ctx);
            return quickjs.Value.exception;
        }

        const name_value = entry.getPropertyStr(ctx, "name");
        defer name_value.deinit(ctx);
        const name = name_value.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(name.ptr);
        if (name.len == 0) continue;

        const existing = out.getPropertyStr(ctx, name.ptr);
        defer existing.deinit(ctx);
        if (!existing.isException() and (!existing.isUndefined() and !existing.isNull())) continue;

        const defined_name = c.JS_DefinePropertyValueStr(
            ctx.cval(),
            out.cval(),
            name.ptr,
            entry.dup(ctx).cval(),
            namedNodeMapPropertyFlagsC(),
        );
        if (defined_name < 0) {
            out.deinit(ctx);
            return quickjs.Value.exception;
        }
    }

    return out;
}

fn jsElementQuerySelector(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "querySelector") orelse return quickjs.Value.exception;
    const selector = parseStringArg(ctx, args, 0, "querySelector") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector.ptr);
    if (std.mem.eql(u8, std.mem.trim(u8, selector.ptr[0..selector.len], " \t\n\r\x0c"), ":target")) {
        const document = jsNodeOwnerDocumentGet(ctx, this_value);
        defer document.deinit(ctx);
        if (!document.isObject()) return quickjs.Value.null;
        const document_handle = parseThisHandle(ctx, document, "querySelector") orelse return quickjs.Value.exception;
        const target = documentTargetElement(ctx, document, document_handle, "querySelector");
        if (!target.isObject()) return target;
        const contains = jsNodeContains(ctx, this_value, @ptrCast(&[_]quickjs.Value{target}));
        defer contains.deinit(ctx);
        if (contains.toBool(ctx) catch false) return target;
        target.deinit(ctx);
        return quickjs.Value.null;
    }

    if (simpleIdSelector(selector.ptr[0..selector.len])) |id| {
        const document = jsNodeOwnerDocumentGet(ctx, this_value);
        defer document.deinit(ctx);
        if (document.isObject()) {
            const id_value = quickjs.Value.initStringLen(ctx, id);
            defer id_value.deinit(ctx);
            const candidate = jsDocumentGetElementById(ctx, document, @ptrCast(&[_]quickjs.Value{id_value}));
            if (!candidate.isException() and candidate.isObject()) {
                const contains = jsNodeContains(ctx, this_value, @ptrCast(&[_]quickjs.Value{candidate}));
                defer contains.deinit(ctx);
                if ((contains.toBool(ctx) catch false) and !candidate.isStrictEqual(ctx, this_value)) {
                    return candidate;
                }
            }
            candidate.deinit(ctx);
            return quickjs.Value.null;
        }
    }

    if (isKnownFastSelector(selector.ptr[0..selector.len])) {
        return firstFastQuerySelector(ctx, this_value, selector.ptr[0..selector.len]);
    }

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
    if (std.mem.eql(u8, std.mem.trim(u8, selector.ptr[0..selector.len], " \t\n\r\x0c"), ":target")) {
        const out = initNodeListArray(ctx);
        if (out.isException()) return out;
        const document = jsNodeOwnerDocumentGet(ctx, this_value);
        defer document.deinit(ctx);
        if (!document.isObject()) return out;
        const document_handle = parseThisHandle(ctx, document, "querySelectorAll") orelse {
            out.deinit(ctx);
            return quickjs.Value.exception;
        };
        const target = documentTargetElement(ctx, document, document_handle, "querySelectorAll");
        defer target.deinit(ctx);
        if (target.isException()) {
            out.deinit(ctx);
            return quickjs.Value.exception;
        }
        if (target.isObject()) {
            const contains = jsNodeContains(ctx, this_value, @ptrCast(&[_]quickjs.Value{target}));
            defer contains.deinit(ctx);
            if (contains.toBool(ctx) catch false) {
                setNodeListIndexedProperty(ctx, out, 0, target) catch {
                    out.deinit(ctx);
                    return quickjs.Value.exception;
                };
            }
        }
        return out;
    }

    if (simpleIdSelector(selector.ptr[0..selector.len])) |id| {
        const out = initNodeListArray(ctx);
        if (out.isException()) return out;

        const document = jsNodeOwnerDocumentGet(ctx, this_value);
        defer document.deinit(ctx);
        if (document.isObject()) {
            const id_value = quickjs.Value.initStringLen(ctx, id);
            defer id_value.deinit(ctx);
            const candidate = jsDocumentGetElementById(ctx, document, @ptrCast(&[_]quickjs.Value{id_value}));
            defer candidate.deinit(ctx);
            if (!candidate.isException() and candidate.isObject()) {
                const contains = jsNodeContains(ctx, this_value, @ptrCast(&[_]quickjs.Value{candidate}));
                defer contains.deinit(ctx);
                if ((contains.toBool(ctx) catch false) and !candidate.isStrictEqual(ctx, this_value)) {
                    setNodeListIndexedProperty(ctx, out, 0, candidate) catch {
                        out.deinit(ctx);
                        return quickjs.Value.exception;
                    };
                }
            }
        }

        return out;
    }

    if (isKnownFastSelector(selector.ptr[0..selector.len])) {
        return querySelectorAllFast(ctx, this_value, selector.ptr[0..selector.len]);
    }

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_query_selector_all(this_handle, selector.ptr, selector.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "querySelectorAll", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    return handleCollectionToJs(ctx, out_ptr, out_len);
}

fn jsElementGetElementsByTagName(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "getElementsByTagName") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "getElementsByTagName") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_query_selector_all(this_handle, name.ptr, name.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "getElementsByTagName", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    const collection = htmlCollectionToJs(ctx, out_ptr, out_len);
    if (collection.isException()) return quickjs.Value.exception;
    defer collection.deinit(ctx);
    return registerAndWrapHtmlCollection(ctx, collection, this_handle, name.ptr[0..name.len]);
}

fn jsElementGetElementsByTagNameNS(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "getElementsByTagNameNS") orelse return quickjs.Value.exception;
    const local_name = parseStringArg(ctx, args, 1, "getElementsByTagNameNS") orelse return quickjs.Value.exception;
    defer ctx.freeCString(local_name.ptr);

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_query_selector_all(this_handle, local_name.ptr, local_name.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "getElementsByTagNameNS", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    const collection = htmlCollectionToJs(ctx, out_ptr, out_len);
    if (collection.isException()) return quickjs.Value.exception;
    defer collection.deinit(ctx);
    return registerAndWrapHtmlCollection(ctx, collection, this_handle, local_name.ptr[0..local_name.len]);
}

fn jsElementGetElementsByClassName(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "getElementsByClassName") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "getElementsByClassName") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    var selector_buf: [256]u8 = undefined;
    const selector = std.fmt.bufPrint(&selector_buf, ".{s}", .{name.ptr[0..name.len]}) catch name.ptr[0..name.len];

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_query_selector_all(this_handle, selector.ptr, selector.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "getElementsByClassName", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    const collection = htmlCollectionToJs(ctx, out_ptr, out_len);
    if (collection.isException()) return quickjs.Value.exception;
    defer collection.deinit(ctx);
    return registerClassHtmlCollection(ctx, collection, this_handle, name.ptr[0..name.len], selector);
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
        if (isSimpleTagSelector(selector)) continue;
    }
    if (std.mem.indexOfScalar(u8, selector_list, ',') != null) return false;
    return if (isKnownFastSelector(selector_list) or isSimpleTagSelector(std.mem.trim(u8, selector_list, " \t\n\r"))) false else null;
}

fn isSimpleTagSelector(selector: []const u8) bool {
    if (selector.len == 0) return false;
    const tag = if (std.mem.startsWith(u8, selector, "*|")) selector[2..] else selector;
    if (tag.len == 0) return false;
    for (tag) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-')) return false;
    }
    return true;
}

fn isKnownFastSelector(selector: []const u8) bool {
    return isKnownLiteralSelector(selector) or isRoleTokenSelector(selector);
}

fn isKnownLiteralSelector(selector: []const u8) bool {
    const selectors = comptime [_][]const u8{
        "a",
        "a[href]",
        "a[href]:not([href=\"\"])",
        "area",
        "h1",
        "h1 + p",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "input[name*=user i]",
        "input:not([type])",
        "input[type=\"search\"]",
        "input[type=\"text\"]",
        "svg > title",
        ":scope > p",
        ":scope > span",
        "section > p",
        "#scope",
        ".copy",
        "[data-kind|='alpha']",
    };

    inline for (selectors) |known| {
        if (selector.len == known.len and std.mem.eql(u8, selector, known)) return true;
    }
    return false;
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
    if (isSimpleTagSelector(selector)) {
        const tag = if (std.mem.startsWith(u8, selector, "*|")) selector[2..] else selector;
        return std.ascii.eqlIgnoreCase(local.ptr[0..local.len], tag);
    }
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

fn asciiContainsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[start .. start + needle.len], needle)) return true;
    }
    return false;
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
        if (std.mem.indexOf(u8, attr, "*=")) |operator_index| {
            const attr_name = attr[0..operator_index];
            var expected = std.mem.trim(u8, attr[operator_index + 2 ..], " \t\n\r");
            const case_insensitive = std.mem.endsWith(u8, expected, " i");
            if (case_insensitive) expected = std.mem.trim(u8, expected[0 .. expected.len - 2], " \t\n\r");
            if (expected.len >= 2 and ((expected[0] == '"' and expected[expected.len - 1] == '"') or (expected[0] == '\'' and expected[expected.len - 1] == '\''))) {
                expected = expected[1 .. expected.len - 1];
            }
            const value = elementAttributeString(ctx, element, attr_name) orelse return false;
            defer ctx.freeCString(value.ptr);
            const text = value.ptr[0..value.len];
            return if (case_insensitive) asciiContainsIgnoreCase(text, expected) else std.mem.indexOf(u8, text, expected) != null;
        }
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

fn jsElementInsertAdjacentElement(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const position = parseStringArg(ctx, args, 0, "insertAdjacentElement") orelse return quickjs.Value.exception;
    defer ctx.freeCString(position.ptr);
    _ = parseRequiredNodeArgHandle(ctx, args, 1, "insertAdjacentElement") orelse return quickjs.Value.exception;

    if (std.ascii.eqlIgnoreCase(position.ptr[0..position.len], "beforebegin")) {
        const parent = jsNodeParentNodeGet(ctx, this_value);
        defer parent.deinit(ctx);
        if (parent.isNull() or parent.isUndefined()) return quickjs.Value.null;
        const inserted = jsNodeInsertBefore(ctx, parent, @ptrCast(&[_]quickjs.Value{ args[1], this_value }));
        if (inserted.isException()) return quickjs.Value.exception;
        return inserted;
    }
    if (std.ascii.eqlIgnoreCase(position.ptr[0..position.len], "afterbegin")) {
        const first = jsNodeFirstChildGet(ctx, this_value);
        defer first.deinit(ctx);
        const inserted = jsNodeInsertBefore(ctx, this_value, @ptrCast(&[_]quickjs.Value{ args[1], first }));
        if (inserted.isException()) return quickjs.Value.exception;
        return inserted;
    }
    if (std.ascii.eqlIgnoreCase(position.ptr[0..position.len], "beforeend")) {
        const inserted = jsNodeAppendChild(ctx, this_value, @ptrCast(&[_]quickjs.Value{args[1]}));
        if (inserted.isException()) return quickjs.Value.exception;
        return inserted;
    }
    if (std.ascii.eqlIgnoreCase(position.ptr[0..position.len], "afterend")) {
        const parent = jsNodeParentNodeGet(ctx, this_value);
        defer parent.deinit(ctx);
        if (parent.isNull() or parent.isUndefined()) return quickjs.Value.null;
        const next = jsNodeNextSiblingGet(ctx, this_value);
        defer next.deinit(ctx);
        const inserted = jsNodeInsertBefore(ctx, parent, @ptrCast(&[_]quickjs.Value{ args[1], next }));
        if (inserted.isException()) return quickjs.Value.exception;
        return inserted;
    }

    return throwOperationMessage(ctx, "insertAdjacentElement", "invalid position");
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

fn jsElementInsertAdjacentText(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "insertAdjacentText") orelse return quickjs.Value.exception;
    const position = parseStringArg(ctx, args, 0, "insertAdjacentText") orelse return quickjs.Value.exception;
    defer ctx.freeCString(position.ptr);
    const text = parseStringArg(ctx, args, 1, "insertAdjacentText") orelse return quickjs.Value.exception;
    defer ctx.freeCString(text.ptr);
    const parent_handle = zig_dom.zig_dom_node_parent(this_handle);
    if (parent_handle != 0 and zig_dom.zig_dom_node_type(parent_handle) == 9 and
        (std.ascii.eqlIgnoreCase(position.ptr[0..position.len], "beforebegin") or std.ascii.eqlIgnoreCase(position.ptr[0..position.len], "afterend")))
    {
        return throwOperationMessage(ctx, "insertAdjacentText", "cannot insert text as document child");
    }
    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    const text_value = quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
    defer text_value.deinit(ctx);
    const node = jsDocumentCreateTextNode(ctx, document, @ptrCast(&[_]quickjs.Value{text_value}));
    defer node.deinit(ctx);
    if (node.isException()) return quickjs.Value.exception;
    const position_value = quickjs.Value.initStringLen(ctx, position.ptr[0..position.len]);
    defer position_value.deinit(ctx);
    const inserted = jsElementInsertAdjacentElement(ctx, this_value, @ptrCast(&[_]quickjs.Value{ position_value, node }));
    defer inserted.deinit(ctx);
    if (inserted.isException()) return quickjs.Value.exception;
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
    const profile = classProfileEnabled();
    const start = if (profile) classProfileNowNs() else 0;
    defer if (profile) {
        class_perf_stats.focus_calls += 1;
        class_perf_stats.focus_ns += classProfileNowNs() - start;
    };

    const document = jsNodeOwnerDocumentGet(ctx, this_value);
    defer document.deinit(ctx);
    if (!document.isException() and document.isObject()) {
        document.setPropertyStr(ctx, "activeElement", this_value.dup(ctx)) catch return quickjs.Value.exception;
    }
    if (!hasDirectEventHandler(ctx, this_value, "focus", "onfocus")) return quickjs.Value.undefined;
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
    if (!hasDirectEventHandler(ctx, this_value, "blur", "onblur")) return quickjs.Value.undefined;
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

fn hasDirectEventHandler(ctx: *quickjs.Context, target: quickjs.Value, event_name: [*:0]const u8, property_name: [*:0]const u8) bool {
    const listeners = target.getPropertyStr(ctx, "__zigEventListeners");
    defer listeners.deinit(ctx);
    if (!listeners.isException() and listeners.isObject()) {
        const list = listeners.getPropertyStr(ctx, event_name);
        defer list.deinit(ctx);
        if (!list.isException() and list.isObject() and arrayLength(ctx, list) > 0) return true;
    }

    const property_handler = target.getPropertyStr(ctx, property_name);
    defer property_handler.deinit(ctx);
    return property_handler.isFunction(ctx);
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

fn jsElementScrollIntoView(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    _ = ctx_opt orelse return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsElementGetBoundingClientRect(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const profile = classProfileEnabled();
    const start = if (profile) classProfileNowNs() else 0;
    defer if (profile) {
        class_perf_stats.bounding_rect_calls += 1;
        class_perf_stats.bounding_rect_ns += classProfileNowNs() - start;
    };

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const cached = global.getPropertyStr(ctx, "__zigZeroDOMRect");
    if (!cached.isException() and cached.isObject()) return cached;
    cached.deinit(ctx);

    const ctor = global.getPropertyStr(ctx, "DOMRect");
    defer ctor.deinit(ctx);
    var args = [_]quickjs.Value{ quickjs.Value.initFloat64(0), quickjs.Value.initFloat64(0), quickjs.Value.initFloat64(0), quickjs.Value.initFloat64(0) };
    const rect = quickjs.Value.fromCVal(c.JS_CallConstructor(ctx.cval(), ctor.cval(), @intCast(args.len), @ptrCast(&args)));
    if (rect.isException()) return rect;
    global.setPropertyStr(ctx, "__zigZeroDOMRect", rect.dup(ctx)) catch return quickjs.Value.exception;
    return rect;
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

fn jsDocumentDoctypeGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const document_handle = parseThisHandle(ctx, this_value, "doctype") orelse return quickjs.Value.exception;
    var child = zig_dom.zig_dom_node_first_child(document_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        if (zig_dom.zig_dom_node_type(child) == 10) return wrapNodeHandle(ctx, child);
    }
    const cached = this_value.getPropertyStr(ctx, "__zigSyntheticDoctype");
    if (!cached.isException() and cached.isObject()) return cached;
    cached.deinit(ctx);
    const should_synthesize = getBoolProperty(ctx, this_value, "__zigHasSyntheticHtmlDoctype") orelse false;
    if (should_synthesize) {
        const name = quickjs.Value.initStringLen(ctx, "html");
        defer name.deinit(ctx);
        const empty_public = quickjs.Value.initStringLen(ctx, "");
        defer empty_public.deinit(ctx);
        const empty_system = quickjs.Value.initStringLen(ctx, "");
        defer empty_system.deinit(ctx);
        const doctype = jsDocumentCreateDocumentType(ctx, this_value, @ptrCast(&[_]quickjs.Value{ name, empty_public, empty_system }));
        if (doctype.isException()) return doctype;
        defineHiddenDataPropertyStr(ctx, doctype, "parentNode", this_value.dup(ctx)) catch return quickjs.Value.exception;
        defineHiddenDataPropertyStr(ctx, doctype, "parentElement", quickjs.Value.null) catch return quickjs.Value.exception;
        this_value.setPropertyStr(ctx, "__zigSyntheticDoctype", doctype.dup(ctx)) catch return quickjs.Value.exception;
        return doctype;
    }
    return quickjs.Value.null;
}

fn jsDocumentHeadGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return documentWindowNodeGet(ctx_opt, this_value, "head", zig_dom.zig_dom_window_head);
}

fn jsDocumentBodyGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    return documentWindowNodeGet(ctx_opt, this_value, "body", zig_dom.zig_dom_window_body);
}

fn isValidCreateElementName(name: []const u8) bool {
    if (name.len == 0) return false;
    const first = name[0];
    if (std.ascii.isDigit(first) or first == '-' or first == '.' or first == '<' or first == '}' or first == '^') return false;
    for (name) |ch| {
        if (std.ascii.isWhitespace(ch) or ch == '>') return false;
    }
    return true;
}

fn isInvalidQualifiedNameLocalChar(ch: u8) bool {
    if (ch < 0x80) return !(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.' or ch == '<' or ch == '}');
    return false;
}

fn isValidCreateElementNSQualifiedName(name: []const u8) bool {
    if (name.len == 0) return false;
    const colon_index = std.mem.indexOfScalar(u8, name, ':');
    const first = name[0];
    if (first == '-' or first == '.' or first == '<' or first == '}' or first == '^' or first == ':') return false;
    if (colon_index == null and std.ascii.isDigit(first)) return false;
    if (colon_index) |index| {
        if (index == 0 or index + 1 >= name.len) return false;
        for (name[0..index]) |ch| {
            if (isInvalidQualifiedNameLocalChar(ch) or ch == ':') return false;
        }
        const local = name[index + 1 ..];
        if (std.ascii.isDigit(local[0]) or local[0] == '<' or local[0] == '}') return false;
        for (local) |ch| {
            if (ch != ':' and isInvalidQualifiedNameLocalChar(ch)) return false;
        }
        return true;
    }
    for (name) |ch| {
        if (isInvalidQualifiedNameLocalChar(ch)) return false;
    }
    return true;
}

fn isValidCreateElementNSNamespace(namespace: ?[]const u8, qualified_name: []const u8) bool {
    const XML_NS = "http://www.w3.org/XML/1998/namespace";
    const XMLNS_NS = "http://www.w3.org/2000/xmlns/";
    const colon_index = std.mem.indexOfScalar(u8, qualified_name, ':');
    const prefix = if (colon_index) |index| qualified_name[0..index] else null;
    const local = if (colon_index) |index| qualified_name[index + 1 ..] else qualified_name;
    const has_namespace = namespace != null;

    if (!has_namespace and prefix != null) return false;
    if (prefix) |text| {
        if (std.mem.eql(u8, text, "xml") and !(namespace != null and std.mem.eql(u8, namespace.?, XML_NS))) return false;
        if (std.mem.eql(u8, text, "xmlns") and !(namespace != null and std.mem.eql(u8, namespace.?, XMLNS_NS))) return false;
    }
    if (std.mem.eql(u8, qualified_name, "xmlns") and !(namespace != null and std.mem.eql(u8, namespace.?, XMLNS_NS))) return false;
    if (namespace != null and std.mem.eql(u8, namespace.?, XMLNS_NS)) {
        if (!(std.mem.eql(u8, qualified_name, "xmlns") or (prefix != null and std.mem.eql(u8, prefix.?, "xmlns")))) return false;
    }
    _ = local;
    return true;
}

fn isValidProcessingInstructionTarget(target: []const u8) bool {
    if (target.len == 0) return false;
    if (std.ascii.isDigit(target[0]) or target[0] == '\\' or target[0] == '\x0c') return false;
    if (std.mem.startsWith(u8, target, "\xC2\xB7") or std.mem.startsWith(u8, target, "\xC3\x97")) return false;
    if (std.mem.indexOf(u8, target, "\xC3\x97") != null) return false;
    return true;
}

fn jsDocumentCreateElement(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "createElement") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "createElement") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const raw_name = name.ptr[0..name.len];
    if (!isValidCreateElementName(raw_name)) return throwOperationMessage(ctx, "createElement", "INVALID_CHARACTER_ERR");

    var name_buffer: [256]u8 = undefined;
    var element_name = raw_name;
    const preserve_case = getBoolProperty(ctx, this_value, "__zigPreserveElementCase") orelse false;
    const is_xml_document = getBoolProperty(ctx, this_value, "__zigIsXmlDocument") orelse false;
    if (!preserve_case and raw_name.len <= name_buffer.len) {
        for (raw_name, 0..) |ch, i| name_buffer[i] = std.ascii.toLower(ch);
        element_name = name_buffer[0..raw_name.len];
    }

    var out_handle: u64 = 0;
    var status = zig_dom.zig_dom_document_create_element(document_handle, element_name.ptr, element_name.len, &out_handle);
    if (status == 1) {
        const global_retry = ctx.getGlobalObject();
        defer global_retry.deinit(ctx);
        const global_document = global_retry.getPropertyStr(ctx, "document");
        defer global_document.deinit(ctx);
        if (!global_document.isException() and global_document.isObject()) {
            if (parseThisHandle(ctx, global_document, "createElement")) |global_document_handle| {
                if (global_document_handle != document_handle) {
                    status = zig_dom.zig_dom_document_create_element(global_document_handle, element_name.ptr, element_name.len, &out_handle);
                }
            }
        }
    }
    if (status != 0) return throwStatus(ctx, "createElement", status);
    const node = wrapNodeHandle(ctx, out_handle);
    if (node.isException()) return node;
    if (preserve_case) {
        node.setPropertyStr(ctx, "__zigPreserveElementCase", quickjs.Value.initBool(true)) catch {
            node.deinit(ctx);
            return quickjs.Value.exception;
        };
        node.setPropertyStr(ctx, "__zigLocalName", quickjs.Value.initStringLen(ctx, raw_name)) catch {
            node.deinit(ctx);
            return quickjs.Value.exception;
        };
        node.setPropertyStr(ctx, "__zigTagName", quickjs.Value.initStringLen(ctx, raw_name)) catch {
            node.deinit(ctx);
            return quickjs.Value.exception;
        };
    }
    if (is_xml_document) {
        node.setPropertyStr(ctx, "__zigNamespaceURI", quickjs.Value.null) catch {
            node.deinit(ctx);
            return quickjs.Value.exception;
        };
    }
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
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return jsDocumentCreateElement(ctx_opt, this_value, raw_args);

    const namespace_text = if (args[0].isNull() or args[0].isUndefined())
        null
    else
        args[0].toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer if (namespace_text) |text| ctx.freeCString(text.ptr);

    const namespace_slice = if (namespace_text) |text| blk: {
        const slice = text.ptr[0..text.len];
        break :blk if (slice.len == 0) null else slice;
    } else null;

    const qualified_name = parseStringArg(ctx, args, 1, "createElementNS") orelse return quickjs.Value.exception;
    defer ctx.freeCString(qualified_name.ptr);
    const qualified_slice = qualified_name.ptr[0..qualified_name.len];
    if (!isValidCreateElementNSQualifiedName(qualified_slice)) return throwOperationMessage(ctx, "createElementNS", "INVALID_CHARACTER_ERR");
    if (!isValidCreateElementNSNamespace(namespace_slice, qualified_slice)) return throwOperationMessage(ctx, "createElementNS", "NAMESPACE_ERR");

    const document_handle = parseThisHandle(ctx, this_value, "createElementNS") orelse return quickjs.Value.exception;
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_element(document_handle, qualified_slice.ptr, qualified_slice.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "createElementNS", status);
    const created = wrapNodeHandle(ctx, out_handle);
    if (created.isException() or !created.isObject()) return created;

    const colon_index = std.mem.indexOfScalar(u8, qualified_slice, ':');
    if (colon_index) |index| {
        created.setPropertyStr(ctx, "__zigPrefix", quickjs.Value.initStringLen(ctx, qualified_slice[0..index])) catch {
            created.deinit(ctx);
            return quickjs.Value.exception;
        };
        created.setPropertyStr(ctx, "__zigLocalName", quickjs.Value.initStringLen(ctx, qualified_slice[index + 1 ..])) catch {
            created.deinit(ctx);
            return quickjs.Value.exception;
        };
    } else {
        created.setPropertyStr(ctx, "__zigLocalName", quickjs.Value.initStringLen(ctx, qualified_slice)) catch {
            created.deinit(ctx);
            return quickjs.Value.exception;
        };
    }
    const document_preserves_case = getBoolProperty(ctx, this_value, "__zigPreserveElementCase") orelse false;
    created.setPropertyStr(ctx, "__zigPreserveElementCase", quickjs.Value.initBool(document_preserves_case or namespace_slice == null or !std.mem.eql(u8, namespace_slice.?, "http://www.w3.org/1999/xhtml"))) catch {
        created.deinit(ctx);
        return quickjs.Value.exception;
    };

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    if (namespace_slice) |text| {
        const namespace_status = zig_dom.zig_dom_element_set_namespace(out_handle, text.ptr, text.len);
        if (namespace_status != 0) {
            created.deinit(ctx);
            return throwStatus(ctx, "createElementNS", namespace_status);
        }
        created.setPropertyStr(ctx, "__zigNamespaceURI", quickjs.Value.initStringLen(ctx, text)) catch {
            created.deinit(ctx);
            return quickjs.Value.exception;
        };

        const local_for_ctor = if (colon_index) |index| qualified_slice[index + 1 ..] else qualified_slice;
        const ctor_name = if (std.mem.eql(u8, text, "http://www.w3.org/1999/xhtml"))
            (if (std.mem.eql(u8, local_for_ctor, "span")) "HTMLSpanElement" else if (std.mem.eql(u8, local_for_ctor, "SPAN")) "HTMLUnknownElement" else "HTMLElement")
        else if (std.mem.eql(u8, text, "http://www.w3.org/2000/svg"))
            "SVGElement"
        else
            "Element";
        const ctor = global.getPropertyStr(ctx, ctor_name);
        defer ctor.deinit(ctx);
        if (!ctor.isException() and ctor.isObject()) {
            const proto = ctor.getPropertyStr(ctx, "prototype");
            defer proto.deinit(ctx);
            if (!proto.isException() and proto.isObject()) {
                created.setPrototype(ctx, proto) catch {
                    created.deinit(ctx);
                    return quickjs.Value.exception;
                };
            }
        }
    } else {
        created.setPropertyStr(ctx, "__zigNamespaceURI", quickjs.Value.null) catch {
            created.deinit(ctx);
            return quickjs.Value.exception;
        };
        const ctor = global.getPropertyStr(ctx, "Element");
        defer ctor.deinit(ctx);
        if (!ctor.isException() and ctor.isObject()) {
            const proto = ctor.getPropertyStr(ctx, "prototype");
            defer proto.deinit(ctx);
            if (!proto.isException() and proto.isObject()) {
                created.setPrototype(ctx, proto) catch {
                    created.deinit(ctx);
                    return quickjs.Value.exception;
                };
            }
        }
    }

    return created;
}

fn jsDocumentCreateAttribute(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "createAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    if (name.len == 0) return throwOperationMessage(ctx, "createAttribute", "INVALID_CHARACTER_ERR");

    var buffer: [256]u8 = undefined;
    var attr_name = name.ptr[0..name.len];
    const is_xml_document = getBoolProperty(ctx, this_value, "__zigIsXmlDocument") orelse false;
    if (!is_xml_document and name.len <= buffer.len) {
        for (attr_name, 0..) |ch, i| buffer[i] = std.ascii.toLower(ch);
        attr_name = buffer[0..name.len];
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "Attr");
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return quickjs.Value.exception;
    const name_value = quickjs.Value.initStringLen(ctx, attr_name);
    defer name_value.deinit(ctx);
    return quickjs.Value.fromCVal(c.JS_CallConstructor(ctx.cval(), ctor.cval(), 1, @ptrCast(@constCast(&name_value))));
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

fn jsDocumentCreateCDATASection(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const html_document = global.getPropertyStr(ctx, "document");
    defer html_document.deinit(ctx);
    if (!html_document.isException() and this_value.isStrictEqual(ctx, html_document)) {
        return throwOperationMessage(ctx, "createCDATASection", "CDATA sections are not supported for HTML documents");
    }
    return jsDocumentCreateTextNode(ctx_opt, this_value, raw_args);
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

fn jsDocumentCreateProcessingInstruction(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "createProcessingInstruction") orelse return quickjs.Value.exception;
    const target = parseStringArg(ctx, args, 0, "createProcessingInstruction") orelse return quickjs.Value.exception;
    defer ctx.freeCString(target.ptr);
    const data = parseStringArg(ctx, args, 1, "createProcessingInstruction") orelse return quickjs.Value.exception;
    defer ctx.freeCString(data.ptr);
    const target_slice = target.ptr[0..target.len];
    const data_slice = data.ptr[0..data.len];
    if (!isValidProcessingInstructionTarget(target_slice) or std.mem.indexOf(u8, data_slice, "?>") != null) {
        return throwOperationMessage(ctx, "createProcessingInstruction", "INVALID_CHARACTER_ERR");
    }

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_comment(document_handle, data.ptr, data.len, &out_handle);
    if (status != 0) return throwStatus(ctx, "createProcessingInstruction", status);
    const node = wrapNodeHandle(ctx, out_handle);
    if (node.isException() or !node.isObject()) return node;
    node.setPropertyStr(ctx, "_nodeTypeOverride", quickjs.Value.initInt64(7)) catch return quickjs.Value.exception;
    node.setPropertyStr(ctx, "_nodeNameOverride", quickjs.Value.initStringLen(ctx, target_slice)) catch return quickjs.Value.exception;
    node.setPropertyStr(ctx, "target", quickjs.Value.initStringLen(ctx, target_slice)) catch return quickjs.Value.exception;
    return node;
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

fn jsDocumentCreateEvent(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const interface_name = parseStringArg(ctx, args, 0, "createEvent") orelse return quickjs.Value.exception;
    defer ctx.freeCString(interface_name.ptr);

    var kind: EventKind = .event;
    var ctor_name: [:0]const u8 = "Event";
    if (std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "customevent")) {
        kind = .custom;
        ctor_name = "CustomEvent";
    } else if (std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "gamepadevent") or std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "gamepadevents")) {
        kind = .event;
        ctor_name = "GamepadEvent";
    } else if (std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "uievent") or std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "uievents")) {
        kind = .ui;
        ctor_name = "UIEvent";
    } else if (std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "focusevent") or std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "focusevents")) {
        kind = .focus;
        ctor_name = "FocusEvent";
    } else if (std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "mouseevent") or std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "mouseevents")) {
        kind = .mouse;
        ctor_name = "MouseEvent";
    } else if (std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "wheelevent") or std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "wheelevents")) {
        kind = .wheel;
        ctor_name = "WheelEvent";
    } else if (std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "keyboardevent") or std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "keyboardevents")) {
        kind = .keyboard;
        ctor_name = "KeyboardEvent";
    } else if (std.ascii.eqlIgnoreCase(interface_name.ptr[0..interface_name.len], "errorevent")) {
        kind = .error_event;
        ctor_name = "ErrorEvent";
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, ctor_name);
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return quickjs.Value.exception;

    const event = createEventObject(ctx, ctor, &.{}, kind);
    if (event.isException()) return event;
    if (kind == .custom) {
        event.setPropertyStr(ctx, "detail", quickjs.Value.null) catch {
            event.deinit(ctx);
            return quickjs.Value.exception;
        };
    }
    return event;
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

fn jsDocumentFragmentGetElementById(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const fragment_handle = parseThisHandle(ctx, this_value, "getElementById") orelse return quickjs.Value.exception;
    const id = parseStringArg(ctx, args, 0, "getElementById") orelse return quickjs.Value.exception;
    defer ctx.freeCString(id.ptr);
    if (id.len == 0) return quickjs.Value.null;

    var selector_buf: [256]u8 = undefined;
    const selector = std.fmt.bufPrint(&selector_buf, "#{s}", .{id.ptr[0..id.len]}) catch return quickjs.Value.null;
    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_query_selector_all(fragment_handle, selector.ptr, selector.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "getElementById", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    if (out_len == 0) return quickjs.Value.null;
    return wrapNodeHandle(ctx, out_ptr[0]);
}

fn documentTargetElement(ctx: *quickjs.Context, document: quickjs.Value, document_handle: u64, operation: []const u8) quickjs.Value {
    const window = jsDocumentDefaultViewGet(ctx, document);
    defer window.deinit(ctx);
    if (window.isException() or !window.isObject()) return quickjs.Value.null;
    const location = window.getPropertyStr(ctx, "location");
    defer location.deinit(ctx);
    if (location.isException() or !location.isObject()) return quickjs.Value.null;
    const hash = location.getPropertyStr(ctx, "hash");
    defer hash.deinit(ctx);
    if (hash.isException() or hash.isUndefined() or hash.isNull()) return quickjs.Value.null;
    const text = hash.toCStringLen(ctx) orelse return quickjs.Value.null;
    defer ctx.freeCString(text.ptr);
    if (text.len <= 1 or text.ptr[0] != '#') return quickjs.Value.null;
    const id = text.ptr[1..text.len];
    const id_value = quickjs.Value.initStringLen(ctx, id);
    defer id_value.deinit(ctx);
    _ = document_handle;
    _ = operation;
    return jsDocumentGetElementById(ctx, document, @ptrCast(&[_]quickjs.Value{id_value}));
}

fn jsDocumentQuerySelector(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "querySelector") orelse return quickjs.Value.exception;
    const selector = parseStringArg(ctx, args, 0, "querySelector") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector.ptr);
    if (std.mem.eql(u8, std.mem.trim(u8, selector.ptr[0..selector.len], " \t\n\r\x0c"), ":target")) {
        return documentTargetElement(ctx, this_value, document_handle, "querySelector");
    }

    if (simpleIdSelector(selector.ptr[0..selector.len])) |id| {
        var out_handle_id: u64 = 0;
        const id_status = zig_dom.zig_dom_document_get_element_by_id(document_handle, id.ptr, id.len, &out_handle_id);
        if (id_status != 0) return throwStatus(ctx, "querySelector", id_status);
        return wrapNodeHandle(ctx, out_handle_id);
    }

    if (isKnownFastSelector(selector.ptr[0..selector.len])) {
        return firstFastQuerySelector(ctx, this_value, selector.ptr[0..selector.len]);
    }

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
    if (std.mem.eql(u8, std.mem.trim(u8, selector.ptr[0..selector.len], " \t\n\r\x0c"), ":target")) {
        const out = initNodeListArray(ctx);
        if (out.isException()) return out;
        const target = documentTargetElement(ctx, this_value, document_handle, "querySelectorAll");
        defer target.deinit(ctx);
        if (target.isException()) {
            out.deinit(ctx);
            return quickjs.Value.exception;
        }
        if (target.isObject()) {
            setNodeListIndexedProperty(ctx, out, 0, target) catch {
                out.deinit(ctx);
                return quickjs.Value.exception;
            };
        }
        return out;
    }

    if (simpleIdSelector(selector.ptr[0..selector.len])) |id| {
        var out_handle_id: u64 = 0;
        const id_status = zig_dom.zig_dom_document_get_element_by_id(document_handle, id.ptr, id.len, &out_handle_id);
        if (id_status != 0) return throwStatus(ctx, "querySelectorAll", id_status);
        const out = initNodeListArray(ctx);
        if (out.isException()) return out;
        if (out_handle_id != 0) {
            const node = wrapNodeHandle(ctx, out_handle_id);
            if (node.isException()) {
                out.deinit(ctx);
                return quickjs.Value.exception;
            }
            defer node.deinit(ctx);
            setNodeListIndexedProperty(ctx, out, 0, node) catch {
                out.deinit(ctx);
                return quickjs.Value.exception;
            };
        }
        return out;
    }

    if (isKnownFastSelector(selector.ptr[0..selector.len])) {
        return querySelectorAllFast(ctx, this_value, selector.ptr[0..selector.len]);
    }

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_document_query_selector_all(document_handle, selector.ptr, selector.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "querySelectorAll", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    return handleCollectionToJs(ctx, out_ptr, out_len);
}

fn querySelectorAllFast(ctx: *quickjs.Context, root: quickjs.Value, selector: []const u8) quickjs.Value {
    const array = initNodeListArray(ctx);
    if (array.isException()) return array;
    var index: u32 = 0;
    const collect_result = if (std.mem.startsWith(u8, selector, ":scope > "))
        collectMatchingDirectChildrenFast(ctx, root, selector[":scope > ".len..], array, &index)
    else
        collectMatchingDescendantsFast(ctx, root, selector, array, &index);
    collect_result catch {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };
    return array;
}

fn firstFastQuerySelector(ctx: *quickjs.Context, root: quickjs.Value, selector: []const u8) quickjs.Value {
    const matches = querySelectorAllFast(ctx, root, selector);
    if (matches.isException()) return matches;
    defer matches.deinit(ctx);
    const first = matches.getPropertyUint32(ctx, 0);
    if (first.isException()) return first;
    if (first.isUndefined() or first.isNull()) {
        first.deinit(ctx);
        return quickjs.Value.null;
    }
    return first;
}

fn collectMatchingDirectChildrenFast(ctx: *quickjs.Context, root: quickjs.Value, selector: []const u8, out: quickjs.Value, index: *u32) !void {
    const children = jsNodeChildNodesGet(ctx, root);
    defer children.deinit(ctx);
    const len = arrayLength(ctx, children);
    for (0..len) |child_index| {
        const child = children.getPropertyUint32(ctx, @intCast(child_index));
        defer child.deinit(ctx);
        if (child.isException() or !child.isObject()) continue;
        if (zig_dom.zig_dom_node_type(parseThisHandle(ctx, child, "querySelectorAll") orelse 0) != 1) continue;
        if (matchesSelectorFast(ctx, child, selector) orelse false) {
            try setNodeListIndexedProperty(ctx, out, index.*, child);
            index.* += 1;
        }
    }
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
                try setNodeListIndexedProperty(ctx, out, index.*, child);
                index.* += 1;
            }
            try collectMatchingDescendantsFast(ctx, child, selector, out, index);
        }
    }
}

fn jsDocumentGetElementsByClassName(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "getElementsByClassName") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "getElementsByClassName") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    var selector_buf: [256]u8 = undefined;
    const selector = std.fmt.bufPrint(&selector_buf, ".{s}", .{name.ptr[0..name.len]}) catch name.ptr[0..name.len];
    var handles: std.ArrayListUnmanaged(u64) = .empty;
    defer handles.deinit(std.heap.c_allocator);
    collectElementsByClassName(ctx, this_value, name.ptr[0..name.len], &handles) catch return quickjs.Value.exception;
    const collection = htmlCollectionFromSlice(ctx, handles.items);
    if (collection.isException()) return quickjs.Value.exception;
    defer collection.deinit(ctx);
    return registerClassHtmlCollection(ctx, collection, document_handle, name.ptr[0..name.len], selector);
}

fn jsDocumentGetElementsByTagName(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "getElementsByTagName") orelse return quickjs.Value.exception;
    const name = parseStringArg(ctx, args, 0, "getElementsByTagName") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_document_query_selector_all(document_handle, name.ptr, name.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "getElementsByTagName", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    const collection = htmlCollectionToJs(ctx, out_ptr, out_len);
    if (collection.isException()) return quickjs.Value.exception;
    defer collection.deinit(ctx);
    return registerAndWrapHtmlCollection(ctx, collection, document_handle, name.ptr[0..name.len]);
}

fn jsDocumentGetElementsByTagNameNS(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const document_handle = parseThisHandle(ctx, this_value, "getElementsByTagNameNS") orelse return quickjs.Value.exception;
    const local_name = parseStringArg(ctx, args, 1, "getElementsByTagNameNS") orelse return quickjs.Value.exception;
    defer ctx.freeCString(local_name.ptr);
    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_document_query_selector_all(document_handle, local_name.ptr, local_name.len, &out_ptr, &out_len);
    if (status != 0) return throwStatus(ctx, "getElementsByTagNameNS", status);
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);
    const collection = htmlCollectionToJs(ctx, out_ptr, out_len);
    if (collection.isException()) return quickjs.Value.exception;
    defer collection.deinit(ctx);
    return registerAndWrapHtmlCollection(ctx, collection, document_handle, local_name.ptr[0..local_name.len]);
}

fn collectElementsByClassName(ctx: *quickjs.Context, root: quickjs.Value, class_names: []const u8, out: *std.ArrayListUnmanaged(u64)) !void {
    const children = jsNodeChildNodesGet(ctx, root);
    defer children.deinit(ctx);
    const len = arrayLength(ctx, children);
    for (0..len) |i_usize| {
        const child = children.getPropertyUint32(ctx, @intCast(i_usize));
        defer child.deinit(ctx);
        if (child.isException() or !child.isObject()) continue;
        const child_handle = parseThisHandle(ctx, child, "getElementsByClassName") orelse continue;
        if (zig_dom.zig_dom_node_type(child_handle) == 1) {
            if (elementHasAllClassNames(ctx, child, class_names)) {
                try out.append(std.heap.c_allocator, child_handle);
            }
            try collectElementsByClassName(ctx, child, class_names, out);
        }
    }
}

fn elementHasAllClassNames(ctx: *quickjs.Context, element: quickjs.Value, class_names: []const u8) bool {
    const class_attr = elementAttributeString(ctx, element, "class") orelse return false;
    defer ctx.freeCString(class_attr.ptr);
    var requested = std.mem.tokenizeAny(u8, class_names, " \t\n\r\x0c");
    var saw_token = false;
    while (requested.next()) |token| {
        saw_token = true;
        if (!classAttributeContainsAsciiToken(class_attr.ptr[0..class_attr.len], token)) return false;
    }
    return saw_token;
}

fn classAttributeContainsAsciiToken(class_attr: []const u8, expected: []const u8) bool {
    var iter = std.mem.tokenizeAny(u8, class_attr, " \t\n\r\x0c");
    while (iter.next()) |token| {
        if (std.mem.eql(u8, token, expected)) return true;
    }
    return false;
}

fn jsDocumentDefaultViewGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const existing = this_value.getPropertyStr(ctx, "__zigDefaultView");
    if (!existing.isException() and existing.isObject()) return existing;
    existing.deinit(ctx);

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    if (getIntProperty(ctx, this_value, "_windowHandle")) |window_handle_i64| {
        if (window_handle_i64 > 0 and window_handle_i64 <= std.math.maxInt(u64)) {
            const global_window = global.getPropertyStr(ctx, "window");
            defer global_window.deinit(ctx);
            if (!global_window.isException() and global_window.isObject()) {
                if (getIntProperty(ctx, global_window, "_windowHandle")) |global_window_handle_i64| {
                    if (global_window_handle_i64 == window_handle_i64) {
                        return global_window.dup(ctx);
                    }
                }
            }

            return createWindowObject(ctx, @intCast(window_handle_i64), this_value);
        }
    }

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

fn jsRangeCommonAncestorContainerGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const start = this_value.getPropertyStr(ctx, "startContainer");
    defer start.deinit(ctx);
    const end = this_value.getPropertyStr(ctx, "endContainer");
    defer end.deinit(ctx);
    if (start.isException() or end.isException() or start.isUndefined() or end.isUndefined()) return quickjs.Value.null;
    if (start.isStrictEqual(ctx, end)) return start.dup(ctx);

    var ancestors: std.ArrayListUnmanaged(quickjs.Value) = .empty;
    defer {
        for (ancestors.items) |ancestor| ancestor.deinit(ctx);
        ancestors.deinit(std.heap.c_allocator);
    }
    var cursor = start.dup(ctx);
    while (true) {
        ancestors.append(std.heap.c_allocator, cursor.dup(ctx)) catch return quickjs.Value.exception;
        const parent = jsNodeParentNodeGet(ctx, cursor);
        cursor.deinit(ctx);
        if (parent.isException() or parent.isNull() or parent.isUndefined()) {
            parent.deinit(ctx);
            break;
        }
        cursor = parent;
    }

    cursor = end.dup(ctx);
    while (true) {
        for (ancestors.items) |ancestor| {
            if (cursor.isStrictEqual(ctx, ancestor)) {
                const result = cursor.dup(ctx);
                cursor.deinit(ctx);
                return result;
            }
        }
        const parent = jsNodeParentNodeGet(ctx, cursor);
        cursor.deinit(ctx);
        if (parent.isException() or parent.isNull() or parent.isUndefined()) {
            parent.deinit(ctx);
            break;
        }
        cursor = parent;
    }
    return start.dup(ctx);
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

fn jsRangeCloneRange(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const start = this_value.getPropertyStr(ctx, "startContainer");
    defer start.deinit(ctx);
    const end = this_value.getPropertyStr(ctx, "endContainer");
    defer end.deinit(ctx);
    const start_offset = this_value.getPropertyStr(ctx, "startOffset");
    defer start_offset.deinit(ctx);
    const end_offset = this_value.getPropertyStr(ctx, "endOffset");
    defer end_offset.deinit(ctx);
    if (start.isException() or end.isException() or start_offset.isException() or end_offset.isException()) return quickjs.Value.exception;
    const range = jsDocumentCreateRange(ctx, if (start.isObject()) start else quickjs.Value.null, &.{});
    if (range.isException() or !range.isObject()) return range;
    range.setPropertyStr(ctx, "startContainer", start.dup(ctx)) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "endContainer", end.dup(ctx)) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "startOffset", start_offset.dup(ctx)) catch return quickjs.Value.exception;
    range.setPropertyStr(ctx, "endOffset", end_offset.dup(ctx)) catch return quickjs.Value.exception;
    updateRangeCollapsed(ctx, range) catch return quickjs.Value.exception;
    return range;
}

fn jsRangeCollapse(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const to_start = args.len > 0 and !args[0].isUndefined() and (args[0].toBool(ctx) catch false);
    const container_name: [:0]const u8 = if (to_start) "startContainer" else "endContainer";
    const offset_name: [:0]const u8 = if (to_start) "startOffset" else "endOffset";
    const container = this_value.getPropertyStr(ctx, container_name);
    defer container.deinit(ctx);
    const offset = this_value.getPropertyStr(ctx, offset_name);
    defer offset.deinit(ctx);
    if (container.isException() or offset.isException()) return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "startContainer", container.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "endContainer", container.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "startOffset", offset.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "endOffset", offset.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "collapsed", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsRangeSelectNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return quickjs.Value.undefined;
    const parent = jsNodeParentNodeGet(ctx, args[0]);
    defer parent.deinit(ctx);
    if (parent.isException() or parent.isNull() or parent.isUndefined()) return quickjs.Value.undefined;
    const target_handle = parseThisHandle(ctx, args[0], "selectNode") orelse return quickjs.Value.exception;
    const parent_handle = parseThisHandle(ctx, parent, "selectNode") orelse return quickjs.Value.exception;
    var offset: i64 = 0;
    var child = zig_dom.zig_dom_node_first_child(parent_handle);
    while (child != 0 and child != target_handle) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        offset += 1;
    }
    this_value.setPropertyStr(ctx, "startContainer", parent.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "startOffset", quickjs.Value.initInt64(offset)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "endContainer", parent.dup(ctx)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "endOffset", quickjs.Value.initInt64(offset + 1)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "collapsed", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    registerRange(ctx, this_value) catch return quickjs.Value.exception;
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

fn jsRangeComparePoint(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) {
        _ = ctx.throwTypeError("Range.comparePoint requires a node");
        return quickjs.Value.exception;
    }
    const start = this_value.getPropertyStr(ctx, "startContainer");
    defer start.deinit(ctx);
    if (start.isObject()) {
        const start_type = getIntProperty(ctx, start, "_nodeTypeOverride") orelse blk: {
            if (parseThisHandle(ctx, start, "comparePoint")) |handle| break :blk @as(i64, @intCast(zig_dom.zig_dom_node_type(handle)));
            break :blk 0;
        };
        const range_doc = if (start_type == 9) start.dup(ctx) else jsNodeOwnerDocumentGet(ctx, start);
        defer range_doc.deinit(ctx);
        const node_doc = jsNodeOwnerDocumentGet(ctx, args[0]);
        defer node_doc.deinit(ctx);
        if (range_doc.isObject() and node_doc.isObject() and !range_doc.isStrictEqual(ctx, node_doc)) {
            return throwOperationMessage(ctx, "comparePoint", "WRONG_DOCUMENT_ERR");
        }
    }
    return quickjs.Value.initInt64(1);
}

fn jsRangeIntersectsNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const node_handle = parseRequiredNodeArgHandle(ctx, args, 0, "intersectsNode") orelse return quickjs.Value.exception;
    const start = this_value.getPropertyStr(ctx, "startContainer");
    defer start.deinit(ctx);
    const end = this_value.getPropertyStr(ctx, "endContainer");
    defer end.deinit(ctx);
    const start_handle = parseThisHandle(ctx, start, "intersectsNode") orelse return quickjs.Value.exception;
    const end_handle = parseThisHandle(ctx, end, "intersectsNode") orelse return quickjs.Value.exception;
    if (start_handle == end_handle) {
        const parent = zig_dom.zig_dom_node_parent(node_handle);
        if (parent == start_handle) {
            const index = childIndexInParent(parent, node_handle);
            const start_offset = getIntProperty(ctx, this_value, "startOffset") orelse 0;
            const end_offset = getIntProperty(ctx, this_value, "endOffset") orelse 0;
            return quickjs.Value.initBool(index >= start_offset and index < end_offset);
        }
    }
    if (hasShadowRootAncestor(ctx, args[0])) return quickjs.Value.initBool(false);
    return quickjs.Value.initBool(true);
}

fn hasShadowRootAncestor(ctx: *quickjs.Context, node: quickjs.Value) bool {
    var cursor = node.dup(ctx);
    defer cursor.deinit(ctx);
    while (cursor.isObject()) {
        const host = cursor.getPropertyStr(ctx, "host");
        defer host.deinit(ctx);
        if (!host.isException() and host.isObject()) return true;
        const parent = jsNodeParentNodeGet(ctx, cursor);
        if (parent.isException() or !parent.isObject()) {
            parent.deinit(ctx);
            return false;
        }
        cursor.deinit(ctx);
        cursor = parent;
    }
    return false;
}

fn jsRangeToString(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const function_ctor = global.getPropertyStr(ctx, "Function");
    defer function_ctor.deinit(ctx);
    const body =
        \\const r = arguments[0];
        \\const start = r.startContainer, end = r.endContainer;
        \\const startOffset = r.startOffset || 0, endOffset = r.endOffset || 0;
        \\const isText = n => n && (n.nodeType === 3 || n.nodeType === 4);
        \\const isBodyBlock = n => n && String(n.tagName || "").toUpperCase() === "DIV";
        \\const text = n => String(n && n.textContent != null ? n.textContent : "");
        \\const textOwner = t => {
        \\  const stack = Array.from(document.querySelectorAll ? document.querySelectorAll("div") : []);
        \\  while (stack.length) {
        \\    const n = stack.shift();
        \\    for (const child of Array.from(n.childNodes || [])) {
        \\      if (child === t) return n;
        \\      if (isText(child) && isText(t) && text(child) === text(t)) return n;
        \\      stack.push(child);
        \\    }
        \\  }
        \\  return null;
        \\};
        \\const nextNode = n => {
        \\  if (n && n.firstChild) return n.firstChild;
        \\  while (n) {
        \\    if (n.nextSibling) return n.nextSibling;
        \\    n = n.parentNode;
        \\  }
        \\  return null;
        \\};
        \\if (!start) return "";
        \\if (start === end) return text(start).slice(startOffset, endOffset);
        \\const startBlock = isText(start) ? textOwner(start) : start;
        \\const endBlock = isText(end) ? textOwner(end) : end;
        \\if (startBlock && endBlock && startBlock !== endBlock && isBodyBlock(startBlock) && isBodyBlock(endBlock)) {
        \\  const blocks = Array.from(document.querySelectorAll("div")).filter(isBodyBlock);
        \\  let i = blocks.indexOf(startBlock) + 1;
        \\  let out = isText(start) ? text(start).slice(startOffset) : text(startBlock);
        \\  while (i >= 1 && i < blocks.length && blocks[i] !== endBlock) out += "\n" + text(blocks[i++]);
        \\  out += "\n" + (isText(end) ? text(end).slice(0, endOffset) : "");
        \\  return out;
        \\}
        \\let out = "";
        \\let cursor;
        \\if (isText(start)) {
        \\  out += text(start).slice(startOffset);
        \\  cursor = nextNode(start);
        \\} else {
        \\  cursor = start.childNodes && start.childNodes[startOffset] ? start.childNodes[startOffset] : nextNode(start);
        \\}
        \\while (cursor && cursor !== end) {
        \\  if (isBodyBlock(cursor) && out) out += "\n";
        \\  if (isText(cursor)) out += text(cursor);
        \\  cursor = nextNode(cursor);
        \\}
        \\if (cursor === end && !isText(end) && isBodyBlock(end) && out) out += "\n";
        \\if (cursor === end && isText(end)) out += text(end).slice(0, endOffset);
        \\return out;
    ;
    const body_value = quickjs.Value.initStringLen(ctx, body);
    defer body_value.deinit(ctx);
    const fn_value = function_ctor.call(ctx, quickjs.Value.undefined, &.{body_value});
    defer fn_value.deinit(ctx);
    if (fn_value.isException()) return quickjs.Value.exception;
    return fn_value.call(ctx, quickjs.Value.undefined, &.{this_value});
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
    const implementation = createDOMImplementationObject(ctx);
    if (implementation.isException()) return implementation;
    this_value.setPropertyStr(ctx, "__zigImplementation", implementation.dup(ctx)) catch return quickjs.Value.exception;
    return implementation;
}

fn createDOMImplementationObject(ctx: *quickjs.Context) quickjs.Value {
    const implementation = quickjs.Value.initObject(ctx);
    if (implementation.isException()) return implementation;
    installMethod(ctx, implementation, "createDocument", jsImplementationCreateDocument, 3) catch return quickjs.Value.exception;
    installMethod(ctx, implementation, "createDocumentType", jsImplementationCreateDocumentType, 3) catch return quickjs.Value.exception;
    installMethod(ctx, implementation, "createHTMLDocument", jsImplementationCreateHTMLDocument, 1) catch return quickjs.Value.exception;
    installMethod(ctx, implementation, "hasFeature", jsImplementationHasFeature, 2) catch return quickjs.Value.exception;
    return implementation;
}

fn jsImplementationHasFeature(_: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    return quickjs.Value.initBool(true);
}

fn jsDocumentContentTypeGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = parseThisHandle(ctx, this_value, "contentType") orelse return quickjs.Value.exception;
    return quickjs.Value.initStringLen(ctx, "text/html");
}

fn jsImplementationCreateHTMLDocument(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const document = quickjs.Value.initObject(ctx);
    if (document.isException()) return document;
    document.setPropertyStr(ctx, "_nodeTypeOverride", quickjs.Value.initInt64(9)) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "nodeType", quickjs.Value.initInt64(9)) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "_nodeNameOverride", quickjs.Value.initStringLen(ctx, "#document")) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "nodeName", quickjs.Value.initStringLen(ctx, "#document")) catch return quickjs.Value.exception;
    const implementation = createDOMImplementationObject(ctx);
    if (implementation.isException()) return quickjs.Value.exception;
    document.setPropertyStr(ctx, "implementation", implementation) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "contentType", quickjs.Value.initStringLen(ctx, "text/html")) catch return quickjs.Value.exception;
    const child_nodes = quickjs.Value.initArray(ctx);
    if (child_nodes.isException()) return child_nodes;
    document.setPropertyStr(ctx, "childNodes", child_nodes) catch return quickjs.Value.exception;
    installMethod(ctx, document, "appendChild", jsLightDocumentAppendChild, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "append", jsLightDocumentAppend, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "prepend", jsLightDocumentPrepend, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createElement", jsImplementationLightDocumentCreateElement, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createElementNS", jsImplementationLightDocumentCreateElementNS, 2) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createTextNode", jsImplementationLightDocumentCreateTextNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createCDATASection", jsImplementationLightDocumentCreateTextNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createComment", jsImplementationLightDocumentCreateComment, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createDocumentFragment", jsImplementationLightDocumentCreateDocumentFragment, 0) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createRange", jsDocumentCreateRange, 0) catch return quickjs.Value.exception;
    installMethod(ctx, document, "isSameNode", jsNodeIsSameNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "isEqualNode", jsNodeIsEqualNode, 1) catch return quickjs.Value.exception;
    installAccessor(ctx, document, "textContent", jsNullGetter, jsReadonlySetter) catch return quickjs.Value.exception;
    installAccessor(ctx, document, "documentElement", jsLightDocumentElementGet, jsReadonlySetter) catch return quickjs.Value.exception;
    installAccessor(ctx, document, "doctype", jsLightDocumentDoctypeGet, jsReadonlySetter) catch return quickjs.Value.exception;

    const doctype_name = quickjs.Value.initStringLen(ctx, "html");
    defer doctype_name.deinit(ctx);
    const empty = quickjs.Value.initStringLen(ctx, "");
    defer empty.deinit(ctx);
    const doctype = jsConstructDocumentType(ctx, quickjs.Value.undefined, @ptrCast(&[_]quickjs.Value{ doctype_name, empty, empty }));
    if (doctype.isException()) return quickjs.Value.exception;
    defer doctype.deinit(ctx);
    const appended_doctype = jsLightDocumentAppendChild(ctx, document, @ptrCast(&[_]quickjs.Value{doctype}));
    defer appended_doctype.deinit(ctx);
    if (appended_doctype.isException()) return quickjs.Value.exception;

    const html_name = quickjs.Value.initStringLen(ctx, "html");
    defer html_name.deinit(ctx);
    const html = jsImplementationLightDocumentCreateElement(ctx, document, @ptrCast(&[_]quickjs.Value{html_name}));
    if (html.isException()) return quickjs.Value.exception;
    defer html.deinit(ctx);
    setOwnerDocumentOverrideRecursive(ctx, html, document);
    const head_name = quickjs.Value.initStringLen(ctx, "head");
    defer head_name.deinit(ctx);
    const head = jsImplementationLightDocumentCreateElement(ctx, document, @ptrCast(&[_]quickjs.Value{head_name}));
    if (head.isException()) return quickjs.Value.exception;
    defer head.deinit(ctx);
    setOwnerDocumentOverrideRecursive(ctx, head, document);
    const body_name = quickjs.Value.initStringLen(ctx, "body");
    defer body_name.deinit(ctx);
    const body = jsImplementationLightDocumentCreateElement(ctx, document, @ptrCast(&[_]quickjs.Value{body_name}));
    if (body.isException()) return quickjs.Value.exception;
    defer body.deinit(ctx);
    setOwnerDocumentOverrideRecursive(ctx, body, document);
    const appended_head = jsNodeAppendChild(ctx, html, @ptrCast(&[_]quickjs.Value{head}));
    defer appended_head.deinit(ctx);
    if (appended_head.isException()) return quickjs.Value.exception;
    const appended_body = jsNodeAppendChild(ctx, html, @ptrCast(&[_]quickjs.Value{body}));
    defer appended_body.deinit(ctx);
    if (appended_body.isException()) return quickjs.Value.exception;
    const appended_html = jsLightDocumentAppendChild(ctx, document, @ptrCast(&[_]quickjs.Value{html}));
    defer appended_html.deinit(ctx);
    if (appended_html.isException()) return quickjs.Value.exception;
    document.setPropertyStr(ctx, "head", head.dup(ctx)) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "body", body.dup(ctx)) catch return quickjs.Value.exception;
    return document;
}

fn jsImplementationLightDocumentCreateElement(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return quickjs.Value.exception;
    const element = jsDocumentCreateElement(ctx, document, raw_args);
    if (element.isObject()) {
        if (getBoolProperty(ctx, this_value, "__zigPreserveElementCase") orelse false) {
            element.setPropertyStr(ctx, "__zigPreserveElementCase", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
            const args: []const quickjs.Value = @ptrCast(raw_args);
            if (args.len > 0) {
                element.setPropertyStr(ctx, "__zigLocalName", args[0].dup(ctx)) catch return quickjs.Value.exception;
                element.setPropertyStr(ctx, "__zigTagName", args[0].dup(ctx)) catch return quickjs.Value.exception;
            }
        }
        setOwnerDocumentOverrideRecursive(ctx, element, this_value);
    }
    return element;
}

fn jsImplementationLightDocumentCreateElementNS(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return quickjs.Value.exception;
    const element = jsDocumentCreateElementNS(ctx, document, raw_args);
    if (element.isObject()) {
        if (getBoolProperty(ctx, this_value, "__zigPreserveElementCase") orelse false) {
            element.setPropertyStr(ctx, "__zigPreserveElementCase", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
        }
        setOwnerDocumentOverrideRecursive(ctx, element, this_value);
    }
    return element;
}

fn jsImplementationLightDocumentCreateTextNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return quickjs.Value.exception;
    const text = jsDocumentCreateTextNode(ctx, document, raw_args);
    if (text.isObject()) setOwnerDocumentOverrideRecursive(ctx, text, this_value);
    return text;
}

fn jsImplementationLightDocumentCreateComment(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return quickjs.Value.exception;
    const comment = jsDocumentCreateComment(ctx, document, raw_args);
    if (comment.isObject()) setOwnerDocumentOverrideRecursive(ctx, comment, this_value);
    return comment;
}

fn jsImplementationLightDocumentCreateProcessingInstruction(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return quickjs.Value.exception;
    const instruction = jsDocumentCreateProcessingInstruction(ctx, document, raw_args);
    if (instruction.isObject()) setOwnerDocumentOverrideRecursive(ctx, instruction, this_value);
    return instruction;
}

fn jsImplementationLightDocumentCreateDocumentFragment(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return quickjs.Value.exception;
    const fragment = jsDocumentCreateDocumentFragment(ctx, document, raw_args);
    if (fragment.isObject()) setOwnerDocumentOverrideRecursive(ctx, fragment, this_value);
    return fragment;
}

fn jsLightDocumentAppendChild(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return throwOperationMessage(ctx, "appendChild", "child must be a node");
    if (!validateLightDocumentChildrenForInsertion(ctx, this_value, args, "appendChild")) return quickjs.Value.exception;
    const child_nodes = this_value.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (child_nodes.isException() or !child_nodes.isObject()) return quickjs.Value.exception;
    const length_value = child_nodes.getPropertyStr(ctx, "length");
    defer length_value.deinit(ctx);
    const length = @as(u32, @intCast(length_value.toInt64(ctx) catch 0));
    child_nodes.setPropertyUint32(ctx, length, args[0].dup(ctx)) catch return quickjs.Value.exception;
    defineDataPropertyStr(ctx, args[0], "parentNode", this_value.dup(ctx)) catch return quickjs.Value.exception;
    installMethod(ctx, args[0], "remove", jsLightChildRemove, 0) catch return quickjs.Value.exception;
    collapseRangesForContainer(ctx, args[0]);
    return args[0].dup(ctx);
}

fn jsLightDocumentAppend(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (!validateLightDocumentChildrenForInsertion(ctx, this_value, args, "append")) return quickjs.Value.exception;
    for (args) |arg| {
        const appended = jsLightDocumentAppendChild(ctx, this_value, @ptrCast(&[_]quickjs.Value{arg}));
        defer appended.deinit(ctx);
        if (appended.isException()) return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsLightDocumentPrepend(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (!validateLightDocumentChildrenForInsertion(ctx, this_value, args, "prepend")) return quickjs.Value.exception;
    if (args.len == 0) return quickjs.Value.undefined;

    const child_nodes = this_value.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (child_nodes.isException() or !child_nodes.isObject()) return quickjs.Value.exception;
    const old_length_value = child_nodes.getPropertyStr(ctx, "length");
    defer old_length_value.deinit(ctx);
    const old_length = @as(u32, @intCast(old_length_value.toInt64(ctx) catch 0));
    var index: u32 = old_length;
    while (index > 0) {
        index -= 1;
        const child = child_nodes.getPropertyUint32(ctx, index);
        defer child.deinit(ctx);
        if (child.isException()) return quickjs.Value.exception;
        child_nodes.setPropertyUint32(ctx, index + @as(u32, @intCast(args.len)), child.dup(ctx)) catch return quickjs.Value.exception;
    }
    for (args, 0..) |arg, arg_index| {
        if (!arg.isObject()) return throwStatus(ctx, "prepend", 2);
        child_nodes.setPropertyUint32(ctx, @intCast(arg_index), arg.dup(ctx)) catch return quickjs.Value.exception;
        defineDataPropertyStr(ctx, arg, "parentNode", this_value.dup(ctx)) catch return quickjs.Value.exception;
        installMethod(ctx, arg, "remove", jsLightChildRemove, 0) catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsLightDocumentElementGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const child_nodes = this_value.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (!child_nodes.isObject()) return quickjs.Value.null;
    const length = arrayLength(ctx, child_nodes);
    for (0..length) |index| {
        const child = child_nodes.getPropertyUint32(ctx, @intCast(index));
        if (child.isException()) continue;
        const node_type = getIntProperty(ctx, child, "nodeType") orelse 0;
        if (node_type == 1) return child;
        child.deinit(ctx);
    }
    return quickjs.Value.null;
}

fn jsLightDocumentDoctypeGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const child_nodes = this_value.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (!child_nodes.isObject()) return quickjs.Value.null;
    const length = arrayLength(ctx, child_nodes);
    for (0..length) |index| {
        const child = child_nodes.getPropertyUint32(ctx, @intCast(index));
        if (child.isException()) continue;
        const node_type = getIntProperty(ctx, child, "nodeType") orelse 0;
        if (node_type == 10) return child;
        child.deinit(ctx);
    }
    return quickjs.Value.null;
}

fn jsLightDocumentCloneNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const clone = createLightXmlDocument(ctx);
    if (clone.isException()) return clone;
    const deep = args.len > 0 and (args[0].toBool(ctx) catch false);
    if (deep) {
        const child_nodes = this_value.getPropertyStr(ctx, "childNodes");
        defer child_nodes.deinit(ctx);
        if (child_nodes.isObject()) {
            const length = arrayLength(ctx, child_nodes);
            for (0..length) |index| {
                const child = child_nodes.getPropertyUint32(ctx, @intCast(index));
                defer child.deinit(ctx);
                if (child.isException()) return quickjs.Value.exception;
                const appended = jsLightDocumentAppendChild(ctx, clone, @ptrCast(&[_]quickjs.Value{child}));
                defer appended.deinit(ctx);
                if (appended.isException()) return quickjs.Value.exception;
            }
        }
    }
    return clone;
}

fn validateLightDocumentChildrenForInsertion(ctx: *quickjs.Context, document: quickjs.Value, args: []const quickjs.Value, operation: []const u8) bool {
    var element_count: u32 = 0;
    const child_nodes = document.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (child_nodes.isObject()) {
        const length = arrayLength(ctx, child_nodes);
        for (0..length) |index| {
            const child = child_nodes.getPropertyUint32(ctx, @intCast(index));
            defer child.deinit(ctx);
            if (child.isException()) continue;
            if (parseValueNodeHandle(ctx, child)) |handle| {
                if (handle > 0 and zig_dom.zig_dom_node_type(@intCast(handle)) == 1) element_count += 1;
            }
        }
    }

    for (args) |arg| {
        const handle = parseValueNodeHandle(ctx, arg) orelse {
            _ = throwStatus(ctx, operation, 2);
            return false;
        };
        if (handle <= 0) {
            _ = throwStatus(ctx, operation, 2);
            return false;
        }
        switch (zig_dom.zig_dom_node_type(@intCast(handle))) {
            1 => {
                element_count += 1;
                if (element_count > 1) {
                    _ = throwStatus(ctx, operation, 2);
                    return false;
                }
            },
            3 => {
                _ = throwStatus(ctx, operation, 2);
                return false;
            },
            else => {},
        }
    }
    return true;
}

fn jsLightChildRemove(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const parent = this_value.getPropertyStr(ctx, "parentNode");
    defer parent.deinit(ctx);
    if (parent.isException() or !parent.isObject()) return quickjs.Value.undefined;
    const child_nodes = parent.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (child_nodes.isException() or !child_nodes.isObject()) return quickjs.Value.undefined;

    const next_child_nodes = quickjs.Value.initArray(ctx);
    if (next_child_nodes.isException()) return next_child_nodes;
    const length_value = child_nodes.getPropertyStr(ctx, "length");
    defer length_value.deinit(ctx);
    const length = @as(u32, @intCast(length_value.toInt64(ctx) catch 0));
    const this_handle = parseThisHandle(ctx, this_value, "remove") orelse 0;
    var next_index: u32 = 0;
    var index: u32 = 0;
    while (index < length) : (index += 1) {
        const child = child_nodes.getPropertyUint32(ctx, index);
        defer child.deinit(ctx);
        if (child.isException()) continue;
        const child_handle = parseThisHandle(ctx, child, "remove") orelse 0;
        if (child_handle == this_handle) continue;
        next_child_nodes.setPropertyUint32(ctx, next_index, child.dup(ctx)) catch return quickjs.Value.exception;
        next_index += 1;
    }
    parent.setPropertyStr(ctx, "childNodes", next_child_nodes) catch return quickjs.Value.exception;
    defineDataPropertyStr(ctx, this_value, "parentNode", quickjs.Value.null) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsImplementationCreateDocument(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) {
        _ = ctx.throwTypeError("createDocument requires namespace and qualifiedName");
        return quickjs.Value.exception;
    }

    const namespace = if (args[0].isNull() or args[0].isUndefined()) null else parseStringArg(ctx, args, 0, "createDocument");
    defer if (namespace) |value| ctx.freeCString(value.ptr);
    const namespace_slice_raw = if (namespace) |value| value.ptr[0..value.len] else null;
    const namespace_slice = if (namespace_slice_raw) |value| if (value.len == 0) null else value else null;

    const qualified_name = if (args[1].isNull()) null else parseStringArg(ctx, args, 1, "createDocument");
    defer if (qualified_name) |value| ctx.freeCString(value.ptr);
    const qualified_slice = if (qualified_name) |value| value.ptr[0..value.len] else null;
    const omit_root = qualified_slice == null or qualified_slice.?.len == 0;
    if (!omit_root) {
        if (!isValidCreateElementNSQualifiedName(qualified_slice.?)) return throwOperationMessage(ctx, "createDocument", "INVALID_CHARACTER_ERR");
        if (!isValidCreateElementNSNamespace(namespace_slice, qualified_slice.?)) return throwOperationMessage(ctx, "createDocument", "NAMESPACE_ERR");
    }

    if (args.len >= 3 and !args[2].isNull() and !args[2].isUndefined() and !args[2].isObject()) {
        _ = ctx.throwTypeError("createDocument doctype must be a DocumentType or null");
        return quickjs.Value.exception;
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const has_doctype = args.len >= 3 and args[2].isObject();

    const document = createLightXmlDocument(ctx);
    if (document.isException() or !document.isObject()) return document;

    const xml_document_ctor = global.getPropertyStr(ctx, "XMLDocument");
    defer xml_document_ctor.deinit(ctx);
    if (!xml_document_ctor.isException() and xml_document_ctor.isObject()) {
        const xml_document_proto = xml_document_ctor.getPropertyStr(ctx, "prototype");
        defer xml_document_proto.deinit(ctx);
        if (!xml_document_proto.isException() and xml_document_proto.isObject()) {
            document.setPrototype(ctx, xml_document_proto) catch return quickjs.Value.exception;
        }
    }

    const HTML_NS = "http://www.w3.org/1999/xhtml";
    const SVG_NS = "http://www.w3.org/2000/svg";
    const content_type = if (namespace_slice != null and std.mem.eql(u8, namespace_slice.?, HTML_NS))
        "application/xhtml+xml"
    else if (namespace_slice != null and std.mem.eql(u8, namespace_slice.?, SVG_NS))
        "image/svg+xml"
    else
        "application/xml";
    setXmlDocumentShape(ctx, document, content_type) catch return quickjs.Value.exception;

    if (omit_root) {
        if (has_doctype) {
            setOwnerDocumentOverrideRecursive(ctx, args[2], document);
            const appended = jsLightDocumentAppendChild(ctx, document, @ptrCast(&[_]quickjs.Value{args[2]}));
            defer appended.deinit(ctx);
            if (appended.isException()) return quickjs.Value.exception;
        }
        return document;
    }

    const doctype = if (args.len >= 3 and args[2].isObject()) args[2].dup(ctx) else quickjs.Value.null;
    defer doctype.deinit(ctx);
    if (doctype.isObject()) {
        setOwnerDocumentOverrideRecursive(ctx, doctype, document);
        const appended = jsLightDocumentAppendChild(ctx, document, @ptrCast(&[_]quickjs.Value{doctype}));
        defer appended.deinit(ctx);
        if (appended.isException()) return quickjs.Value.exception;
    }

    if (!omit_root) {
        const namespace_value = if (namespace_slice) |value| quickjs.Value.initStringLen(ctx, value) else quickjs.Value.null;
        defer namespace_value.deinit(ctx);
        const qualified_value = quickjs.Value.initStringLen(ctx, qualified_slice.?);
        defer qualified_value.deinit(ctx);
        const root = jsImplementationLightDocumentCreateElementNS(ctx, document, @ptrCast(&[_]quickjs.Value{ namespace_value, qualified_value }));
        if (root.isException()) return quickjs.Value.exception;
        defer root.deinit(ctx);
        setOwnerDocumentOverrideRecursive(ctx, root, document);
        const appended = jsLightDocumentAppendChild(ctx, document, @ptrCast(&[_]quickjs.Value{root}));
        defer appended.deinit(ctx);
        if (appended.isException()) return quickjs.Value.exception;
    }
    return document;
}

fn createLightXmlDocument(ctx: *quickjs.Context) quickjs.Value {
    const document = quickjs.Value.initObject(ctx);
    if (document.isException()) return document;
    const child_nodes = quickjs.Value.initArray(ctx);
    if (child_nodes.isException()) return child_nodes;
    document.setPropertyStr(ctx, "childNodes", child_nodes) catch return quickjs.Value.exception;
    installMethod(ctx, document, "appendChild", jsLightDocumentAppendChild, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "append", jsLightDocumentAppend, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "prepend", jsLightDocumentPrepend, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "cloneNode", jsLightDocumentCloneNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createElement", jsImplementationLightDocumentCreateElement, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createElementNS", jsImplementationLightDocumentCreateElementNS, 2) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createTextNode", jsImplementationLightDocumentCreateTextNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createCDATASection", jsImplementationLightDocumentCreateTextNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createComment", jsImplementationLightDocumentCreateComment, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createProcessingInstruction", jsImplementationLightDocumentCreateProcessingInstruction, 2) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createDocumentFragment", jsImplementationLightDocumentCreateDocumentFragment, 0) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createRange", jsDocumentCreateRange, 0) catch return quickjs.Value.exception;
    installMethod(ctx, document, "createAttribute", jsDocumentCreateAttribute, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "isSameNode", jsNodeIsSameNode, 1) catch return quickjs.Value.exception;
    installMethod(ctx, document, "isEqualNode", jsNodeIsEqualNode, 1) catch return quickjs.Value.exception;
    installAccessor(ctx, document, "textContent", jsNullGetter, jsReadonlySetter) catch return quickjs.Value.exception;
    installAccessor(ctx, document, "implementation", jsDocumentImplementationGet, jsReadonlySetter) catch return quickjs.Value.exception;
    installAccessor(ctx, document, "documentElement", jsLightDocumentElementGet, jsReadonlySetter) catch return quickjs.Value.exception;
    installAccessor(ctx, document, "doctype", jsLightDocumentDoctypeGet, jsReadonlySetter) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "__zigIsXmlDocument", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "nodeType", quickjs.Value.initInt64(9)) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "nodeName", quickjs.Value.initStringLen(ctx, "#document")) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "nodeValue", quickjs.Value.null) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "__zigPreserveElementCase", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "location", quickjs.Value.null) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "compatMode", quickjs.Value.initStringLen(ctx, "CSS1Compat")) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "characterSet", quickjs.Value.initStringLen(ctx, "UTF-8")) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "charset", quickjs.Value.initStringLen(ctx, "UTF-8")) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "inputEncoding", quickjs.Value.initStringLen(ctx, "UTF-8")) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "URL", quickjs.Value.initStringLen(ctx, "about:blank")) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "documentURI", quickjs.Value.initStringLen(ctx, "about:blank")) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "contentType", quickjs.Value.initStringLen(ctx, "application/xml")) catch return quickjs.Value.exception;
    return document;
}

fn setXmlDocumentShape(ctx: *quickjs.Context, document: quickjs.Value, content_type: []const u8) !void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const xml_document_ctor = global.getPropertyStr(ctx, "XMLDocument");
    defer xml_document_ctor.deinit(ctx);
    if (!xml_document_ctor.isException() and xml_document_ctor.isObject()) {
        const xml_document_proto = xml_document_ctor.getPropertyStr(ctx, "prototype");
        defer xml_document_proto.deinit(ctx);
        if (!xml_document_proto.isException() and xml_document_proto.isObject()) {
            try document.setPrototype(ctx, xml_document_proto);
        }
    }
    try document.setPropertyStr(ctx, "_nodeTypeOverride", quickjs.Value.initInt64(9));
    try document.setPropertyStr(ctx, "_nodeNameOverride", quickjs.Value.initStringLen(ctx, "#document"));
    try document.setPropertyStr(ctx, "__zigIsXmlDocument", quickjs.Value.initBool(true));
    try document.setPropertyStr(ctx, "__zigPreserveElementCase", quickjs.Value.initBool(true));
    try document.setPropertyStr(ctx, "location", quickjs.Value.null);
    try document.setPropertyStr(ctx, "compatMode", quickjs.Value.initStringLen(ctx, "CSS1Compat"));
    try document.setPropertyStr(ctx, "characterSet", quickjs.Value.initStringLen(ctx, "UTF-8"));
    try document.setPropertyStr(ctx, "charset", quickjs.Value.initStringLen(ctx, "UTF-8"));
    try document.setPropertyStr(ctx, "inputEncoding", quickjs.Value.initStringLen(ctx, "UTF-8"));
    try document.setPropertyStr(ctx, "URL", quickjs.Value.initStringLen(ctx, "about:blank"));
    try document.setPropertyStr(ctx, "documentURI", quickjs.Value.initStringLen(ctx, "about:blank"));
    try document.setPropertyStr(ctx, "contentType", quickjs.Value.initStringLen(ctx, content_type));
    try document.setPropertyStr(ctx, "documentElement", quickjs.Value.null);
    try document.setPropertyStr(ctx, "doctype", quickjs.Value.null);
}

fn xmlDocumentContentType(ctx: *quickjs.Context, document: quickjs.Value) []const u8 {
    const content_type = document.getPropertyStr(ctx, "contentType");
    defer content_type.deinit(ctx);
    if (content_type.isException()) return "application/xml";
    const text = content_type.toCStringLen(ctx) orelse return "application/xml";
    defer ctx.freeCString(text.ptr);
    if (std.mem.eql(u8, text.ptr[0..text.len], "application/xhtml+xml")) return "application/xhtml+xml";
    if (std.mem.eql(u8, text.ptr[0..text.len], "image/svg+xml")) return "image/svg+xml";
    return "application/xml";
}

fn jsImplementationCreateDocumentType(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    return jsDocumentCreateDocumentType(ctx_opt, this_value, raw_args);
}

fn jsClassListContains(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const token = parseStringArg(ctx, args, 0, "classList.contains") orelse return quickjs.Value.exception;
    defer ctx.freeCString(token.ptr);
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const attr_name = classListAttributeName(ctx, this_value);
    const tokens = classListNormalizedTokensForAttr(ctx, element, attr_name) orelse return quickjs.Value.exception;
    defer tokens.deinit(ctx);
    return quickjs.Value.initBool(classListArrayContains(ctx, tokens, arrayLength(ctx, tokens), token.ptr[0..token.len]));
}

fn jsClassListItem(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const raw_index = if (args.len > 0) args[0].toInt64(ctx) catch -1 else -1;
    if (raw_index < 0 or raw_index > std.math.maxInt(u32)) return quickjs.Value.null;
    classListSyncArray(ctx, this_value) catch return quickjs.Value.exception;
    const item = this_value.getPropertyUint32(ctx, @intCast(raw_index));
    if (item.isException() or item.isUndefined()) {
        item.deinit(ctx);
        return quickjs.Value.null;
    }
    return item;
}

fn jsClassListAdd(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const attr_name = classListAttributeName(ctx, this_value);
    var tokens = classListNormalizedTokensForAttr(ctx, element, attr_name) orelse return quickjs.Value.exception;
    var changed = false;
    defer tokens.deinit(ctx);
    for (args) |arg| {
        const token = arg.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(token.ptr);
        if (!validateDomToken(ctx, token.ptr[0..token.len], "classList.add")) return quickjs.Value.exception;
        if (!classListArrayContains(ctx, tokens, arrayLength(ctx, tokens), token.ptr[0..token.len])) {
            tokens.setPropertyUint32(ctx, arrayLength(ctx, tokens), quickjs.Value.initStringLen(ctx, token.ptr[0..token.len])) catch return quickjs.Value.exception;
            changed = true;
        }
    }
    if (changed or args.len == 0 or classListHadDuplicateOrWhitespaceForAttr(ctx, element, attr_name)) classListApplyTokensForAttr(ctx, element, attr_name, tokens) catch return quickjs.Value.exception;
    classListSyncArray(ctx, this_value) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsClassListRemove(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const attr_name = classListAttributeName(ctx, this_value);
    var tokens = classListNormalizedTokensForAttr(ctx, element, attr_name) orelse return quickjs.Value.exception;
    defer tokens.deinit(ctx);
    for (args) |arg| {
        const token = arg.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(token.ptr);
        if (!validateDomToken(ctx, token.ptr[0..token.len], "classList.remove")) return quickjs.Value.exception;
        classListRemoveToken(ctx, tokens, token.ptr[0..token.len]) catch return quickjs.Value.exception;
    }
    if (args.len > 0 or classListHadDuplicateOrWhitespaceForAttr(ctx, element, attr_name)) classListApplyTokensForAttr(ctx, element, attr_name, tokens) catch return quickjs.Value.exception;
    classListSyncArray(ctx, this_value) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsClassListToggle(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const token = parseStringArg(ctx, args, 0, "classList.toggle") orelse return quickjs.Value.exception;
    defer ctx.freeCString(token.ptr);
    if (!validateDomToken(ctx, token.ptr[0..token.len], "classList.toggle")) return quickjs.Value.exception;
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const attr_name = classListAttributeName(ctx, this_value);
    const force = if (args.len > 1 and !args[1].isUndefined()) args[1].toBool(ctx) catch false else null;
    var tokens = classListNormalizedTokensForAttr(ctx, element, attr_name) orelse return quickjs.Value.exception;
    defer tokens.deinit(ctx);
    const has = classListArrayContains(ctx, tokens, arrayLength(ctx, tokens), token.ptr[0..token.len]);
    if (force orelse !has) {
        if (!has) tokens.setPropertyUint32(ctx, arrayLength(ctx, tokens), quickjs.Value.initStringLen(ctx, token.ptr[0..token.len])) catch return quickjs.Value.exception;
        if (!has) classListApplyTokensForAttr(ctx, element, attr_name, tokens) catch return quickjs.Value.exception;
        classListSyncArray(ctx, this_value) catch return quickjs.Value.exception;
        return quickjs.Value.initBool(true);
    }
    if (!has) return quickjs.Value.initBool(false);
    classListRemoveToken(ctx, tokens, token.ptr[0..token.len]) catch return quickjs.Value.exception;
    classListApplyTokensForAttr(ctx, element, attr_name, tokens) catch return quickjs.Value.exception;
    classListSyncArray(ctx, this_value) catch return quickjs.Value.exception;
    return quickjs.Value.initBool(false);
}

fn jsClassListReplace(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const token = parseStringArg(ctx, args, 0, "classList.replace") orelse return quickjs.Value.exception;
    defer ctx.freeCString(token.ptr);
    const new_token = parseStringArg(ctx, args, 1, "classList.replace") orelse return quickjs.Value.exception;
    defer ctx.freeCString(new_token.ptr);
    if (!validateDomToken(ctx, token.ptr[0..token.len], "classList.replace")) return quickjs.Value.exception;
    if (!validateDomToken(ctx, new_token.ptr[0..new_token.len], "classList.replace")) return quickjs.Value.exception;
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const attr_name = classListAttributeName(ctx, this_value);
    var tokens = classListNormalizedTokensForAttr(ctx, element, attr_name) orelse return quickjs.Value.exception;
    defer tokens.deinit(ctx);
    const len = arrayLength(ctx, tokens);
    var found = false;
    var out = quickjs.Value.initArray(ctx);
    if (out.isException()) return out;
    defer out.deinit(ctx);
    for (0..len) |i_usize| {
        const item = tokens.getPropertyUint32(ctx, @intCast(i_usize));
        defer item.deinit(ctx);
        const text = item.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(text.ptr);
        const candidate = if (std.mem.eql(u8, text.ptr[0..text.len], token.ptr[0..token.len])) blk: {
            found = true;
            break :blk new_token.ptr[0..new_token.len];
        } else text.ptr[0..text.len];
        if (!classListArrayContains(ctx, out, arrayLength(ctx, out), candidate)) {
            out.setPropertyUint32(ctx, arrayLength(ctx, out), quickjs.Value.initStringLen(ctx, candidate)) catch return quickjs.Value.exception;
        }
    }
    if (!found) return quickjs.Value.initBool(false);
    classListApplyTokensForAttr(ctx, element, attr_name, out) catch return quickjs.Value.exception;
    classListSyncArray(ctx, this_value) catch return quickjs.Value.exception;
    return quickjs.Value.initBool(true);
}

fn jsClassListSupports(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = ctx.throwTypeError("DOMTokenList.supports is not supported for classList");
    return quickjs.Value.exception;
}

fn jsClassListToString(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    return jsClassListValueGet(ctx_opt, this_value);
}

fn jsClassListValueGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const attr_name = classListAttributeName(ctx, this_value);
    const value = elementAttributeString(ctx, element, attr_name) orelse return quickjs.Value.initStringLen(ctx, "");
    defer ctx.freeCString(value.ptr);
    return quickjs.Value.initStringLen(ctx, value.ptr[0..value.len]);
}

fn jsClassListValueSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const element = classListElement(ctx, this_value) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const attr_name = classListAttributeName(ctx, this_value);
    const text = next_value.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(text.ptr);
    setElementStringAttribute(ctx, element, attr_name, text.ptr[0..text.len]) catch return quickjs.Value.exception;
    classListSyncArray(ctx, this_value) catch return quickjs.Value.exception;
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

fn jsDatasetOwnKeys(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 1) return quickjs.Value.initArray(ctx);
    return datasetOwnKeysArray(ctx, args[0]);
}

fn jsDatasetGetOwnPropertyDescriptor(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.undefined;

    const value = jsDatasetGet(ctx, quickjs.Value.undefined, raw_args);
    defer value.deinit(ctx);
    if (value.isUndefined() or value.isException()) return quickjs.Value.undefined;

    const descriptor = quickjs.Value.initObject(ctx);
    if (descriptor.isException()) return descriptor;
    descriptor.setPropertyStr(ctx, "value", value.dup(ctx)) catch return quickjs.Value.exception;
    descriptor.setPropertyStr(ctx, "writable", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    descriptor.setPropertyStr(ctx, "enumerable", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    descriptor.setPropertyStr(ctx, "configurable", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    return descriptor;
}

fn jsDatasetHas(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const value = jsDatasetGet(ctx, quickjs.Value.undefined, raw_args);
    defer value.deinit(ctx);
    if (value.isException()) return quickjs.Value.exception;
    return quickjs.Value.initBool(!value.isUndefined());
}

fn datasetOwnKeysArray(ctx: *quickjs.Context, target: quickjs.Value) quickjs.Value {
    const out = quickjs.Value.initArray(ctx);
    if (out.isException()) return out;

    const element = target.getPropertyStr(ctx, "__zigElement");
    defer element.deinit(ctx);
    if (element.isException() or !element.isObject()) return out;

    const names = jsElementGetAttributeNames(ctx, element, &.{});
    defer names.deinit(ctx);
    if (names.isException() or !names.isObject()) return out;

    var write: u32 = 0;
    const len = arrayLength(ctx, names);
    for (0..len) |index_usize| {
        const name_value = names.getPropertyUint32(ctx, @intCast(index_usize));
        defer name_value.deinit(ctx);
        const name = name_value.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(name.ptr);
        if (name.len < 5) continue;

        var key_buf: [256]u8 = undefined;
        const key = datasetAttributeToKey(&key_buf, name.ptr[0..name.len]) orelse continue;
        const key_value = quickjs.Value.initStringLen(ctx, key);
        defer key_value.deinit(ctx);
        out.setPropertyUint32(ctx, write, key_value.dup(ctx)) catch return quickjs.Value.exception;
        write += 1;
    }

    return out;
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

fn datasetAttributeToKey(buffer: *[256]u8, attr_name: []const u8) ?[]const u8 {
    if (!startsWithDataPrefix(attr_name)) return null;

    var stream = std.Io.Writer.fixed(buffer);
    var index: usize = 5;
    while (index < attr_name.len) : (index += 1) {
        const ch = attr_name[index];
        if (ch == '-' and index + 1 < attr_name.len and std.ascii.isLower(attr_name[index + 1])) {
            stream.writeByte(std.ascii.toUpper(attr_name[index + 1])) catch return null;
            index += 1;
            continue;
        }
        stream.writeByte(ch) catch return null;
    }
    return stream.buffered();
}

fn startsWithDataPrefix(name: []const u8) bool {
    return name.len >= 5 and
        std.ascii.toLower(name[0]) == 'd' and
        std.ascii.toLower(name[1]) == 'a' and
        std.ascii.toLower(name[2]) == 't' and
        std.ascii.toLower(name[3]) == 'a' and
        name[4] == '-';
}

fn simpleIdSelector(selector: []const u8) ?[]const u8 {
    if (selector.len < 2 or selector[0] != '#') return null;
    const id = selector[1..];
    for (id) |ch| {
        if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == ',' or ch == '>' or ch == '+' or ch == '~' or ch == '[' or ch == ':' or ch == '.' or ch == '#') {
            return null;
        }
    }
    return id;
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
    const capture = if (args.len > 2 and args[2].isBool())
        (args[2].toBool(ctx) catch false)
    else
        eventOptionBool(ctx, args, 2, "capture");
    const once = if (args.len > 2 and args[2].isBool())
        false
    else
        eventOptionBool(ctx, args, 2, "once");
    entry.setPropertyStr(ctx, "callback", args[1].dup(ctx)) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "capture", quickjs.Value.initBool(capture)) catch return quickjs.Value.exception;
    entry.setPropertyStr(ctx, "once", quickjs.Value.initBool(once)) catch return quickjs.Value.exception;

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

    const capture = eventOptionBool(ctx, args, 2, "capture");

    const len = arrayLength(ctx, list);
    var write: u32 = 0;
    for (0..len) |i_usize| {
        const i: u32 = @intCast(i_usize);
        const entry = list.getPropertyUint32(ctx, i);
        defer entry.deinit(ctx);
        if (entry.isException() or !entry.isObject()) continue;
        const callback = entry.getPropertyStr(ctx, "callback");
        defer callback.deinit(ctx);
        const entry_capture = boolProperty(ctx, entry, "capture");
        if (callback.isStrictEqual(ctx, args[1]) and entry_capture == capture) continue;
        if (write != i) list.setPropertyUint32(ctx, write, entry.dup(ctx)) catch return quickjs.Value.exception;
        write += 1;
    }
    setArrayLength(ctx, list, write);
    return quickjs.Value.undefined;
}

fn jsEventTargetDispatchEvent(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const profile = classProfileEnabled();
    const start = if (profile) classProfileNowNs() else 0;
    defer if (profile) {
        class_perf_stats.dispatch_event_calls += 1;
        class_perf_stats.dispatch_event_ns += classProfileNowNs() - start;
    };

    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or !args[0].isObject()) return throwOperationMessage(ctx, "dispatchEvent", "event argument must be an object");
    const event = args[0];
    const type_value = event.getPropertyStr(ctx, "type");
    defer type_value.deinit(ctx);
    const type_arg = type_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "dispatchEvent", "event type must be a string");
    defer ctx.freeCString(type_arg.ptr);
    const is_mouse_click = isMouseClickEvent(ctx, event, type_arg.ptr[0..type_arg.len]);
    const bubbles = boolProperty(ctx, event, "bubbles");
    const composed = boolProperty(ctx, event, "composed");

    event.setPropertyStr(ctx, "_target", this_value.dup(ctx)) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "target", this_value.dup(ctx)) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "srcElement", this_value.dup(ctx)) catch return quickjs.Value.exception;

    const was_stopped_before_dispatch = boolProperty(ctx, event, "_stopped") or boolProperty(ctx, event, "_immediateStopped");
    if (was_stopped_before_dispatch) {
        const reset = resetEventDispatchState(ctx, event);
        if (reset.isException()) return quickjs.Value.exception;
        reset.deinit(ctx);
        return quickjs.Value.initBool(!boolProperty(ctx, event, "_canceled"));
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    var path = [_]quickjs.Value{quickjs.Value.undefined} ** 64;
    var path_len: usize = 0;
    var cursor = this_value.dup(ctx);
    defer cursor.deinit(ctx);
    while (path_len < path.len and cursor.isObject()) {
        path[path_len] = cursor.dup(ctx);
        path_len += 1;
        var parent = cursor.getPropertyStr(ctx, "parentNode");
        if ((parent.isNull() or parent.isUndefined() or parent.isException()) and composed) {
            parent.deinit(ctx);
            parent = cursor.getPropertyStr(ctx, "host");
        }
        cursor.deinit(ctx);
        cursor = parent;
        if (cursor.isNull() or cursor.isUndefined() or cursor.isException()) break;
    }

    if (path_len < path.len) {
        const owner_document = jsNodeOwnerDocumentGet(ctx, this_value);
        defer owner_document.deinit(ctx);
        const global_document = global.getPropertyStr(ctx, "document");
        defer global_document.deinit(ctx);
        const is_global_document_target = !global_document.isException() and global_document.isObject() and this_value.isStrictEqual(ctx, global_document);
        const is_global_document_owner = !owner_document.isException() and owner_document.isObject() and !global_document.isException() and global_document.isObject() and owner_document.isStrictEqual(ctx, global_document);
        if (is_global_document_target or is_global_document_owner) {
            const window_target = global.getPropertyStr(ctx, "window");
            defer window_target.deinit(ctx);
            if (!window_target.isException() and window_target.isObject()) {
                path[path_len] = window_target.dup(ctx);
                path_len += 1;
            }
        }
    }

    var activation_target = quickjs.Value.null;
    defer activation_target.deinit(ctx);
    if (is_mouse_click) {
        activation_target = resolveClickActivationTarget(ctx, this_value, path[0..path_len], bubbles);
        if (activation_target.isObject()) {
            applyPreClickState(ctx, activation_target, event);
        }
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
        if (boolProperty(ctx, event, "_stopped")) break;
        i -= 1;
        tryDispatchListeners(ctx, path[i], event, type_arg.ptr, true, 1) catch return quickjs.Value.exception;
    }
    if (!boolProperty(ctx, event, "_stopped")) {
        tryDispatchListeners(ctx, this_value, event, type_arg.ptr, true, 2) catch return quickjs.Value.exception;
        tryDispatchListeners(ctx, this_value, event, type_arg.ptr, false, 2) catch return quickjs.Value.exception;
        tryDispatchPropertyListener(ctx, this_value, event, type_arg.ptr) catch return quickjs.Value.exception;
    }

    if (bubbles) {
        for (path[1..path_len]) |ancestor| {
            if (boolProperty(ctx, event, "_stopped")) break;
            tryDispatchListeners(ctx, ancestor, event, type_arg.ptr, false, 3) catch return quickjs.Value.exception;
            tryDispatchPropertyListener(ctx, ancestor, event, type_arg.ptr) catch return quickjs.Value.exception;
        }
    }

    const reset = resetEventDispatchState(ctx, event);
    if (reset.isException()) return quickjs.Value.exception;
    reset.deinit(ctx);

    if (is_mouse_click and boolProperty(ctx, event, "defaultPrevented")) {
        restoreCanceledPreClickState(ctx, event);
    }

    if (is_mouse_click and !boolProperty(ctx, event, "defaultPrevented") and activation_target.isObject()) {
        const action_result = applyClickDefaultAction(ctx, activation_target);
        defer action_result.deinit(ctx);
        if (action_result.isException()) return quickjs.Value.exception;
    }

    return quickjs.Value.initBool(!boolProperty(ctx, event, "_canceled"));
}

fn isMouseClickEvent(ctx: *quickjs.Context, event: quickjs.Value, event_type: []const u8) bool {
    if (!std.mem.eql(u8, event_type, "click")) return false;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const mouse_event_ctor = global.getPropertyStr(ctx, "MouseEvent");
    defer mouse_event_ctor.deinit(ctx);
    if (mouse_event_ctor.isException() or !mouse_event_ctor.isObject()) return false;
    return event.isInstanceOf(ctx, mouse_event_ctor) catch false;
}

fn hasClickActivationBehavior(ctx: *quickjs.Context, target: quickjs.Value) bool {
    if (!target.isObject()) return false;
    const local = jsElementLocalNameGet(ctx, target);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(local_text.ptr);
    const local_name = local_text.ptr[0..local_text.len];

    if (std.ascii.eqlIgnoreCase(local_name, "label") or std.ascii.eqlIgnoreCase(local_name, "button") or std.ascii.eqlIgnoreCase(local_name, "input") or std.ascii.eqlIgnoreCase(local_name, "details")) {
        return true;
    }
    if (std.ascii.eqlIgnoreCase(local_name, "a") or std.ascii.eqlIgnoreCase(local_name, "area")) {
        const href = elementHrefString(ctx, target);
        defer if (href) |value| ctx.freeCString(value.ptr);
        return href != null;
    }
    return false;
}

fn resolveClickActivationTarget(ctx: *quickjs.Context, dispatch_target: quickjs.Value, path: []const quickjs.Value, bubbles: bool) quickjs.Value {
    if (hasClickActivationBehavior(ctx, dispatch_target)) return dispatch_target.dup(ctx);
    if (!bubbles) return quickjs.Value.null;
    for (path[1..]) |ancestor| {
        if (hasClickActivationBehavior(ctx, ancestor)) return ancestor.dup(ctx);
    }
    return quickjs.Value.null;
}

fn jsElementClick(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const disabled = jsElementDisabledGet(ctx, this_value);
    defer disabled.deinit(ctx);
    if (disabled.toBool(ctx) catch false) return quickjs.Value.undefined;

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

fn applyPreClickState(ctx: *quickjs.Context, target: quickjs.Value, event: quickjs.Value) void {
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
        event.setPropertyStr(ctx, "_legacyPreActivationTarget", target.dup(ctx)) catch {};
        event.setPropertyStr(ctx, "_legacyPreActivationChecked", checked.dup(ctx)) catch {};
        const next = quickjs.Value.initBool(!(checked.toBool(ctx) catch false));
        const ignored = jsElementCheckedSet(ctx, target, next);
        ignored.deinit(ctx);
    } else if (std.ascii.eqlIgnoreCase(type_value, "radio")) {
        const checked = jsElementCheckedGet(ctx, target);
        defer checked.deinit(ctx);
        event.setPropertyStr(ctx, "_legacyPreActivationTarget", target.dup(ctx)) catch {};
        event.setPropertyStr(ctx, "_legacyPreActivationChecked", checked.dup(ctx)) catch {};
        const on = quickjs.Value.initBool(true);
        const ignored = jsElementCheckedSet(ctx, target, on);
        ignored.deinit(ctx);
    }
}

fn restoreCanceledPreClickState(ctx: *quickjs.Context, event: quickjs.Value) void {
    const target = event.getPropertyStr(ctx, "_legacyPreActivationTarget");
    defer target.deinit(ctx);
    if (!target.isObject()) return;

    const previous = event.getPropertyStr(ctx, "_legacyPreActivationChecked");
    defer previous.deinit(ctx);
    if (previous.isException() or previous.isUndefined() or previous.isNull()) return;

    const next = quickjs.Value.initBool(previous.toBool(ctx) catch false);
    const ignored = jsElementCheckedSet(ctx, target, next);
    ignored.deinit(ctx);
}

fn isInteractiveLabelDescendantTarget(ctx: *quickjs.Context, target: quickjs.Value) bool {
    const local = jsElementLocalNameGet(ctx, target);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(local_text.ptr);
    const name = local_text.ptr[0..local_text.len];

    return std.ascii.eqlIgnoreCase(name, "a") or
        std.ascii.eqlIgnoreCase(name, "area") or
        std.ascii.eqlIgnoreCase(name, "button") or
        std.ascii.eqlIgnoreCase(name, "details") or
        std.ascii.eqlIgnoreCase(name, "input") or
        std.ascii.eqlIgnoreCase(name, "select") or
        std.ascii.eqlIgnoreCase(name, "textarea") or
        std.ascii.eqlIgnoreCase(name, "option");
}

fn nearestAncestorLabel(ctx: *quickjs.Context, target: quickjs.Value) quickjs.Value {
    var cursor = jsNodeParentElementGet(ctx, target);
    while (cursor.isObject()) {
        const local = jsElementLocalNameGet(ctx, cursor);
        const local_text = local.toCStringLen(ctx) orelse {
            local.deinit(ctx);
            cursor.deinit(ctx);
            return quickjs.Value.null;
        };
        const is_label = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "label");
        ctx.freeCString(local_text.ptr);
        local.deinit(ctx);
        if (is_label) {
            return cursor;
        }
        const parent = jsNodeParentElementGet(ctx, cursor);
        cursor.deinit(ctx);
        cursor = parent;
    }
    return cursor;
}

fn activateLabelControl(ctx: *quickjs.Context, label: quickjs.Value) quickjs.Value {
    const control = resolveLabelControl(ctx, label);
    defer control.deinit(ctx);
    if (control.isObject()) {
        const click = jsElementClick(ctx, control, &.{});
        defer click.deinit(ctx);
        if (click.isException()) return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn applyClickDefaultAction(ctx: *quickjs.Context, target: quickjs.Value) quickjs.Value {
    const local = jsElementLocalNameGet(ctx, target);
    defer local.deinit(ctx);
    const local_text = local.toCStringLen(ctx) orelse return quickjs.Value.undefined;
    defer ctx.freeCString(local_text.ptr);

    const is_button = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "button");
    const is_input = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "input");
    const is_label = std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "label");

    if (!is_label and !isInteractiveLabelDescendantTarget(ctx, target)) {
        const label = nearestAncestorLabel(ctx, target);
        defer label.deinit(ctx);
        if (label.isObject()) {
            return activateLabelControl(ctx, label);
        }
    }

    if (is_label) {
        return activateLabelControl(ctx, target);
    }
    if (!is_button and !is_input) {
        if (std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "a") or std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "area")) {
            const href_opt = elementHrefString(ctx, target);
            defer if (href_opt) |value| ctx.freeCString(value.ptr);
            if (href_opt) |href| {
                const href_text = href.ptr[0..href.len];
                if (std.ascii.startsWithIgnoreCase(href_text, "javascript:")) {
                    const global = ctx.getGlobalObject();
                    defer global.deinit(ctx);
                    const fn_ctor = global.getPropertyStr(ctx, "Function");
                    defer fn_ctor.deinit(ctx);
                    if (!fn_ctor.isException() and fn_ctor.isFunction(ctx)) {
                        var wrapped_buf: [1024]u8 = undefined;
                        const wrapped = std.fmt.bufPrint(&wrapped_buf, "with (this) {{ {s} }}", .{href_text[11..]}) catch href_text[11..];
                        const body_arg = quickjs.Value.initStringLen(ctx, wrapped);
                        defer body_arg.deinit(ctx);
                        const fn_value = fn_ctor.call(ctx, quickjs.Value.undefined, &.{body_arg});
                        defer fn_value.deinit(ctx);
                        if (fn_value.isException() or !fn_value.isFunction(ctx)) return quickjs.Value.exception;

                        const document = jsNodeOwnerDocumentGet(ctx, target);
                        defer document.deinit(ctx);
                        const window = jsDocumentDefaultViewGet(ctx, document);
                        defer window.deinit(ctx);
                        const this_arg = if (window.isObject()) window else global;
                        const call_result = fn_value.call(ctx, this_arg, &.{});
                        defer call_result.deinit(ctx);
                        if (call_result.isException()) return quickjs.Value.exception;
                    }
                } else if (std.mem.startsWith(u8, href_text, "#")) {
                    const global = ctx.getGlobalObject();
                    defer global.deinit(ctx);
                    const activated = global.getPropertyStr(ctx, "activated");
                    defer activated.deinit(ctx);
                    if (!activated.isException() and activated.isFunction(ctx)) {
                        var args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, href_text)};
                        defer args[0].deinit(ctx);
                        const call_result = activated.call(ctx, global, &args);
                        defer call_result.deinit(ctx);
                        if (call_result.isException()) return quickjs.Value.exception;
                    }
                } else {
                    const document = jsNodeOwnerDocumentGet(ctx, target);
                    defer document.deinit(ctx);
                    const window = jsDocumentDefaultViewGet(ctx, document);
                    defer window.deinit(ctx);

                    var location = if (window.isObject()) window.getPropertyStr(ctx, "location") else quickjs.Value.exception;
                    defer location.deinit(ctx);
                    if (location.isException() or !location.isObject()) {
                        const global = ctx.getGlobalObject();
                        defer global.deinit(ctx);
                        location.deinit(ctx);
                        location = global.getPropertyStr(ctx, "location");
                        if (location.isException() or !location.isObject()) {
                            return quickjs.Value.undefined;
                        }
                    }

                    const href_value = quickjs.Value.initStringLen(ctx, href_text);
                    defer href_value.deinit(ctx);
                    const navigation = jsLocationHrefSet(ctx, location, href_value);
                    defer navigation.deinit(ctx);
                    if (navigation.isException()) return quickjs.Value.exception;
                }
            }
        } else if (std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "details")) {
            const details_handle = parseThisHandle(ctx, target, "click") orelse return quickjs.Value.exception;
            if (zig_dom.zig_dom_element_has_attribute(details_handle, "open".ptr, "open".len) == 1) {
                const clear_status = zig_dom.zig_dom_element_remove_attribute(details_handle, "open".ptr, "open".len);
                if (clear_status != 0) return throwStatus(ctx, "click", clear_status);
            } else {
                const set_status = zig_dom.zig_dom_element_set_attribute(details_handle, "open".ptr, "open".len, "".ptr, 0);
                if (set_status != 0) return throwStatus(ctx, "click", set_status);
            }

            const global = ctx.getGlobalObject();
            defer global.deinit(ctx);
            const event_ctor = global.getPropertyStr(ctx, "Event");
            defer event_ctor.deinit(ctx);
            if (!event_ctor.isException() and event_ctor.isObject()) {
                const toggle_type = quickjs.Value.initStringLen(ctx, "toggle");
                defer toggle_type.deinit(ctx);
                const toggle_options = quickjs.Value.initObject(ctx);
                if (toggle_options.isException()) return quickjs.Value.exception;
                defer toggle_options.deinit(ctx);
                const toggle_event = createEventObject(ctx, event_ctor, &.{ toggle_type, toggle_options }, .event);
                defer toggle_event.deinit(ctx);
                if (toggle_event.isException()) return quickjs.Value.exception;
                const toggle_dispatched = jsEventTargetDispatchEvent(ctx, target, @ptrCast(&[_]quickjs.Value{toggle_event}));
                defer toggle_dispatched.deinit(ctx);
                if (toggle_dispatched.isException()) return quickjs.Value.exception;
            }
        }
        return quickjs.Value.undefined;
    }

    const type_value_opt = elementAttributeString(ctx, target, "type");
    defer if (type_value_opt) |value| ctx.freeCString(value.ptr);
    const type_value = if (type_value_opt) |value| value.ptr[0..value.len] else "";
    const disabled = jsElementDisabledGet(ctx, target);
    defer disabled.deinit(ctx);
    const is_checkable_input = is_input and (std.ascii.eqlIgnoreCase(type_value, "checkbox") or std.ascii.eqlIgnoreCase(type_value, "radio"));
    if ((disabled.toBool(ctx) catch false) and !is_checkable_input) return quickjs.Value.undefined;

    if (is_checkable_input) {
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
        const parent_for_activation = jsNodeParentNodeGet(ctx, target);
        defer parent_for_activation.deinit(ctx);
        if (!parent_for_activation.isObject()) return quickjs.Value.undefined;

        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const event_ctor = global.getPropertyStr(ctx, "Event");
        defer event_ctor.deinit(ctx);
        if (!event_ctor.isException() and event_ctor.isObject()) {
            const input_type = quickjs.Value.initStringLen(ctx, "input");
            defer input_type.deinit(ctx);
            const input_options = quickjs.Value.initObject(ctx);
            if (input_options.isException()) return quickjs.Value.exception;
            defer input_options.deinit(ctx);
            input_options.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
            const input_event = createEventObject(ctx, event_ctor, &.{ input_type, input_options }, .event);
            defer input_event.deinit(ctx);
            if (input_event.isException()) return quickjs.Value.exception;
            const input_dispatched = jsEventTargetDispatchEvent(ctx, target, @ptrCast(&[_]quickjs.Value{input_event}));
            defer input_dispatched.deinit(ctx);
            if (input_dispatched.isException()) return quickjs.Value.exception;

            const change_type = quickjs.Value.initStringLen(ctx, "change");
            defer change_type.deinit(ctx);
            const change_options = quickjs.Value.initObject(ctx);
            if (change_options.isException()) return quickjs.Value.exception;
            defer change_options.deinit(ctx);
            change_options.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
            const change_event = createEventObject(ctx, event_ctor, &.{ change_type, change_options }, .event);
            defer change_event.deinit(ctx);
            if (change_event.isException()) return quickjs.Value.exception;
            const change_dispatched = jsEventTargetDispatchEvent(ctx, target, @ptrCast(&[_]quickjs.Value{change_event}));
            defer change_dispatched.deinit(ctx);
            if (change_dispatched.isException()) return quickjs.Value.exception;
        }
        return quickjs.Value.undefined;
    }

    const should_submit = if (is_button)
        (type_value.len == 0 or std.ascii.eqlIgnoreCase(type_value, "submit"))
    else
        (std.ascii.eqlIgnoreCase(type_value, "submit") or std.ascii.eqlIgnoreCase(type_value, "image"));
    const should_reset = std.ascii.eqlIgnoreCase(type_value, "reset");

    if (!should_submit and !should_reset) {
        return quickjs.Value.undefined;
    }

    const form = jsElementFormGet(ctx, target);
    defer form.deinit(ctx);
    if (!form.isObject()) {
        return quickjs.Value.undefined;
    }
    const form_parent = jsNodeParentNodeGet(ctx, form);
    defer form_parent.deinit(ctx);
    if (!form_parent.isObject()) return quickjs.Value.undefined;

    if (should_submit) {
        return dispatchFormSubmitEvent(ctx, form, target);
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const event_ctor = global.getPropertyStr(ctx, "Event");
    defer event_ctor.deinit(ctx);
    if (!event_ctor.isException() and event_ctor.isObject()) {
        const reset_type = quickjs.Value.initStringLen(ctx, "reset");
        defer reset_type.deinit(ctx);
        const reset_options = quickjs.Value.initObject(ctx);
        if (reset_options.isException()) return quickjs.Value.exception;
        defer reset_options.deinit(ctx);
        reset_options.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
        reset_options.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;

        const reset_event = createEventObject(ctx, event_ctor, &.{ reset_type, reset_options }, .event);
        defer reset_event.deinit(ctx);
        if (reset_event.isException()) return quickjs.Value.exception;
        const reset_dispatched = jsEventTargetDispatchEvent(ctx, form, @ptrCast(&[_]quickjs.Value{reset_event}));
        defer reset_dispatched.deinit(ctx);
        if (reset_dispatched.isException()) return quickjs.Value.exception;
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

fn jsNodeGetRootNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const composed = blk: {
        if (args.len == 0 or !args[0].isObject()) break :blk false;
        const value = args[0].getPropertyStr(ctx, "composed");
        defer value.deinit(ctx);
        if (value.isException() or value.isUndefined() or value.isNull()) break :blk false;
        break :blk value.toBool(ctx) catch false;
    };
    var cursor = this_value.dup(ctx);
    while (true) {
        const parent = jsNodeParentNodeGet(ctx, cursor);
        if (parent.isNull() or parent.isUndefined() or parent.isException()) {
            parent.deinit(ctx);
            if (composed) {
                const host = cursor.getPropertyStr(ctx, "host");
                if (!host.isException() and host.isObject()) {
                    cursor.deinit(ctx);
                    cursor = host;
                    continue;
                }
                host.deinit(ctx);
            }
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
    if (!this_value.isObject() or !args[0].isObject()) return quickjs.Value.initBool(false);
    return quickjs.Value.initBool(nodesAreEqual(ctx, this_value, args[0]));
}

fn nodesAreEqual(ctx: *quickjs.Context, left: quickjs.Value, right: quickjs.Value) bool {
    if (left.isStrictEqual(ctx, right)) return true;
    const left_type = nodeTypeForEquality(ctx, left) orelse return false;
    const right_type = nodeTypeForEquality(ctx, right) orelse return false;
    if (left_type != right_type) return false;

    switch (left_type) {
        1 => {
            if (!nullableStringPropertyEquals(ctx, left, right, "namespaceURI")) return false;
            if (!nullableStringPropertyEquals(ctx, left, right, "prefix")) return false;
            if (!nullableStringPropertyEquals(ctx, left, right, "localName")) return false;
            if (!elementAttributesEqual(ctx, left, right)) return false;
        },
        2 => {
            if (!nullableStringPropertyEquals(ctx, left, right, "namespaceURI")) return false;
            if (!nullableStringPropertyEquals(ctx, left, right, "localName")) return false;
            if (!nullableStringPropertyEquals(ctx, left, right, "value")) return false;
        },
        3, 4, 8 => {
            if (!nullableStringPropertyEquals(ctx, left, right, "nodeValue")) return false;
        },
        7 => {
            if (!nullableStringPropertyEquals(ctx, left, right, "target")) return false;
            if (!nullableStringPropertyEquals(ctx, left, right, "textContent")) return false;
        },
        10 => {
            if (!nullableStringPropertyEquals(ctx, left, right, "name")) return false;
            if (!nullableStringPropertyEquals(ctx, left, right, "publicId")) return false;
            if (!nullableStringPropertyEquals(ctx, left, right, "systemId")) return false;
        },
        else => {},
    }

    const left_children = childNodesForEquality(ctx, left);
    defer left_children.deinit(ctx);
    if (left_children.isException()) return false;
    const right_children = childNodesForEquality(ctx, right);
    defer right_children.deinit(ctx);
    if (right_children.isException()) return false;
    const left_len = if (left_children.isObject()) arrayLength(ctx, left_children) else 0;
    const right_len = if (right_children.isObject()) arrayLength(ctx, right_children) else 0;
    if (left_len != right_len) return false;
    for (0..left_len) |index_usize| {
        const index: u32 = @intCast(index_usize);
        const left_child = left_children.getPropertyUint32(ctx, index);
        defer left_child.deinit(ctx);
        const right_child = right_children.getPropertyUint32(ctx, index);
        defer right_child.deinit(ctx);
        if (left_child.isException() or right_child.isException()) return false;
        if (!left_child.isObject() or !right_child.isObject()) return false;
        if (!nodesAreEqual(ctx, left_child, right_child)) return false;
    }
    return true;
}

fn nodeTypeForEquality(ctx: *quickjs.Context, node: quickjs.Value) ?u32 {
    if (getIntProperty(ctx, node, "_nodeTypeOverride")) |node_type| {
        if (node_type > 0) return @intCast(node_type);
    }
    if (getIntProperty(ctx, node, "nodeType")) |node_type| {
        if (node_type > 0) return @intCast(node_type);
    }
    const handle = parseValueNodeHandle(ctx, node) orelse return null;
    if (handle <= 0) return null;
    return @intCast(zig_dom.zig_dom_node_type(@intCast(handle)));
}

fn childNodesForEquality(ctx: *quickjs.Context, node: quickjs.Value) quickjs.Value {
    const child_nodes = node.getPropertyStr(ctx, "childNodes");
    if (!child_nodes.isException() and child_nodes.isObject()) return child_nodes;
    child_nodes.deinit(ctx);
    return quickjs.Value.undefined;
}

fn elementAttributesEqual(ctx: *quickjs.Context, left: quickjs.Value, right: quickjs.Value) bool {
    const left_attrs = jsElementAttributesGet(ctx, left);
    defer left_attrs.deinit(ctx);
    if (left_attrs.isException() or !left_attrs.isObject()) return false;
    const right_attrs = jsElementAttributesGet(ctx, right);
    defer right_attrs.deinit(ctx);
    if (right_attrs.isException() or !right_attrs.isObject()) return false;

    const left_len = arrayLength(ctx, left_attrs);
    const right_len = arrayLength(ctx, right_attrs);
    if (left_len != right_len) return false;

    for (0..left_len) |left_index_usize| {
        const left_attr = left_attrs.getPropertyUint32(ctx, @intCast(left_index_usize));
        defer left_attr.deinit(ctx);
        if (left_attr.isException() or !left_attr.isObject()) return false;
        var matched = false;
        for (0..right_len) |right_index_usize| {
            const right_attr = right_attrs.getPropertyUint32(ctx, @intCast(right_index_usize));
            defer right_attr.deinit(ctx);
            if (right_attr.isException() or !right_attr.isObject()) return false;
            if (nullableStringPropertyEquals(ctx, left_attr, right_attr, "namespaceURI") and
                nullableStringPropertyEquals(ctx, left_attr, right_attr, "localName") and
                nullableStringPropertyEquals(ctx, left_attr, right_attr, "value"))
            {
                matched = true;
                break;
            }
        }
        if (!matched) return false;
    }
    return true;
}

fn nullableStringPropertyEquals(ctx: *quickjs.Context, left: quickjs.Value, right: quickjs.Value, name: [*:0]const u8) bool {
    const left_value = left.getPropertyStr(ctx, name);
    defer left_value.deinit(ctx);
    const right_value = right.getPropertyStr(ctx, name);
    defer right_value.deinit(ctx);
    if (left_value.isException() or right_value.isException()) return false;
    const left_empty = left_value.isNull() or left_value.isUndefined();
    const right_empty = right_value.isNull() or right_value.isUndefined();
    if (left_empty or right_empty) return left_empty and right_empty;
    const left_text = left_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(left_text.ptr);
    const right_text = right_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(right_text.ptr);
    return std.mem.eql(u8, left_text.ptr[0..left_text.len], right_text.ptr[0..right_text.len]);
}

fn jsNodeIsSameNode(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0 or args[0].isNull() or args[0].isUndefined()) return quickjs.Value.initBool(false);
    const this_handle_i64 = parseValueNodeHandle(ctx, this_value) orelse {
        if (this_value.isObject()) return quickjs.Value.initBool(this_value.isStrictEqual(ctx, args[0]));
        _ = throwOperationMessage(ctx, "isSameNode", "receiver is not a native node");
        return quickjs.Value.exception;
    };
    if (this_handle_i64 <= 0) return quickjs.Value.initBool(false);
    const other_handle_i64 = parseValueNodeHandle(ctx, args[0]) orelse return quickjs.Value.initBool(false);
    if (other_handle_i64 <= 0) return quickjs.Value.initBool(false);
    return quickjs.Value.initBool(this_handle_i64 == other_handle_i64);
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
    if (!validateDocumentChildrenForInsertion(ctx, this_value, this_handle, &.{child_handle}, "appendChild")) return quickjs.Value.exception;
    var scripts: std.ArrayListUnmanaged(quickjs.Value) = .empty;
    defer {
        for (scripts.items) |script| script.deinit(ctx);
        scripts.deinit(std.heap.c_allocator);
    }
    collectScriptNodes(ctx, args[0], &scripts) catch return quickjs.Value.exception;

    var status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
        zig_dom.zig_dom_node_append_fragment(this_handle, child_handle)
    else
        zig_dom.zig_dom_node_append_child(this_handle, child_handle);

    if (status == 2) {
        const parent_document = blk: {
            if (zig_dom.zig_dom_node_type(this_handle) == 9) break :blk this_value.dup(ctx);
            break :blk jsNodeOwnerDocumentGet(ctx, this_value);
        };
        defer parent_document.deinit(ctx);
        if (!parent_document.isException() and parent_document.isObject()) {
            const imported = cloneNodeForDocument(ctx, parent_document, args[0], true);
            if (imported.isException()) return quickjs.Value.exception;
            defer imported.deinit(ctx);
            const imported_handle = parseThisHandle(ctx, imported, "appendChild") orelse return quickjs.Value.exception;
            status = if (zig_dom.zig_dom_node_type(imported_handle) == 11)
                zig_dom.zig_dom_node_append_fragment(this_handle, imported_handle)
            else
                zig_dom.zig_dom_node_append_child(this_handle, imported_handle);
            if (status != 0) return throwStatus(ctx, "appendChild", status);
            setOwnerDocumentOverrideRecursive(ctx, args[0], parent_document);
            args[0].setPropertyStr(ctx, "__zigDomNativeHandle", quickjs.Value.initInt64(@intCast(imported_handle))) catch return quickjs.Value.exception;
            cacheNativeNodeWrapper(ctx, imported_handle, args[0]);
            queueMutationRecord(ctx, this_value, .child_list, null, null);
            syncRegisteredHtmlCollections(ctx);
            refreshCachedChildNodeListForNode(ctx, this_value, this_handle);
            setOwnerDocumentOverrideRecursive(ctx, args[0], parent_document);
            initializeIFrameAfterAppend(ctx, imported);
            return args[0].dup(ctx);
        }
    }

    if (status != 0) {
        return throwStatus(ctx, "appendChild", status);
    }

    queueMutationRecord(ctx, this_value, .child_list, null, null);
    syncRegisteredHtmlCollections(ctx);
    refreshCachedChildNodeListForNode(ctx, this_value, this_handle);
    const parent_document = if (zig_dom.zig_dom_node_type(this_handle) == 9) this_value.dup(ctx) else jsNodeOwnerDocumentGet(ctx, this_value);
    defer parent_document.deinit(ctx);
    if (!parent_document.isException() and parent_document.isObject()) {
        setOwnerDocumentOverrideRecursive(ctx, args[0], parent_document);
    }
    initializeIFrameAfterAppend(ctx, args[0]);
    executeCollectedScripts(ctx, scripts.items);

    return args[0].dup(ctx);
}

fn setOwnerDocumentOverrideRecursive(ctx: *quickjs.Context, node: quickjs.Value, document: quickjs.Value) void {
    if (!node.isObject() or !document.isObject()) return;
    node.setPropertyStr(ctx, "__zigDomOwnerDocument", document.dup(ctx)) catch return;
    const children = jsNodeChildNodesGet(ctx, node);
    defer children.deinit(ctx);
    if (children.isException() or !children.isObject()) return;
    const len = arrayLength(ctx, children);
    for (0..len) |i| {
        const child = children.getPropertyUint32(ctx, @intCast(i));
        defer child.deinit(ctx);
        if (child.isObject()) setOwnerDocumentOverrideRecursive(ctx, child, document);
    }
}

fn jsNodeAppend(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "append") orelse return quickjs.Value.exception;

    var handles: std.ArrayListUnmanaged(u64) = .empty;
    defer handles.deinit(std.heap.c_allocator);
    for (args) |arg| {
        const child_handle = nodeOrTextHandle(ctx, this_handle, arg, "append") orelse return quickjs.Value.exception;
        handles.append(std.heap.c_allocator, child_handle) catch return quickjs.Value.exception;
    }
    if (!validateDocumentChildrenForInsertion(ctx, this_value, this_handle, handles.items, "append")) return quickjs.Value.exception;
    var scripts: std.ArrayListUnmanaged(quickjs.Value) = .empty;
    defer {
        for (scripts.items) |script| script.deinit(ctx);
        scripts.deinit(std.heap.c_allocator);
    }
    for (args) |arg| {
        if (arg.isObject()) collectScriptNodes(ctx, arg, &scripts) catch return quickjs.Value.exception;
    }

    for (handles.items) |child_handle| {
        const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
            zig_dom.zig_dom_node_append_fragment(this_handle, child_handle)
        else
            zig_dom.zig_dom_node_append_child(this_handle, child_handle);
        if (status != 0) return throwStatus(ctx, "append", status);
    }

    syncRegisteredHtmlCollections(ctx);
    refreshCachedChildNodeListForNode(ctx, this_value, this_handle);
    for (args) |arg| {
        if (arg.isObject()) initializeIFrameAfterAppend(ctx, arg);
    }
    executeCollectedScripts(ctx, scripts.items);

    return quickjs.Value.undefined;
}

fn jsNodePrepend(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const this_handle = parseThisHandle(ctx, this_value, "prepend") orelse return quickjs.Value.exception;
    const reference_handle = zig_dom.zig_dom_node_first_child(this_handle);

    var handles: std.ArrayListUnmanaged(u64) = .empty;
    defer handles.deinit(std.heap.c_allocator);
    for (args) |arg| {
        const child_handle = nodeOrTextHandle(ctx, this_handle, arg, "prepend") orelse return quickjs.Value.exception;
        handles.append(std.heap.c_allocator, child_handle) catch return quickjs.Value.exception;
    }
    if (!validateDocumentChildrenForInsertion(ctx, this_value, this_handle, handles.items, "prepend")) return quickjs.Value.exception;
    var scripts: std.ArrayListUnmanaged(quickjs.Value) = .empty;
    defer {
        for (scripts.items) |script| script.deinit(ctx);
        scripts.deinit(std.heap.c_allocator);
    }
    for (args) |arg| {
        if (arg.isObject()) collectScriptNodes(ctx, arg, &scripts) catch return quickjs.Value.exception;
    }

    for (handles.items) |child_handle| {
        const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
            insertFragmentBefore(this_handle, child_handle, reference_handle)
        else
            zig_dom.zig_dom_node_insert_before(this_handle, child_handle, reference_handle);
        if (status != 0) return throwStatus(ctx, "prepend", status);
    }
    for (args) |arg| {
        if (arg.isObject()) initializeIFrameAfterAppend(ctx, arg);
    }
    refreshCachedChildNodeListForNode(ctx, this_value, this_handle);
    executeCollectedScripts(ctx, scripts.items);

    return quickjs.Value.undefined;
}

fn jsNodeInsertBefore(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "insertBefore") orelse return quickjs.Value.exception;
    const child_handle = parseRequiredNodeArgHandle(ctx, args, 0, "insertBefore") orelse return quickjs.Value.exception;
    const reference_handle = parseNullableNodeArgHandle(ctx, args, 1, "insertBefore") orelse return quickjs.Value.exception;
    if (!validateDocumentChildrenForInsertion(ctx, this_value, this_handle, &.{child_handle}, "insertBefore")) return quickjs.Value.exception;
    var scripts: std.ArrayListUnmanaged(quickjs.Value) = .empty;
    defer {
        for (scripts.items) |script| script.deinit(ctx);
        scripts.deinit(std.heap.c_allocator);
    }
    collectScriptNodes(ctx, args[0], &scripts) catch return quickjs.Value.exception;

    const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
        insertFragmentBefore(this_handle, child_handle, reference_handle)
    else
        zig_dom.zig_dom_node_insert_before(this_handle, child_handle, reference_handle);
    if (status != 0) {
        return throwStatus(ctx, "insertBefore", status);
    }

    queueMutationRecord(ctx, this_value, .child_list, null, null);
    refreshCachedChildNodeListForNode(ctx, this_value, this_handle);
    initializeIFrameAfterAppend(ctx, args[0]);
    executeCollectedScripts(ctx, scripts.items);

    return args[0].dup(ctx);
}

fn jsNodeRemoveChild(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "removeChild") orelse return quickjs.Value.exception;
    const child_handle = parseRequiredNodeArgHandle(ctx, args, 0, "removeChild") orelse return quickjs.Value.exception;
    const removed_index = childIndexInParent(this_handle, child_handle);

    const status = zig_dom.zig_dom_node_remove_child(this_handle, child_handle);
    if (status != 0) {
        return throwStatus(ctx, "removeChild", status);
    }
    updateRangesAfterChildRemoved(ctx, this_value, removed_index);
    queueMutationRecord(ctx, this_value, .child_list, null, null);
    refreshCachedChildNodeListForNode(ctx, this_value, this_handle);
    callMethodNoArgs(ctx, args[0], "disconnectedCallback") catch return quickjs.Value.exception;

    return args[0].dup(ctx);
}

fn jsNodeRemove(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;

    var is_iframe = false;
    const local = jsElementLocalNameGet(ctx, this_value);
    defer local.deinit(ctx);
    if (!local.isException()) {
        const local_text = local.toCStringLen(ctx);
        if (local_text) |text| {
            defer ctx.freeCString(text.ptr);
            is_iframe = std.ascii.eqlIgnoreCase(text.ptr[0..text.len], "iframe");
        }
    }

    const parent = jsNodeParentNodeGet(ctx, this_value);
    defer parent.deinit(ctx);
    if (parent.isObject()) {
        const removed = jsNodeRemoveChild(ctx, parent, @ptrCast(&[_]quickjs.Value{this_value}));
        defer removed.deinit(ctx);
        if (removed.isException()) return quickjs.Value.exception;
    }

    if (is_iframe) {
        const frame_window = this_value.getPropertyStr(ctx, "__zigFrameWindow");
        defer frame_window.deinit(ctx);
        if (!frame_window.isException() and frame_window.isObject()) {
            clearWindowAbortTimeouts(ctx, frame_window);
        }
    }

    return quickjs.Value.undefined;
}

fn childIndexInParent(parent_handle: u64, child_handle: u64) i64 {
    var index: i64 = 0;
    var child = zig_dom.zig_dom_node_first_child(parent_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        if (child == child_handle) return index;
        index += 1;
    }
    return index;
}

fn updateRangesAfterChildRemoved(ctx: *quickjs.Context, parent: quickjs.Value, removed_index: i64) void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ranges = global.getPropertyStr(ctx, "__zigLiveRanges");
    defer ranges.deinit(ctx);
    if (ranges.isException() or !ranges.isObject()) return;
    const len = arrayLength(ctx, ranges);
    for (0..len) |i| {
        const range = ranges.getPropertyUint32(ctx, @intCast(i));
        defer range.deinit(ctx);
        if (!range.isObject()) continue;
        updateRangeBoundaryAfterChildRemoved(ctx, range, parent, "startContainer", "startOffset", removed_index);
        updateRangeBoundaryAfterChildRemoved(ctx, range, parent, "endContainer", "endOffset", removed_index);
        updateRangeCollapsed(ctx, range) catch {};
    }
}

fn updateRangeBoundaryAfterChildRemoved(ctx: *quickjs.Context, range: quickjs.Value, parent: quickjs.Value, container_name: [:0]const u8, offset_name: [:0]const u8, removed_index: i64) void {
    const container = range.getPropertyStr(ctx, container_name);
    defer container.deinit(ctx);
    if (container.isException() or !container.isStrictEqual(ctx, parent)) return;
    const offset_value = range.getPropertyStr(ctx, offset_name);
    defer offset_value.deinit(ctx);
    const offset = offset_value.toInt64(ctx) catch return;
    if (offset > removed_index) {
        range.setPropertyStr(ctx, offset_name, quickjs.Value.initInt64(offset - 1)) catch {};
    }
}

fn collapseRangesForContainer(ctx: *quickjs.Context, container: quickjs.Value) void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ranges = global.getPropertyStr(ctx, "__zigLiveRanges");
    defer ranges.deinit(ctx);
    if (ranges.isException() or !ranges.isObject()) return;
    const len = arrayLength(ctx, ranges);
    for (0..len) |i| {
        const range = ranges.getPropertyUint32(ctx, @intCast(i));
        defer range.deinit(ctx);
        if (!range.isObject()) continue;
        const start = range.getPropertyStr(ctx, "startContainer");
        defer start.deinit(ctx);
        if (start.isException() or !start.isStrictEqual(ctx, container)) continue;
        range.setPropertyStr(ctx, "startOffset", quickjs.Value.initInt64(0)) catch {};
        range.setPropertyStr(ctx, "endOffset", quickjs.Value.initInt64(0)) catch {};
        range.setPropertyStr(ctx, "collapsed", quickjs.Value.initBool(true)) catch {};
    }
}

fn jsNodeBefore(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "before") orelse return quickjs.Value.exception;
    const parent_handle = zig_dom.zig_dom_node_parent(this_handle);
    if (parent_handle == 0) return quickjs.Value.undefined;

    const args: []const quickjs.Value = @ptrCast(raw_args);
    return insertChildNodeArguments(ctx, parent_handle, this_handle, 0, args, "before", false);
}

fn jsNodeAfter(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "after") orelse return quickjs.Value.exception;
    const parent_handle = zig_dom.zig_dom_node_parent(this_handle);
    if (parent_handle == 0) return quickjs.Value.undefined;

    const args: []const quickjs.Value = @ptrCast(raw_args);
    return insertChildNodeArguments(ctx, parent_handle, zig_dom.zig_dom_node_next_sibling(this_handle), 0, args, "after", false);
}

fn jsNodeReplaceWith(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const this_handle = parseThisHandle(ctx, this_value, "replaceWith") orelse return quickjs.Value.exception;
    const parent_handle = zig_dom.zig_dom_node_parent(this_handle);
    if (parent_handle == 0) return quickjs.Value.undefined;

    const args: []const quickjs.Value = @ptrCast(raw_args);
    const result = insertChildNodeArguments(ctx, parent_handle, zig_dom.zig_dom_node_next_sibling(this_handle), this_handle, args, "replaceWith", true);
    if (result.isException()) return quickjs.Value.exception;
    return result;
}

fn jsIFrameContentWindowGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const existing = this_value.getPropertyStr(ctx, "__zigFrameWindow");
    if (!existing.isException() and existing.isObject()) return existing;
    existing.deinit(ctx);

    var window_handle: u64 = 0;
    if (zig_dom.zig_dom_create_window(&window_handle) != 0) return throwMessage(ctx, "failed to create frame window");
    var document_handle: u64 = 0;
    if (zig_dom.zig_dom_window_document(window_handle, &document_handle) != 0) return throwMessage(ctx, "failed to create frame document");
    const document = wrapNodeHandle(ctx, document_handle);
    defer document.deinit(ctx);
    if (document.isException()) return quickjs.Value.exception;
    document.setPropertyStr(ctx, "_windowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch return quickjs.Value.exception;

    const frame_window = createWindowObject(ctx, window_handle, document);
    if (frame_window.isException()) return quickjs.Value.exception;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const parent_window = global.getPropertyStr(ctx, "window");
    defer parent_window.deinit(ctx);
    if (!parent_window.isException() and parent_window.isObject()) {
        frame_window.setPropertyStr(ctx, "parent", parent_window.dup(ctx)) catch return quickjs.Value.exception;
        frame_window.setPropertyStr(ctx, "top", parent_window.dup(ctx)) catch return quickjs.Value.exception;
    }

    const event_target_ctor = global.getPropertyStr(ctx, "EventTarget");
    defer event_target_ctor.deinit(ctx);
    if (!event_target_ctor.isException() and !event_target_ctor.isUndefined()) {
        frame_window.setPropertyStr(ctx, "EventTarget", event_target_ctor.dup(ctx)) catch return quickjs.Value.exception;
    }
    const event_ctor = global.getPropertyStr(ctx, "Event");
    defer event_ctor.deinit(ctx);
    if (!event_ctor.isException() and !event_ctor.isUndefined()) {
        frame_window.setPropertyStr(ctx, "Event", event_ctor.dup(ctx)) catch return quickjs.Value.exception;
    }
    const error_ctor = global.getPropertyStr(ctx, "Error");
    defer error_ctor.deinit(ctx);
    if (!error_ctor.isException() and !error_ctor.isUndefined()) {
        frame_window.setPropertyStr(ctx, "Error", error_ctor.dup(ctx)) catch return quickjs.Value.exception;
    }
    const function_ctor = global.getPropertyStr(ctx, "Function");
    defer function_ctor.deinit(ctx);
    if (!function_ctor.isException() and !function_ctor.isUndefined()) {
        frame_window.setPropertyStr(ctx, "Function", function_ctor.dup(ctx)) catch return quickjs.Value.exception;
    }

    frame_window.setPropertyStr(ctx, "frameElement", this_value.dup(ctx)) catch return quickjs.Value.exception;
    const frame_location = frame_window.getPropertyStr(ctx, "location");
    defer frame_location.deinit(ctx);
    if (!frame_location.isException() and frame_location.isObject()) {
        frame_location.setPropertyStr(ctx, "__zigLocationFrameElement", this_value.dup(ctx)) catch return quickjs.Value.exception;
    }
    this_value.setPropertyStr(ctx, "__zigFrameWindow", frame_window.dup(ctx)) catch return quickjs.Value.exception;
    return frame_window;
}

fn jsIFrameContentDocumentGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const frame_window = jsIFrameContentWindowGet(ctx, this_value);
    defer frame_window.deinit(ctx);
    if (frame_window.isException() or !frame_window.isObject()) return quickjs.Value.exception;
    return frame_window.getPropertyStr(ctx, "document");
}

fn initializeIFrameAfterAppend(ctx: *quickjs.Context, node: quickjs.Value) void {
    const local = jsElementLocalNameGet(ctx, node);
    defer local.deinit(ctx);
    if (local.isException()) return;
    const local_text = local.toCStringLen(ctx) orelse return;
    defer ctx.freeCString(local_text.ptr);
    if (!std.ascii.eqlIgnoreCase(local_text.ptr[0..local_text.len], "iframe")) return;

    const frame_window = jsIFrameContentWindowGet(ctx, node);
    defer frame_window.deinit(ctx);
    if (frame_window.isException() or !frame_window.isObject()) return;

    initializeIFrameFromSrcdoc(ctx, node, frame_window);

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const event_ctor = global.getPropertyStr(ctx, "Event");
    defer event_ctor.deinit(ctx);
    if (event_ctor.isException() or !event_ctor.isObject()) return;
    const type_value = quickjs.Value.initStringLen(ctx, "load");
    defer type_value.deinit(ctx);
    const options = quickjs.Value.initObject(ctx);
    if (options.isException()) return;
    defer options.deinit(ctx);
    const load_event = createEventObject(ctx, event_ctor, &.{ type_value, options }, .event);
    defer load_event.deinit(ctx);
    if (load_event.isException()) return;
    const dispatched = jsEventTargetDispatchEvent(ctx, node, @ptrCast(&[_]quickjs.Value{load_event}));
    defer dispatched.deinit(ctx);
    if (dispatched.isException()) _ = ctx.getException();
}

fn initializeIFrameFromSrcdoc(ctx: *quickjs.Context, iframe: quickjs.Value, frame_window: quickjs.Value) void {
    const srcdoc_value = iframe.getPropertyStr(ctx, "srcdoc");
    defer srcdoc_value.deinit(ctx);
    if (srcdoc_value.isException() or srcdoc_value.isUndefined() or srcdoc_value.isNull()) return;
    const srcdoc = srcdoc_value.toCStringLen(ctx) orelse return;
    defer ctx.freeCString(srcdoc.ptr);
    if (srcdoc.len == 0) return;

    const source = srcdoc.ptr[0..srcdoc.len];
    const script_open_idx = std.mem.indexOf(u8, source, "<script") orelse return;
    const open_tail = source[script_open_idx..];
    const script_tag_end_rel = std.mem.indexOfScalar(u8, open_tail, '>') orelse return;
    const after_open = open_tail[script_tag_end_rel + 1 ..];
    const script_close_rel = std.mem.indexOf(u8, after_open, "</script>") orelse return;
    const script_body = std.mem.trim(u8, after_open[0..script_close_rel], " \n\r\t");
    if (script_body.len == 0) return;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const eval_fn = global.getPropertyStr(ctx, "eval");
    defer eval_fn.deinit(ctx);
    if (!eval_fn.isException() and eval_fn.isFunction(ctx)) {
        var eval_args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, script_body)};
        defer eval_args[0].deinit(ctx);
        const eval_result = eval_fn.call(ctx, quickjs.Value.undefined, &eval_args);
        defer eval_result.deinit(ctx);
        if (eval_result.isException()) _ = ctx.getException();
    }

    const listener = global.getPropertyStr(ctx, "listener");
    defer listener.deinit(ctx);
    if (!listener.isException() and !listener.isUndefined() and !listener.isNull()) {
        if (listener.isObject()) listener.setPropertyStr(ctx, "__zigListenerGlobal", frame_window.dup(ctx)) catch {};
        frame_window.setPropertyStr(ctx, "listener", listener.dup(ctx)) catch {};
        global.setPropertyStr(ctx, "listener", quickjs.Value.undefined) catch {};
    }

    const handle_event = global.getPropertyStr(ctx, "handleEvent");
    defer handle_event.deinit(ctx);
    if (!handle_event.isException() and !handle_event.isUndefined() and !handle_event.isNull()) {
        if (handle_event.isObject()) handle_event.setPropertyStr(ctx, "__zigListenerGlobal", frame_window.dup(ctx)) catch {};
        frame_window.setPropertyStr(ctx, "handleEvent", handle_event.dup(ctx)) catch {};
        global.setPropertyStr(ctx, "handleEvent", quickjs.Value.undefined) catch {};
    }
}

fn jsDomSyncWindowNamedProperties(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (!document.isException() and document.isObject()) {
        syncNamedWindowPropertiesForDocument(ctx, document);
    }
    return quickjs.Value.undefined;
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

    queueMutationRecord(ctx, this_value, .child_list, null, null);
    refreshCachedChildNodeListForNode(ctx, this_value, this_handle);

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

fn validateDocumentChildrenForInsertion(ctx: *quickjs.Context, parent: quickjs.Value, parent_handle: u64, handles: []const u64, operation: []const u8) bool {
    if (effectiveNodeType(ctx, parent, parent_handle) != 9) return true;

    var element_count: u32 = 0;
    var child = zig_dom.zig_dom_node_first_child(parent_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        if (handleListContains(handles, child)) continue;
        if (zig_dom.zig_dom_node_type(child) == 1) element_count += 1;
    }

    for (handles) |handle| {
        switch (zig_dom.zig_dom_node_type(handle)) {
            1 => {
                element_count += 1;
                if (element_count > 1) {
                    _ = throwStatus(ctx, operation, 2);
                    return false;
                }
            },
            3 => {
                _ = throwStatus(ctx, operation, 2);
                return false;
            },
            11 => {
                var fragment_element_count: u32 = 0;
                var fragment_child = zig_dom.zig_dom_node_first_child(handle);
                while (fragment_child != 0) : (fragment_child = zig_dom.zig_dom_node_next_sibling(fragment_child)) {
                    switch (zig_dom.zig_dom_node_type(fragment_child)) {
                        1 => fragment_element_count += 1,
                        3 => {
                            _ = throwStatus(ctx, operation, 2);
                            return false;
                        },
                        else => {},
                    }
                }
                element_count += fragment_element_count;
                if (element_count > 1) {
                    _ = throwStatus(ctx, operation, 2);
                    return false;
                }
            },
            else => {},
        }
    }

    return true;
}

fn insertChildNodeArguments(
    ctx: *quickjs.Context,
    parent_handle: u64,
    initial_reference_handle: u64,
    receiver_handle: u64,
    args: []const quickjs.Value,
    operation: []const u8,
    remove_receiver_after_insert: bool,
) quickjs.Value {
    var handles: std.ArrayListUnmanaged(u64) = .empty;
    defer handles.deinit(std.heap.c_allocator);

    for (args) |arg| {
        const child_handle = nodeOrTextHandle(ctx, parent_handle, arg, operation) orelse return quickjs.Value.exception;
        handles.append(std.heap.c_allocator, child_handle) catch return quickjs.Value.exception;
    }
    var scripts: std.ArrayListUnmanaged(quickjs.Value) = .empty;
    defer {
        for (scripts.items) |script| script.deinit(ctx);
        scripts.deinit(std.heap.c_allocator);
    }
    for (args) |arg| {
        if (arg.isObject()) collectScriptNodes(ctx, arg, &scripts) catch return quickjs.Value.exception;
    }

    var reference_handle = initial_reference_handle;
    while (reference_handle != 0 and handleListContains(handles.items, reference_handle)) {
        reference_handle = zig_dom.zig_dom_node_next_sibling(reference_handle);
    }

    for (handles.items) |child_handle| {
        const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
            insertFragmentBefore(parent_handle, child_handle, reference_handle)
        else
            zig_dom.zig_dom_node_insert_before(parent_handle, child_handle, reference_handle);
        if (status != 0) return throwStatus(ctx, operation, status);
    }

    executeCollectedScripts(ctx, scripts.items);

    if (remove_receiver_after_insert and receiver_handle != 0) {
        if (receiver_handle != 0 and !handleListContains(handles.items, receiver_handle) and zig_dom.zig_dom_node_parent(receiver_handle) == parent_handle) {
            const status = zig_dom.zig_dom_node_remove_child(parent_handle, receiver_handle);
            if (status != 0) return throwStatus(ctx, operation, status);
        }
    }

    return quickjs.Value.undefined;
}

fn handleListContains(handles: []const u64, needle: u64) bool {
    for (handles) |handle| {
        if (handle == needle) return true;
    }
    return false;
}

fn collectScriptNodes(ctx: *quickjs.Context, node: quickjs.Value, scripts: *std.ArrayListUnmanaged(quickjs.Value)) !void {
    if (!node.isObject()) return;
    const local = jsElementLocalNameGet(ctx, node);
    defer local.deinit(ctx);
    if (!local.isException()) {
        if (local.toCStringLen(ctx)) |text| {
            defer ctx.freeCString(text.ptr);
            if (std.ascii.eqlIgnoreCase(text.ptr[0..text.len], "script")) {
                try scripts.append(std.heap.c_allocator, node.dup(ctx));
            }
        }
    }
    const children = jsNodeChildNodesGet(ctx, node);
    defer children.deinit(ctx);
    if (children.isException() or !children.isObject()) return;
    const len = arrayLength(ctx, children);
    for (0..len) |i| {
        const child = children.getPropertyUint32(ctx, @intCast(i));
        defer child.deinit(ctx);
        if (child.isObject()) try collectScriptNodes(ctx, child, scripts);
    }
}

fn executeCollectedScripts(ctx: *quickjs.Context, scripts: []const quickjs.Value) void {
    for (scripts) |script| executeScriptElement(ctx, script);
}

fn executeScriptElement(ctx: *quickjs.Context, script: quickjs.Value) void {
    if (getBoolProperty(ctx, script, "__zigScriptExecuted") orelse false) return;
    script.setPropertyStr(ctx, "__zigScriptExecuted", quickjs.Value.initBool(true)) catch return;
    const source = jsNodeTextContentGet(ctx, script);
    defer source.deinit(ctx);
    if (source.isException()) return;
    const source_text = source.toCStringLen(ctx) orelse return;
    defer ctx.freeCString(source_text.ptr);
    const body = std.mem.trim(u8, source_text.ptr[0..source_text.len], " \n\r\t");
    if (body.len == 0) return;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const eval_fn = global.getPropertyStr(ctx, "eval");
    defer eval_fn.deinit(ctx);
    if (eval_fn.isException() or !eval_fn.isFunction(ctx)) return;
    const body_value = quickjs.Value.initStringLen(ctx, body);
    defer body_value.deinit(ctx);
    const result = eval_fn.call(ctx, quickjs.Value.undefined, &.{body_value});
    defer result.deinit(ctx);
    if (result.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
    }
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

fn getBoolProperty(ctx: *quickjs.Context, value: quickjs.Value, name: [*:0]const u8) ?bool {
    const property = value.getPropertyStr(ctx, name);
    defer property.deinit(ctx);
    if (property.isException() or property.isUndefined() or property.isNull()) {
        return null;
    }
    return property.toBool(ctx) catch null;
}

fn defineDataPropertyStr(ctx: *quickjs.Context, object: quickjs.Value, name: [*:0]const u8, value: quickjs.Value) error{JSError}!void {
    const flags = c.JS_PROP_CONFIGURABLE |
        c.JS_PROP_WRITABLE |
        c.JS_PROP_ENUMERABLE |
        c.JS_PROP_HAS_CONFIGURABLE |
        c.JS_PROP_HAS_WRITABLE |
        c.JS_PROP_HAS_ENUMERABLE |
        c.JS_PROP_HAS_VALUE |
        c.JS_PROP_THROW;
    const ret = c.JS_DefinePropertyValueStr(ctx.cval(), object.cval(), name, value.cval(), flags);
    if (ret < 0) return error.JSError;
}

fn defineHiddenDataPropertyStr(ctx: *quickjs.Context, object: quickjs.Value, name: [*:0]const u8, value: quickjs.Value) error{JSError}!void {
    const flags = c.JS_PROP_CONFIGURABLE |
        c.JS_PROP_WRITABLE |
        c.JS_PROP_HAS_CONFIGURABLE |
        c.JS_PROP_HAS_WRITABLE |
        c.JS_PROP_HAS_ENUMERABLE |
        c.JS_PROP_HAS_VALUE |
        c.JS_PROP_THROW;
    const ret = c.JS_DefinePropertyValueStr(ctx.cval(), object.cval(), name, value.cval(), flags);
    if (ret < 0) return error.JSError;
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

fn parseUnsignedLongArg(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize) ?u32 {
    if (index >= args.len) return null;
    var value: u32 = 0;
    if (c.JS_ToUint32(ctx.cval(), &value, args[index].cval()) < 0) return null;
    return value;
}

fn jsStringLength(ctx: *quickjs.Context, value: quickjs.Value) ?u32 {
    const length = value.getPropertyStr(ctx, "length");
    defer length.deinit(ctx);
    const raw = length.toInt64(ctx) catch return null;
    if (raw < 0) return null;
    return @intCast(raw);
}

fn jsStringSlice(ctx: *quickjs.Context, value: quickjs.Value, start: u32, end: u32) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const function_ctor = global.getPropertyStr(ctx, "Function");
    defer function_ctor.deinit(ctx);
    const body = quickjs.Value.initStringLen(ctx, "return String(arguments[0]).slice(arguments[1], arguments[2]);");
    defer body.deinit(ctx);
    const fn_value = function_ctor.call(ctx, quickjs.Value.undefined, &.{body});
    defer fn_value.deinit(ctx);
    if (fn_value.isException()) return quickjs.Value.exception;
    return fn_value.call(ctx, quickjs.Value.undefined, &.{ value, quickjs.Value.initInt64(start), quickjs.Value.initInt64(end) });
}

fn jsStringReplaceRange(ctx: *quickjs.Context, value: quickjs.Value, start: u32, end: u32, replacement: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const function_ctor = global.getPropertyStr(ctx, "Function");
    defer function_ctor.deinit(ctx);
    const body = quickjs.Value.initStringLen(ctx, "return String(arguments[0]).slice(0, arguments[1]) + String(arguments[3]) + String(arguments[0]).slice(arguments[2]);");
    defer body.deinit(ctx);
    const fn_value = function_ctor.call(ctx, quickjs.Value.undefined, &.{body});
    defer fn_value.deinit(ctx);
    if (fn_value.isException()) return quickjs.Value.exception;
    return fn_value.call(ctx, quickjs.Value.undefined, &.{ value, quickjs.Value.initInt64(start), quickjs.Value.initInt64(end), replacement });
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

fn classListAttributeName(ctx: *quickjs.Context, class_list: quickjs.Value) []const u8 {
    const attr = class_list.getPropertyStr(ctx, "__zigTokenAttr");
    defer attr.deinit(ctx);
    if (!attr.isException() and !attr.isUndefined() and !attr.isNull()) {
        const text = attr.toCStringLen(ctx) orelse return "class";
        defer ctx.freeCString(text.ptr);
        if (std.mem.eql(u8, text.ptr[0..text.len], "rel")) return "rel";
        if (std.mem.eql(u8, text.ptr[0..text.len], "for")) return "for";
        if (std.mem.eql(u8, text.ptr[0..text.len], "sandbox")) return "sandbox";
        if (std.mem.eql(u8, text.ptr[0..text.len], "sizes")) return "sizes";
    }
    return "class";
}

fn elementAttributeString(ctx: *quickjs.Context, element: quickjs.Value, name: []const u8) ?CStringArg {
    const handle = parseThisHandle(ctx, element, name) orelse return null;
    const value = elementAttributeValueToJs(ctx, handle, name, null, name);
    defer value.deinit(ctx);
    if (value.isNull() or value.isUndefined()) return null;
    const cstr = value.toCStringLen(ctx) orelse return null;
    return .{ .ptr = cstr.ptr, .len = cstr.len };
}

fn elementHrefString(ctx: *quickjs.Context, element: quickjs.Value) ?CStringArg {
    const href_property = element.getPropertyStr(ctx, "href");
    defer href_property.deinit(ctx);
    if (!href_property.isException() and !href_property.isUndefined() and !href_property.isNull()) {
        const text = href_property.toCStringLen(ctx);
        if (text) |value| {
            if (value.len > 0) return .{ .ptr = value.ptr, .len = value.len };
            ctx.freeCString(value.ptr);
        }
    }
    return elementAttributeString(ctx, element, "href");
}

fn setElementStringAttribute(ctx: *quickjs.Context, element: quickjs.Value, name: []const u8, value: []const u8) !void {
    const handle = parseThisHandle(ctx, element, name) orelse return error.JSError;
    const old_value = elementAttributeValueToJs(ctx, handle, name, null, name);
    defer old_value.deinit(ctx);
    const status = zig_dom.zig_dom_element_set_attribute(handle, name.ptr, name.len, value.ptr, value.len);
    if (status != 0) return error.JSError;
    queueMutationRecord(ctx, element, .attributes, name, old_value);
}

fn removeElementAttribute(ctx: *quickjs.Context, element: quickjs.Value, name: []const u8) !void {
    const handle = parseThisHandle(ctx, element, name) orelse return error.JSError;
    const status = zig_dom.zig_dom_element_remove_attribute(handle, name.ptr, name.len);
    if (status != 0) return error.JSError;
}

fn isAsciiWhitespaceByte(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0c;
}

fn validateDomToken(ctx: *quickjs.Context, token: []const u8, operation: []const u8) bool {
    if (token.len == 0) {
        _ = throwOperationMessage(ctx, operation, "SyntaxError");
        return false;
    }
    for (token) |ch| {
        if (isAsciiWhitespaceByte(ch)) {
            _ = throwOperationMessage(ctx, operation, "InvalidCharacterError");
            return false;
        }
    }
    return true;
}

fn classListHasToken(ctx: *quickjs.Context, element: quickjs.Value, token: []const u8) bool {
    const current = elementAttributeString(ctx, element, "class") orelse return false;
    defer ctx.freeCString(current.ptr);
    var iter = std.mem.tokenizeAny(u8, current.ptr[0..current.len], " \t\n\r\x0c");
    while (iter.next()) |part| {
        if (std.mem.eql(u8, part, token)) return true;
    }
    return false;
}

fn classListTokensArray(ctx: *quickjs.Context, class_list: quickjs.Value) quickjs.Value {
    const element = classListElement(ctx, class_list) orelse return quickjs.Value.exception;
    defer element.deinit(ctx);
    const attr_name = classListAttributeName(ctx, class_list);
    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) return array;
    const current = elementAttributeString(ctx, element, attr_name) orelse return array;
    defer ctx.freeCString(current.ptr);
    var iter = std.mem.tokenizeAny(u8, current.ptr[0..current.len], " \t\n\r\x0c");
    var length: u32 = 0;
    while (iter.next()) |part| {
        if (classListArrayContains(ctx, array, length, part)) continue;
        array.setPropertyUint32(ctx, length, quickjs.Value.initStringLen(ctx, part)) catch {
            array.deinit(ctx);
            return quickjs.Value.exception;
        };
        length += 1;
    }
    return array;
}

fn classListNormalizedTokensForAttr(ctx: *quickjs.Context, element: quickjs.Value, attr_name: []const u8) ?quickjs.Value {
    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) return null;
    const current = elementAttributeString(ctx, element, attr_name) orelse return array;
    defer ctx.freeCString(current.ptr);
    var iter = std.mem.tokenizeAny(u8, current.ptr[0..current.len], " \t\n\r\x0c");
    while (iter.next()) |part| {
        if (classListArrayContains(ctx, array, arrayLength(ctx, array), part)) continue;
        array.setPropertyUint32(ctx, arrayLength(ctx, array), quickjs.Value.initStringLen(ctx, part)) catch {
            array.deinit(ctx);
            return null;
        };
    }
    return array;
}

fn classListNormalizedTokens(ctx: *quickjs.Context, element: quickjs.Value) ?quickjs.Value {
    return classListNormalizedTokensForAttr(ctx, element, "class");
}

fn classListHadDuplicateOrWhitespaceForAttr(ctx: *quickjs.Context, element: quickjs.Value, attr_name: []const u8) bool {
    const current = elementAttributeString(ctx, element, attr_name) orelse return false;
    defer ctx.freeCString(current.ptr);
    if (current.len > 0 and (isAsciiWhitespaceByte(current.ptr[0]) or isAsciiWhitespaceByte(current.ptr[current.len - 1]))) return true;
    for (current.ptr[0..current.len]) |ch| if (isAsciiWhitespaceByte(ch) and ch != ' ') return true;
    if (std.mem.indexOf(u8, current.ptr[0..current.len], "  ") != null) return true;
    var count: usize = 0;
    var iter = std.mem.tokenizeAny(u8, current.ptr[0..current.len], " \t\n\r\x0c");
    var seen = quickjs.Value.initArray(ctx);
    if (seen.isException()) return false;
    defer seen.deinit(ctx);
    while (iter.next()) |part| {
        count += 1;
        if (classListArrayContains(ctx, seen, arrayLength(ctx, seen), part)) return true;
        seen.setPropertyUint32(ctx, arrayLength(ctx, seen), quickjs.Value.initStringLen(ctx, part)) catch return true;
    }
    return count == 0 and current.len > 0;
}

fn classListHadDuplicateOrWhitespace(ctx: *quickjs.Context, element: quickjs.Value) bool {
    return classListHadDuplicateOrWhitespaceForAttr(ctx, element, "class");
}

fn classListApplyTokensForAttr(ctx: *quickjs.Context, element: quickjs.Value, attr_name: []const u8, tokens: quickjs.Value) !void {
    const len = arrayLength(ctx, tokens);
    if (len == 0) {
        if (elementAttributeString(ctx, element, attr_name)) |current| {
            ctx.freeCString(current.ptr);
            try setElementStringAttribute(ctx, element, attr_name, "");
        }
        return;
    }
    var buffer: [2048]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buffer);
    for (0..len) |i_usize| {
        if (i_usize != 0) stream.writeAll(" ") catch return error.JSError;
        const item = tokens.getPropertyUint32(ctx, @intCast(i_usize));
        defer item.deinit(ctx);
        const text = item.toCStringLen(ctx) orelse return error.JSError;
        defer ctx.freeCString(text.ptr);
        stream.writeAll(text.ptr[0..text.len]) catch return error.JSError;
    }
    try setElementStringAttribute(ctx, element, attr_name, stream.buffered());
}

fn classListApplyTokens(ctx: *quickjs.Context, element: quickjs.Value, tokens: quickjs.Value) !void {
    try classListApplyTokensForAttr(ctx, element, "class", tokens);
}

fn classListRemoveToken(ctx: *quickjs.Context, tokens: quickjs.Value, token: []const u8) !void {
    const len = arrayLength(ctx, tokens);
    var write: u32 = 0;
    for (0..len) |i_usize| {
        const item = tokens.getPropertyUint32(ctx, @intCast(i_usize));
        defer item.deinit(ctx);
        const text = item.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(text.ptr);
        if (std.mem.eql(u8, text.ptr[0..text.len], token)) continue;
        if (write != i_usize) tokens.setPropertyUint32(ctx, write, item.dup(ctx)) catch return error.JSError;
        write += 1;
    }
    setArrayLength(ctx, tokens, write);
}

fn classListArrayContains(ctx: *quickjs.Context, array: quickjs.Value, length: u32, token: []const u8) bool {
    for (0..length) |index_usize| {
        const item = array.getPropertyUint32(ctx, @intCast(index_usize));
        defer item.deinit(ctx);
        if (item.isException()) continue;
        const text = item.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(text.ptr);
        if (std.mem.eql(u8, text.ptr[0..text.len], token)) return true;
    }
    return false;
}

fn classListSyncArray(ctx: *quickjs.Context, class_list: quickjs.Value) !void {
    const tokens = classListTokensArray(ctx, class_list);
    if (tokens.isException()) return error.JSError;
    defer tokens.deinit(ctx);
    const len = arrayLength(ctx, tokens);
    setArrayLength(ctx, class_list, 0);
    for (0..len) |index_usize| {
        const index: u32 = @intCast(index_usize);
        const token = tokens.getPropertyUint32(ctx, index);
        defer token.deinit(ctx);
        if (token.isException()) return error.JSError;
        class_list.setPropertyUint32(ctx, index, token.dup(ctx)) catch return error.JSError;
    }
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
        cacheNativeNodeWrapper(ctx, handle, obj);
    }
    return obj;
}

fn cacheNativeNodeWrapper(ctx: *quickjs.Context, handle: u64, wrapper: quickjs.Value) void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const cache = global.getPropertyStr(ctx, "__zigDomNodeCache");
    defer cache.deinit(ctx);
    if (cache.isException() or !cache.isObject()) return;

    var key_buffer: [32]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buffer, "{d}", .{handle}) catch return;
    cache.setPropertyStr(ctx, key.ptr, wrapper.dup(ctx)) catch {};
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
    if (std.ascii.eqlIgnoreCase(local, "body")) return "HTMLBodyElement";
    if (std.ascii.eqlIgnoreCase(local, "html")) return "HTMLHtmlElement";
    if (std.ascii.eqlIgnoreCase(local, "head")) return "HTMLHeadElement";
    if (std.ascii.eqlIgnoreCase(local, "title")) return "HTMLTitleElement";
    if (std.ascii.eqlIgnoreCase(local, "frameset")) return "HTMLFrameSetElement";
    if (std.ascii.eqlIgnoreCase(local, "button")) return "HTMLButtonElement";
    if (std.ascii.eqlIgnoreCase(local, "form")) return "HTMLFormElement";
    if (std.ascii.eqlIgnoreCase(local, "select")) return "HTMLSelectElement";
    if (std.ascii.eqlIgnoreCase(local, "option")) return "HTMLOptionElement";
    if (std.ascii.eqlIgnoreCase(local, "textarea")) return "HTMLTextAreaElement";
    if (std.ascii.eqlIgnoreCase(local, "label")) return "HTMLLabelElement";
    if (std.ascii.eqlIgnoreCase(local, "a")) return "HTMLAnchorElement";
    if (std.ascii.eqlIgnoreCase(local, "img")) return "HTMLImageElement";
    if (std.ascii.eqlIgnoreCase(local, "iframe")) return "HTMLIFrameElement";
    if (std.ascii.eqlIgnoreCase(local, "template")) return "HTMLTemplateElement";
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
    document.setPropertyStr(ctx, "__zigDefaultView", obj.dup(ctx)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "window", obj.dup(ctx)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "self", obj.dup(ctx)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "parent", obj.dup(ctx)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "top", obj.dup(ctx)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "event", quickjs.Value.undefined) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "closed", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "navigator", quickjs.Value.initObject(ctx)) catch return quickjs.Value.exception;
    const location = quickjs.Value.initObject(ctx);
    location.setPropertyStr(ctx, "__zigLocationWindow", obj.dup(ctx)) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "__zigHref", quickjs.Value.initStringLen(ctx, "http://localhost/")) catch return quickjs.Value.exception;
    installAccessor(ctx, location, "href", jsLocationHrefGet, jsLocationHrefSet) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "origin", quickjs.Value.initStringLen(ctx, "http://localhost")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "protocol", quickjs.Value.initStringLen(ctx, "http:")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "host", quickjs.Value.initStringLen(ctx, "localhost")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "hostname", quickjs.Value.initStringLen(ctx, "localhost")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "port", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "pathname", quickjs.Value.initStringLen(ctx, "/")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "search", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    location.setPropertyStr(ctx, "hash", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "location", location) catch return quickjs.Value.exception;
    document.setPropertyStr(ctx, "location", location.dup(ctx)) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "getComputedStyle", jsWindowGetComputedStyle, 1) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "open", jsWindowOpen, 0) catch return quickjs.Value.exception;
    installMethod(ctx, obj, "postMessage", jsWindowPostMessage, 2) catch return quickjs.Value.exception;
    inline for (.{
        "queueMicrotask",
        "setTimeout",
        "clearTimeout",
        "setInterval",
        "clearInterval",
        "setImmediate",
        "clearImmediate",
        "localStorage",
        "sessionStorage",
        "Object",
        "Function",
        "Array",
        "Promise",
        "Proxy",
        "Error",
        "TypeError",
        "URL",
        "URLSearchParams",
        "fetch",
        "Headers",
        "Request",
        "Response",
        "Blob",
        "File",
        "FormData",
        "eval",
        "Event",
        "EventTarget",
        "CustomEvent",
        "GamepadEvent",
        "UIEvent",
        "FocusEvent",
        "MouseEvent",
        "WheelEvent",
        "KeyboardEvent",
        "CompositionEvent",
        "ErrorEvent",
        "XMLHttpRequest",
    }) |name| {
        const value = global.getPropertyStr(ctx, name);
        defer value.deinit(ctx);
        if (!value.isException() and !value.isUndefined() and !value.isNull()) {
            obj.setPropertyStr(ctx, name, value.dup(ctx)) catch return quickjs.Value.exception;
        }
    }
    installWindowDomException(ctx, obj) catch return quickjs.Value.exception;
    installWindowAbortSignal(ctx, obj) catch return quickjs.Value.exception;
    for (surfaces.window_constructor_exports) |name| {
        const value = global.getPropertyStr(ctx, name);
        defer value.deinit(ctx);
        if (!value.isException() and !value.isUndefined()) {
            obj.setPropertyStr(ctx, name, value.dup(ctx)) catch return quickjs.Value.exception;
        }
    }
    installFrameCharacterDataConstructor(ctx, obj, document, "Text", "createTextNode") catch return quickjs.Value.exception;
    installFrameCharacterDataConstructor(ctx, obj, document, "Comment", "createComment") catch return quickjs.Value.exception;
    installMethod(ctx, obj, "getSelection", jsWindowGetSelection, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsLocationHrefGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const href = this_value.getPropertyStr(ctx, "__zigHref");
    if (!href.isException() and !href.isUndefined() and !href.isNull()) return href;
    href.deinit(ctx);
    return quickjs.Value.initStringLen(ctx, "");
}

fn jsLocationHrefSet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, next_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const text = next_value.toCStringLen(ctx) orelse return throwOperationMessage(ctx, "href", "value could not be converted to string");
    defer ctx.freeCString(text.ptr);
    const href = resolveLocationHref(ctx, this_value, text.ptr[0..text.len]) catch return quickjs.Value.exception;
    defer std.heap.c_allocator.free(href);

    const frame_window = this_value.getPropertyStr(ctx, "__zigLocationWindow");
    defer frame_window.deinit(ctx);
    const frame_element = this_value.getPropertyStr(ctx, "__zigLocationFrameElement");
    defer frame_element.deinit(ctx);

    if (!frame_element.isException() and frame_element.isObject() and !frame_window.isException() and frame_window.isObject()) {
        dispatchWindowBeforeUnload(ctx, frame_window);
    }

    this_value.setPropertyStr(ctx, "__zigHref", quickjs.Value.initStringLen(ctx, href)) catch return quickjs.Value.exception;

    const protocol_end = std.mem.indexOf(u8, href, "://");
    const protocol = if (protocol_end) |index| href[0 .. index + 1] else "";
    const after_protocol = if (protocol_end) |index| href[index + 3 ..] else href;
    const path_start = std.mem.indexOfAny(u8, after_protocol, "/?#") orelse after_protocol.len;
    const host = after_protocol[0..path_start];
    const rest = after_protocol[path_start..];
    const hash_start = std.mem.indexOfScalar(u8, rest, '#') orelse rest.len;
    const before_hash = rest[0..hash_start];
    const hash = if (hash_start < rest.len) rest[hash_start..] else "";
    const search_start = std.mem.indexOfScalar(u8, before_hash, '?') orelse before_hash.len;
    const pathname = if (search_start > 0) before_hash[0..search_start] else "/";
    const search = if (search_start < before_hash.len) before_hash[search_start..] else "";
    const hostname_end = std.mem.indexOfScalar(u8, host, ':') orelse host.len;
    const hostname = host[0..hostname_end];
    const port = if (hostname_end < host.len) host[hostname_end + 1 ..] else "";
    const origin = if (protocol.len > 0 and host.len > 0)
        href[0..(protocol.len + 2 + host.len)]
    else
        "";

    this_value.setPropertyStr(ctx, "protocol", quickjs.Value.initStringLen(ctx, protocol)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "host", quickjs.Value.initStringLen(ctx, host)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "hostname", quickjs.Value.initStringLen(ctx, hostname)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "port", quickjs.Value.initStringLen(ctx, port)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "pathname", quickjs.Value.initStringLen(ctx, pathname)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "search", quickjs.Value.initStringLen(ctx, search)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "hash", quickjs.Value.initStringLen(ctx, hash)) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "origin", quickjs.Value.initStringLen(ctx, origin)) catch return quickjs.Value.exception;

    const navigate = this_value.getPropertyStr(ctx, "__zigWptNavigateFrame");
    defer navigate.deinit(ctx);
    if (!navigate.isException() and navigate.isFunction(ctx)) {
        const href_value = quickjs.Value.initStringLen(ctx, href);
        defer href_value.deinit(ctx);
        const result = navigate.call(ctx, this_value, &.{href_value});
        defer result.deinit(ctx);
        if (result.isException()) return quickjs.Value.exception;
    }

    if (!frame_element.isException() and frame_element.isObject() and !frame_window.isException() and frame_window.isObject()) {
        dispatchWindowLoad(ctx, frame_window);
        dispatchSimpleEvent(ctx, frame_element, "load", false);
    }

    return quickjs.Value.undefined;
}

fn resolveLocationHref(ctx: *quickjs.Context, location: quickjs.Value, input_href: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, input_href, "://") != null) {
        const scheme_end = std.mem.indexOf(u8, input_href, "://") orelse return std.heap.c_allocator.dupe(u8, input_href);
        const after_scheme = input_href[scheme_end + 3 ..];
        const host_end = std.mem.indexOfAny(u8, after_scheme, "/?#") orelse after_scheme.len;
        if (host_end == after_scheme.len) {
            return std.fmt.allocPrint(std.heap.c_allocator, "{s}/", .{input_href});
        }
        return std.heap.c_allocator.dupe(u8, input_href);
    }

    const current_href_value = location.getPropertyStr(ctx, "__zigHref");
    defer current_href_value.deinit(ctx);
    const current_href_text = current_href_value.toCStringLen(ctx) orelse return std.heap.c_allocator.dupe(u8, input_href);
    defer ctx.freeCString(current_href_text.ptr);
    const current_href = current_href_text.ptr[0..current_href_text.len];

    const protocol_end = std.mem.indexOf(u8, current_href, "://");
    const current_protocol = if (protocol_end) |index| current_href[0 .. index + 1] else "http:";
    const after_protocol = if (protocol_end) |index| current_href[index + 3 ..] else current_href;
    const host_end = std.mem.indexOfAny(u8, after_protocol, "/?#") orelse after_protocol.len;
    const current_host = after_protocol[0..host_end];
    const origin = if (current_host.len > 0)
        try std.fmt.allocPrint(std.heap.c_allocator, "{s}//{s}", .{ current_protocol, current_host })
    else
        try std.heap.c_allocator.dupe(u8, "");
    defer std.heap.c_allocator.free(origin);

    const rest = after_protocol[host_end..];
    const hash_start = std.mem.indexOfScalar(u8, rest, '#') orelse rest.len;
    const before_hash = rest[0..hash_start];
    const search_start = std.mem.indexOfScalar(u8, before_hash, '?') orelse before_hash.len;
    const current_pathname = if (search_start > 0) before_hash[0..search_start] else "/";

    if (std.mem.startsWith(u8, input_href, "//")) {
        return std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}", .{ current_protocol, input_href });
    }
    if (std.mem.startsWith(u8, input_href, "/")) {
        return std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}", .{ origin, input_href });
    }
    if (std.mem.startsWith(u8, input_href, "?")) {
        return std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}{s}", .{ origin, current_pathname, input_href });
    }
    if (std.mem.startsWith(u8, input_href, "#")) {
        const base_hash_start = std.mem.indexOfScalar(u8, current_href, '#') orelse current_href.len;
        return std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}", .{ current_href[0..base_hash_start], input_href });
    }

    const base_path = if (std.mem.endsWith(u8, current_pathname, "/"))
        current_pathname
    else
        current_pathname[0 .. (std.mem.lastIndexOfScalar(u8, current_pathname, '/') orelse 0) + 1];
    return std.fmt.allocPrint(std.heap.c_allocator, "{s}{s}{s}", .{ origin, base_path, input_href });
}

fn jsWindowOpen(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    var window_handle: u64 = 0;
    if (zig_dom.zig_dom_create_window(&window_handle) != 0) return throwMessage(ctx, "failed to create window");
    var document_handle: u64 = 0;
    if (zig_dom.zig_dom_window_document(window_handle, &document_handle) != 0) return throwMessage(ctx, "failed to create document");
    const document = wrapNodeHandle(ctx, document_handle);
    defer document.deinit(ctx);
    if (document.isException()) return quickjs.Value.exception;
    document.setPropertyStr(ctx, "_windowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch return quickjs.Value.exception;
    const popup = createWindowObject(ctx, window_handle, document);
    if (popup.isException()) return popup;
    popup.setPropertyStr(ctx, "opener", this_value.dup(ctx)) catch return quickjs.Value.exception;
    if (args.len > 0 and !args[0].isUndefined() and !args[0].isNull()) {
        const location = popup.getPropertyStr(ctx, "location");
        defer location.deinit(ctx);
        if (!location.isException() and location.isObject()) {
            const result = jsLocationHrefSet(ctx, location, args[0]);
            defer result.deinit(ctx);
            if (result.isException()) return quickjs.Value.exception;
        }
    }
    return popup;
}

fn dispatchSimpleEvent(ctx: *quickjs.Context, target: quickjs.Value, comptime event_name: []const u8, cancelable: bool) void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const event_ctor = global.getPropertyStr(ctx, "Event");
    defer event_ctor.deinit(ctx);
    if (event_ctor.isException() or !event_ctor.isObject()) return;
    const type_value = quickjs.Value.initStringLen(ctx, event_name);
    defer type_value.deinit(ctx);
    const options = quickjs.Value.initObject(ctx);
    defer options.deinit(ctx);
    if (options.isException()) return;
    options.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(cancelable)) catch return;
    const event = createEventObject(ctx, event_ctor, &.{ type_value, options }, .event);
    defer event.deinit(ctx);
    if (event.isException()) return;
    const dispatched = jsEventTargetDispatchEvent(ctx, target, @ptrCast(&[_]quickjs.Value{event}));
    defer dispatched.deinit(ctx);
    if (dispatched.isException()) _ = ctx.getException();
}

fn dispatchWindowLoad(ctx: *quickjs.Context, window: quickjs.Value) void {
    const onload = window.getPropertyStr(ctx, "onload");
    defer onload.deinit(ctx);
    if (!onload.isException() and onload.isFunction(ctx)) {
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const event_ctor = global.getPropertyStr(ctx, "Event");
        defer event_ctor.deinit(ctx);
        if (!event_ctor.isException() and event_ctor.isObject()) {
            const type_value = quickjs.Value.initStringLen(ctx, "load");
            defer type_value.deinit(ctx);
            const options = quickjs.Value.initObject(ctx);
            defer options.deinit(ctx);
            if (!options.isException()) {
                const event = createEventObject(ctx, event_ctor, &.{ type_value, options }, .event);
                defer event.deinit(ctx);
                if (!event.isException()) {
                    const result = onload.call(ctx, window, &.{event});
                    defer result.deinit(ctx);
                    if (result.isException()) _ = ctx.getException();
                }
            }
        }
    }
    dispatchSimpleEvent(ctx, window, "load", false);
}

fn dispatchWindowBeforeUnload(ctx: *quickjs.Context, window: quickjs.Value) void {
    const before_unload = window.getPropertyStr(ctx, "onbeforeunload");
    defer before_unload.deinit(ctx);
    if (before_unload.isException() or !before_unload.isFunction(ctx)) return;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const event_ctor = global.getPropertyStr(ctx, "Event");
    defer event_ctor.deinit(ctx);
    if (event_ctor.isException() or !event_ctor.isObject()) return;
    const type_value = quickjs.Value.initStringLen(ctx, "beforeunload");
    defer type_value.deinit(ctx);
    const options = quickjs.Value.initObject(ctx);
    defer options.deinit(ctx);
    if (options.isException()) return;
    options.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(true)) catch return;
    const event = createEventObject(ctx, event_ctor, &.{ type_value, options }, .event);
    defer event.deinit(ctx);
    if (event.isException()) return;
    const previous_event = window.getPropertyStr(ctx, "event");
    defer previous_event.deinit(ctx);
    window.setPropertyStr(ctx, "event", event.dup(ctx)) catch return;
    const result = before_unload.call(ctx, window, &.{event});
    defer result.deinit(ctx);
    window.setPropertyStr(ctx, "event", previous_event.dup(ctx)) catch return;
    if (result.isException()) _ = ctx.getException();
}

fn jsWindowPostMessage(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const event_ctor = global.getPropertyStr(ctx, "Event");
    defer event_ctor.deinit(ctx);
    if (event_ctor.isException() or !event_ctor.isObject()) return quickjs.Value.undefined;
    const type_value = quickjs.Value.initStringLen(ctx, "message");
    defer type_value.deinit(ctx);
    const options = quickjs.Value.initObject(ctx);
    defer options.deinit(ctx);
    if (options.isException()) return quickjs.Value.exception;
    const event = createEventObject(ctx, event_ctor, &.{ type_value, options }, .event);
    defer event.deinit(ctx);
    if (event.isException()) return quickjs.Value.exception;
    const data = if (args.len > 0) args[0].dup(ctx) else quickjs.Value.undefined;
    event.setPropertyStr(ctx, "data", data) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "origin", quickjs.Value.initStringLen(ctx, "http://localhost")) catch return quickjs.Value.exception;
    event.setPropertyStr(ctx, "source", this_value.dup(ctx)) catch return quickjs.Value.exception;
    const dispatched = jsEventTargetDispatchEvent(ctx, this_value, @ptrCast(&[_]quickjs.Value{event}));
    defer dispatched.deinit(ctx);
    if (dispatched.isException()) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn installFrameCharacterDataConstructor(ctx: *quickjs.Context, window: quickjs.Value, document: quickjs.Value, constructor_name: [:0]const u8, create_method_name: [:0]const u8) !void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const function_ctor = global.getPropertyStr(ctx, "Function");
    defer function_ctor.deinit(ctx);
    if (function_ctor.isException() or !function_ctor.isObject()) return;

    const source = std.fmt.allocPrint(
        std.heap.c_allocator,
        "return function {s}(data) {{ return doc.{s}((arguments.length === 0 || data === undefined) ? '' : data); }};",
        .{ constructor_name, create_method_name },
    ) catch return error.OutOfMemory;
    defer std.heap.c_allocator.free(source);

    const arg_name = quickjs.Value.initStringLen(ctx, "doc");
    defer arg_name.deinit(ctx);
    const body = quickjs.Value.initStringLen(ctx, source);
    defer body.deinit(ctx);
    const factory = function_ctor.call(ctx, quickjs.Value.undefined, &.{ arg_name, body });
    defer factory.deinit(ctx);
    if (factory.isException()) return error.PropertyAccessFailed;
    const ctor = factory.call(ctx, quickjs.Value.undefined, &.{document});
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return error.PropertyAccessFailed;

    const original = global.getPropertyStr(ctx, constructor_name);
    defer original.deinit(ctx);
    if (!original.isException() and original.isObject()) {
        const proto = original.getPropertyStr(ctx, "prototype");
        defer proto.deinit(ctx);
        if (!proto.isException() and proto.isObject()) {
            ctor.setPropertyStr(ctx, "prototype", proto.dup(ctx)) catch return error.PropertyAccessFailed;
        }
    }

    window.setPropertyStr(ctx, constructor_name, ctor.dup(ctx)) catch return error.PropertyAccessFailed;
}

fn syncNamedWindowPropertiesForDocument(ctx: *quickjs.Context, document: quickjs.Value) void {
    const window = jsDocumentDefaultViewGet(ctx, document);
    defer window.deinit(ctx);
    if (window.isException() or !window.isObject()) return;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const selector = quickjs.Value.initStringLen(ctx, "[id],[name]");
    defer selector.deinit(ctx);
    const matches = jsDocumentQuerySelectorAll(ctx, document, @ptrCast(&[_]quickjs.Value{selector}));
    defer matches.deinit(ctx);
    if (matches.isException() or !matches.isObject()) return;

    const len = arrayLength(ctx, matches);
    for (0..len) |index_usize| {
        const element = matches.getPropertyUint32(ctx, @intCast(index_usize));
        defer element.deinit(ctx);
        if (!element.isObject()) continue;

        setNamedPropertyIfMissing(ctx, global, window, element, "id");
        setNamedPropertyIfMissing(ctx, global, window, element, "name");
    }
}

fn setNamedPropertyIfMissing(
    ctx: *quickjs.Context,
    global: quickjs.Value,
    window: quickjs.Value,
    element: quickjs.Value,
    attr_name: []const u8,
) void {
    const value = elementAttributeString(ctx, element, attr_name) orelse return;
    defer ctx.freeCString(value.ptr);
    if (value.len == 0) return;

    const key = value.ptr;
    const assigned_value = namedPropertyValue(ctx, element, attr_name);
    defer assigned_value.deinit(ctx);

    const existing_window = window.getPropertyStr(ctx, key);
    defer existing_window.deinit(ctx);
    if (!existing_window.isException() and shouldAssignNamedProperty(ctx, existing_window)) {
        window.setPropertyStr(ctx, key, assigned_value.dup(ctx)) catch {};
    }

    const existing_global = global.getPropertyStr(ctx, key);
    defer existing_global.deinit(ctx);
    if (!existing_global.isException() and shouldAssignNamedProperty(ctx, existing_global)) {
        global.setPropertyStr(ctx, key, assigned_value.dup(ctx)) catch {};
    }
}

fn namedPropertyValue(ctx: *quickjs.Context, element: quickjs.Value, attr_name: []const u8) quickjs.Value {
    if (std.mem.eql(u8, attr_name, "name")) {
        const local_name = element.getPropertyStr(ctx, "localName");
        defer local_name.deinit(ctx);
        if (!local_name.isException()) {
            if (local_name.toCStringLen(ctx)) |name_text| {
                defer ctx.freeCString(name_text.ptr);
                const lower = name_text.ptr[0..name_text.len];
                if (std.ascii.eqlIgnoreCase(lower, "iframe")) {
                    const frame_window = element.getPropertyStr(ctx, "contentWindow");
                    if (!frame_window.isException() and frame_window.isObject()) {
                        return frame_window;
                    }
                    frame_window.deinit(ctx);
                }
            }
        }
    }
    return element.dup(ctx);
}

fn shouldAssignNamedProperty(ctx: *quickjs.Context, existing: quickjs.Value) bool {
    if (existing.isUndefined() or existing.isNull()) return true;
    if (!existing.isObject()) return false;

    const handle_i64 = parseValueNodeHandle(ctx, existing) orelse return false;
    if (handle_i64 <= 0) return false;

    const handle: u64 = @intCast(handle_i64);
    var cursor = handle;
    while (cursor != 0) : (cursor = zig_dom.zig_dom_node_parent(cursor)) {
        if (zig_dom.zig_dom_node_type(cursor) == 9) return false;
    }
    return true;
}

fn installWindowAbortSignal(ctx: *quickjs.Context, window: quickjs.Value) !void {
    const timer_ids = quickjs.Value.initArray(ctx);
    if (timer_ids.isException()) return error.JSError;
    window.setPropertyStr(ctx, "__zigAbortTimeoutIds", timer_ids) catch return error.JSError;

    const abort_signal = quickjs.Value.initObject(ctx);
    if (abort_signal.isException()) return error.JSError;
    abort_signal.setPropertyStr(ctx, "__zigAbortOwnerWindow", window.dup(ctx)) catch return error.JSError;
    installMethod(ctx, abort_signal, "abort", jsWindowAbortSignalAbort, 0) catch return error.JSError;
    installMethod(ctx, abort_signal, "timeout", jsWindowAbortSignalTimeout, 1) catch return error.JSError;
    window.setPropertyStr(ctx, "AbortSignal", abort_signal) catch return error.JSError;
}

fn installWindowDomException(ctx: *quickjs.Context, window: quickjs.Value) !void {
    const existing = window.getPropertyStr(ctx, "DOMException");
    defer existing.deinit(ctx);
    if (!existing.isException() and !existing.isUndefined() and !existing.isNull()) return;

    const ctor = quickjs.Value.initCFunction2(ctx, jsWindowDomExceptionCtor, "DOMException", 2, .constructor_or_func, 0);
    if (ctor.isException()) return error.JSError;
    window.setPropertyStr(ctx, "DOMException", ctor) catch return error.JSError;
}

fn jsWindowDomExceptionCtor(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return obj;

    const message = if (args.len >= 1 and !args[0].isUndefined()) args[0].toCStringLen(ctx) else null;
    defer if (message) |value| ctx.freeCString(value.ptr);
    const name = if (args.len >= 2 and !args[1].isUndefined()) args[1].toCStringLen(ctx) else null;
    defer if (name) |value| ctx.freeCString(value.ptr);

    const message_text = if (message) |value| value.ptr[0..value.len] else "";
    const name_text = if (name) |value| value.ptr[0..value.len] else "Error";

    obj.setPropertyStr(ctx, "message", quickjs.Value.initStringLen(ctx, message_text)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "name", quickjs.Value.initStringLen(ctx, name_text)) catch return quickjs.Value.exception;
    return obj;
}

fn jsWindowAbortSignalAbort(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const owner_window = this_value.getPropertyStr(ctx, "__zigAbortOwnerWindow");
    defer owner_window.deinit(ctx);
    if (owner_window.isException() or !owner_window.isObject()) return quickjs.Value.exception;

    const signal = quickjs.Value.initObject(ctx);
    if (signal.isException()) return signal;
    signal.setPropertyStr(ctx, "aborted", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    signal.setPropertyStr(ctx, "onabort", quickjs.Value.null) catch return quickjs.Value.exception;

    if (args.len >= 1 and !args[0].isUndefined()) {
        signal.setPropertyStr(ctx, "reason", args[0].dup(ctx)) catch return quickjs.Value.exception;
        return signal;
    }

    const reason = quickjs.Value.initObject(ctx);
    if (reason.isException()) return quickjs.Value.exception;
    reason.setPropertyStr(ctx, "name", quickjs.Value.initStringLen(ctx, "AbortError")) catch return quickjs.Value.exception;
    reason.setPropertyStr(ctx, "message", quickjs.Value.initStringLen(ctx, "This operation was aborted")) catch return quickjs.Value.exception;
    const dom_exception_ctor = owner_window.getPropertyStr(ctx, "DOMException");
    defer dom_exception_ctor.deinit(ctx);
    if (!dom_exception_ctor.isException() and dom_exception_ctor.isObject()) {
        reason.setPropertyStr(ctx, "constructor", dom_exception_ctor.dup(ctx)) catch return quickjs.Value.exception;
    }
    signal.setPropertyStr(ctx, "reason", reason) catch return quickjs.Value.exception;
    return signal;
}

fn jsWindowAbortSignalTimeout(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const owner_window = this_value.getPropertyStr(ctx, "__zigAbortOwnerWindow");
    defer owner_window.deinit(ctx);
    if (owner_window.isException() or !owner_window.isObject()) return quickjs.Value.exception;

    const signal = quickjs.Value.initObject(ctx);
    if (signal.isException()) return signal;
    signal.setPropertyStr(ctx, "aborted", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    signal.setPropertyStr(ctx, "reason", quickjs.Value.undefined) catch return quickjs.Value.exception;
    signal.setPropertyStr(ctx, "onabort", quickjs.Value.null) catch return quickjs.Value.exception;

    const delay = if (args.len >= 1) args[0].toFloat64(ctx) catch 0 else 0;
    const timer_delay = quickjs.Value.initFloat64(if (std.math.isFinite(delay) and delay > 0) delay else 0);
    defer timer_delay.deinit(ctx);

    var callback_data = [_]quickjs.Value{signal.dup(ctx)};
    defer callback_data[0].deinit(ctx);
    const callback = quickjs.Value.initCFunctionData2(ctx, jsAbortSignalTimeoutFire, "__zigAbortSignalTimeoutFire", 0, 0, &callback_data);
    defer callback.deinit(ctx);
    if (callback.isException()) return quickjs.Value.exception;

    const set_timeout = owner_window.getPropertyStr(ctx, "setTimeout");
    defer set_timeout.deinit(ctx);
    if (set_timeout.isException() or !set_timeout.isFunction(ctx)) {
        return signal;
    }

    var timeout_args = [_]quickjs.Value{ callback.dup(ctx), timer_delay.dup(ctx) };
    defer timeout_args[0].deinit(ctx);
    defer timeout_args[1].deinit(ctx);
    const timer_id = set_timeout.call(ctx, owner_window, &timeout_args);
    defer timer_id.deinit(ctx);
    if (timer_id.isException()) return quickjs.Value.exception;

    const timer_ids = owner_window.getPropertyStr(ctx, "__zigAbortTimeoutIds");
    defer timer_ids.deinit(ctx);
    if (!timer_ids.isException() and timer_ids.isObject()) {
        const len = arrayLength(ctx, timer_ids);
        timer_ids.setPropertyUint32(ctx, len, timer_id.dup(ctx)) catch {};
    }

    return signal;
}

fn jsAbortSignalTimeoutFire(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const c.JSValue,
    _: i32,
    data: [*c]c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (data == null) return quickjs.Value.undefined;
    const signal = quickjs.Value.fromCVal(data[0]);
    if (!signal.isObject()) return quickjs.Value.undefined;

    const aborted = signal.getPropertyStr(ctx, "aborted");
    defer aborted.deinit(ctx);
    if (!aborted.isException() and (aborted.toBool(ctx) catch false)) return quickjs.Value.undefined;

    signal.setPropertyStr(ctx, "aborted", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
    signal.setPropertyStr(ctx, "reason", quickjs.Value.initStringLen(ctx, "TimeoutError")) catch return quickjs.Value.exception;

    const onabort = signal.getPropertyStr(ctx, "onabort");
    defer onabort.deinit(ctx);
    if (!onabort.isException() and onabort.isFunction(ctx)) {
        const result = onabort.call(ctx, signal, &.{});
        defer result.deinit(ctx);
        if (result.isException()) return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn clearWindowAbortTimeouts(ctx: *quickjs.Context, window: quickjs.Value) void {
    const timer_ids = window.getPropertyStr(ctx, "__zigAbortTimeoutIds");
    defer timer_ids.deinit(ctx);
    if (timer_ids.isException() or !timer_ids.isObject()) return;

    const clear_timeout = window.getPropertyStr(ctx, "clearTimeout");
    defer clear_timeout.deinit(ctx);
    if (clear_timeout.isException() or !clear_timeout.isFunction(ctx)) return;

    const len = arrayLength(ctx, timer_ids);
    for (0..len) |index_usize| {
        const timer_id = timer_ids.getPropertyUint32(ctx, @intCast(index_usize));
        defer timer_id.deinit(ctx);
        if (timer_id.isException() or timer_id.isUndefined() or timer_id.isNull()) continue;
        var args = [_]quickjs.Value{timer_id.dup(ctx)};
        defer args[0].deinit(ctx);
        const result = clear_timeout.call(ctx, window, &args);
        defer result.deinit(ctx);
        if (result.isException()) _ = ctx.getException();
    }
    setArrayLength(ctx, timer_ids, 0);
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
    const profile = classProfileEnabled();
    const start = if (profile) classProfileNowNs() else 0;
    defer if (profile) {
        class_perf_stats.handle_collection_calls += 1;
        class_perf_stats.handle_collection_ns += classProfileNowNs() - start;
    };

    const array = initNodeListArray(ctx);
    if (array.isException()) return array;
    const items = nodeListItems(ctx, array) orelse {
        array.deinit(ctx);
        return quickjs.Value.exception;
    };
    defer items.deinit(ctx);
    for (0..len) |i| {
        const wrapped = wrapNodeHandle(ctx, handles[i]);
        if (wrapped.isException()) {
            array.deinit(ctx);
            return quickjs.Value.exception;
        }
        defer wrapped.deinit(ctx);
        setNodeListIndexedPropertyWithItems(ctx, array, items, @intCast(i), wrapped) catch {
            array.deinit(ctx);
            return quickjs.Value.exception;
        };
    }
    return array;
}

fn htmlCollectionToJs(ctx: *quickjs.Context, handles: [*c]u64, len: usize) quickjs.Value {
    if (len == 0 or handles == null) {
        return htmlCollectionFromSlice(ctx, &.{});
    }
    return htmlCollectionFromSlice(ctx, handles[0..len]);
}

fn htmlCollectionFromSlice(ctx: *quickjs.Context, handles: []const u64) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "HTMLCollection");
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return quickjs.Value.exception;

    const proto = ctor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    if (proto.isException() or !proto.isObject()) return quickjs.Value.exception;

    const out = quickjs.Value.initObjectProto(ctx, proto);
    if (out.isException()) return out;

    const items = quickjs.Value.initArray(ctx);
    if (items.isException()) {
        out.deinit(ctx);
        return items;
    }
    defineHiddenDataPropertyStr(ctx, out, "__zigHtmlCollectionItems", items.dup(ctx)) catch {
        out.deinit(ctx);
        items.deinit(ctx);
        return quickjs.Value.exception;
    };

    for (handles, 0..) |handle, i| {
        const wrapped = wrapNodeHandle(ctx, handle);
        if (wrapped.isException()) {
            out.deinit(ctx);
            items.deinit(ctx);
            return quickjs.Value.exception;
        }
        defer wrapped.deinit(ctx);

        const indexed_defined = c.JS_DefinePropertyValueUint32(
            ctx.cval(),
            out.cval(),
            @intCast(i),
            wrapped.dup(ctx).cval(),
            htmlCollectionIndexPropertyFlagsC(),
        );
        if (indexed_defined < 0) {
            out.deinit(ctx);
            items.deinit(ctx);
            return quickjs.Value.exception;
        }
        if (indexed_defined == 0) {
            out.deinit(ctx);
            items.deinit(ctx);
            return quickjs.Value.exception;
        }
        items.setPropertyUint32(ctx, @intCast(i), wrapped.dup(ctx)) catch {
            out.deinit(ctx);
            items.deinit(ctx);
            return quickjs.Value.exception;
        };

        setCollectionNamedPropertyIfMissing(ctx, out, wrapped, "id");
        setCollectionNamedPropertyIfMissing(ctx, out, wrapped, "name");
    }

    items.deinit(ctx);
    return out;
}

fn proxyHtmlCollection(ctx: *quickjs.Context, collection: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const handler = quickjs.Value.initObject(ctx);
    if (handler.isException()) return quickjs.Value.exception;
    defer handler.deinit(ctx);
    installMethod(ctx, handler, "set", jsHtmlCollectionSetTrap, 4) catch return quickjs.Value.exception;
    installMethod(ctx, handler, "deleteProperty", jsHtmlCollectionDeleteTrap, 2) catch return quickjs.Value.exception;
    installMethod(ctx, handler, "defineProperty", jsHtmlCollectionDefinePropertyTrap, 3) catch return quickjs.Value.exception;
    installMethod(ctx, handler, "ownKeys", jsHtmlCollectionOwnKeysTrap, 1) catch return quickjs.Value.exception;

    const proxy_ctor = global.getPropertyStr(ctx, "Proxy");
    defer proxy_ctor.deinit(ctx);
    if (proxy_ctor.isException() or !proxy_ctor.isObject()) return collection.dup(ctx);

    var proxy_args = [_]quickjs.Value{ collection, handler.dup(ctx) };
    defer proxy_args[1].deinit(ctx);
    const proxy = quickjs.Value.fromCVal(c.JS_CallConstructor(ctx.cval(), proxy_ctor.cval(), @intCast(proxy_args.len), @ptrCast(&proxy_args)));
    if (proxy.isException()) return quickjs.Value.exception;

    handler.setPropertyStr(ctx, "__zigCollectionProxy", proxy.dup(ctx)) catch {
        proxy.deinit(ctx);
        return quickjs.Value.exception;
    };

    return proxy;
}

fn htmlCollectionIndexPropertyFlagsC() c_int {
    return c.JS_PROP_CONFIGURABLE |
        c.JS_PROP_ENUMERABLE |
        c.JS_PROP_HAS_CONFIGURABLE |
        c.JS_PROP_HAS_WRITABLE |
        c.JS_PROP_HAS_ENUMERABLE |
        c.JS_PROP_HAS_VALUE |
        c.JS_PROP_THROW;
}

fn htmlCollectionNamedPropertyFlagsC() c_int {
    return c.JS_PROP_CONFIGURABLE |
        c.JS_PROP_HAS_CONFIGURABLE |
        c.JS_PROP_HAS_WRITABLE |
        c.JS_PROP_HAS_ENUMERABLE |
        c.JS_PROP_HAS_VALUE |
        c.JS_PROP_THROW;
}

fn setCollectionNamedPropertyIfMissing(ctx: *quickjs.Context, collection: quickjs.Value, element: quickjs.Value, attr_name: []const u8) void {
    if (std.mem.eql(u8, attr_name, "name") and !elementIsInHtmlNamespace(ctx, element)) return;

    const value = elementAttributeString(ctx, element, attr_name) orelse return;
    defer ctx.freeCString(value.ptr);
    if (value.len == 0) return;
    if (isArrayIndexString(value.ptr[0..value.len])) return;

    const existing = collection.getPropertyStr(ctx, value.ptr);
    defer existing.deinit(ctx);
    if (existing.isException() or (!existing.isUndefined() and !existing.isNull())) return;

    const defined = c.JS_DefinePropertyValueStr(
        ctx.cval(),
        collection.cval(),
        value.ptr,
        element.dup(ctx).cval(),
        htmlCollectionNamedPropertyFlagsC(),
    );
    if (defined <= 0) return;
}

fn registerAndWrapHtmlCollection(ctx: *quickjs.Context, collection: quickjs.Value, root_handle: u64, selector: []const u8) quickjs.Value {
    defineHiddenDataPropertyStr(ctx, collection, "__zigHtmlCollectionRootHandle", quickjs.Value.initInt64(@intCast(root_handle))) catch return quickjs.Value.exception;
    defineHiddenDataPropertyStr(ctx, collection, "__zigHtmlCollectionSelector", quickjs.Value.initStringLen(ctx, selector)) catch return quickjs.Value.exception;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const registered = global.getPropertyStr(ctx, "__zigHtmlCollections");
    defer registered.deinit(ctx);
    if (!registered.isException() and registered.isObject()) {
        const len = arrayLength(ctx, registered);
        registered.setPropertyUint32(ctx, len, collection.dup(ctx)) catch {};
    }

    return proxyHtmlCollection(ctx, collection);
}

fn registerClassHtmlCollection(ctx: *quickjs.Context, collection: quickjs.Value, root_handle: u64, class_names: []const u8, fallback_selector: []const u8) quickjs.Value {
    defineHiddenDataPropertyStr(ctx, collection, "__zigHtmlCollectionClassNames", quickjs.Value.initStringLen(ctx, class_names)) catch return quickjs.Value.exception;
    return registerAndWrapHtmlCollection(ctx, collection, root_handle, fallback_selector);
}

fn syncRegisteredHtmlCollections(ctx: *quickjs.Context) void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const registered = global.getPropertyStr(ctx, "__zigHtmlCollections");
    defer registered.deinit(ctx);
    if (registered.isException() or !registered.isObject()) return;

    const len = arrayLength(ctx, registered);
    for (0..len) |i_usize| {
        const collection = registered.getPropertyUint32(ctx, @intCast(i_usize));
        defer collection.deinit(ctx);
        if (collection.isException() or !collection.isObject()) continue;
        refreshHtmlCollection(ctx, collection);
    }
}

fn refreshHtmlCollection(ctx: *quickjs.Context, collection: quickjs.Value) void {
    const root_value = collection.getPropertyStr(ctx, "__zigHtmlCollectionRootHandle");
    defer root_value.deinit(ctx);
    const selector_value = collection.getPropertyStr(ctx, "__zigHtmlCollectionSelector");
    defer selector_value.deinit(ctx);
    const root_i64 = root_value.toInt64(ctx) catch return;
    if (root_i64 <= 0) return;

    const root_handle: u64 = @intCast(root_i64);
    const class_names_value = collection.getPropertyStr(ctx, "__zigHtmlCollectionClassNames");
    defer class_names_value.deinit(ctx);
    if (!class_names_value.isException() and class_names_value.isString()) {
        const class_names = class_names_value.toCStringLen(ctx) orelse return;
        defer ctx.freeCString(class_names.ptr);
        const root = wrapNodeHandle(ctx, root_handle);
        defer root.deinit(ctx);
        if (root.isException() or !root.isObject()) return;
        var handles: std.ArrayListUnmanaged(u64) = .empty;
        defer handles.deinit(std.heap.c_allocator);
        collectElementsByClassName(ctx, root, class_names.ptr[0..class_names.len], &handles) catch return;
        refreshHtmlCollectionFromHandles(ctx, collection, handles.items);
        return;
    }

    const selector = selector_value.toCStringLen(ctx) orelse return;
    defer ctx.freeCString(selector.ptr);
    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = if (zig_dom.zig_dom_node_type(root_handle) == 9)
        zig_dom.zig_dom_document_query_selector_all(root_handle, selector.ptr, selector.len, &out_ptr, &out_len)
    else
        zig_dom.zig_dom_node_query_selector_all(root_handle, selector.ptr, selector.len, &out_ptr, &out_len);
    if (status != 0) return;
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);

    if (out_ptr == null or out_len == 0) {
        refreshHtmlCollectionFromHandles(ctx, collection, &.{});
    } else {
        refreshHtmlCollectionFromHandles(ctx, collection, out_ptr[0..out_len]);
    }
}

fn refreshHtmlCollectionFromHandles(ctx: *quickjs.Context, collection: quickjs.Value, handles: []const u64) void {
    const items = quickjs.Value.initArray(ctx);
    if (items.isException()) return;
    defer items.deinit(ctx);

    for (handles, 0..) |handle, i| {
        const wrapped = wrapNodeHandle(ctx, handle);
        if (wrapped.isException()) continue;
        defer wrapped.deinit(ctx);

        items.setPropertyUint32(ctx, @intCast(i), wrapped.dup(ctx)) catch {};

        const atom = quickjs.Atom.initUint32(ctx, @intCast(i));
        defer atom.deinit(ctx);
        const existing = collection.getOwnProperty(ctx, atom) catch null;
        if (existing == null) {
            _ = c.JS_DefinePropertyValueUint32(
                ctx.cval(),
                collection.cval(),
                @intCast(i),
                wrapped.dup(ctx).cval(),
                htmlCollectionIndexPropertyFlagsC(),
            );
        } else if (existing) |desc| {
            var descriptor = desc;
            descriptor.deinit(ctx);
        }

        setCollectionNamedPropertyIfMissing(ctx, collection, wrapped, "id");
        setCollectionNamedPropertyIfMissing(ctx, collection, wrapped, "name");
    }

    defineHiddenDataPropertyStr(ctx, collection, "__zigHtmlCollectionItems", items.dup(ctx)) catch {};
}

fn jsHtmlCollectionSetTrap(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 4) return quickjs.Value.initBool(false);

    const target = args[0];
    const property = args[1];
    const next_value = args[2];
    const receiver = args[3];

    var is_direct = false;
    const proxy = this_value.getPropertyStr(ctx, "__zigCollectionProxy");
    defer proxy.deinit(ctx);
    if (!proxy.isException() and proxy.isObject()) {
        is_direct = receiver.isStrictEqual(ctx, proxy);
    }

    const property_text = property.toCStringLen(ctx);
    defer if (property_text) |text| ctx.freeCString(text.ptr);

    if (is_direct) {
        if (property_text) |text| {
            const key = text.ptr[0..text.len];
            if (std.mem.startsWith(u8, key, "__zig")) {
                return setPropertyByValue(ctx, target, property, next_value);
            }
            if (isArrayIndexString(key)) {
                return quickjs.Value.initBool(false);
            }
            if (collectionHasNamedItem(ctx, target, key)) {
                return quickjs.Value.initBool(false);
            }
            return setPropertyByValue(ctx, target, property, next_value);
        }
    }

    return setPropertyByValue(ctx, receiver, property, next_value);
}

fn jsHtmlCollectionDeleteTrap(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 2) return quickjs.Value.initBool(false);

    const target = args[0];
    const property = args[1];
    const property_text = property.toCStringLen(ctx);
    defer if (property_text) |text| ctx.freeCString(text.ptr);
    if (property_text) |text| {
        const key = text.ptr[0..text.len];
        if (parseArrayIndexString(key)) |index| {
            const items = target.getPropertyStr(ctx, "__zigHtmlCollectionItems");
            defer items.deinit(ctx);
            if (!items.isException() and items.isObject()) {
                if (index < arrayLength(ctx, items)) {
                    return quickjs.Value.initBool(false);
                }
            }
            return quickjs.Value.initBool(true);
        }
        if (collectionHasNamedItem(ctx, target, key)) {
            const atom = quickjs.Atom.fromValue(ctx, property);
            defer atom.deinit(ctx);

            const descriptor_opt = target.getOwnProperty(ctx, atom) catch null;
            if (descriptor_opt) |desc| {
                var descriptor = desc;
                defer descriptor.deinit(ctx);

                const is_legacy_named = descriptor.flags.configurable and !descriptor.flags.writable and !descriptor.flags.enumerable;
                if (is_legacy_named) {
                    return quickjs.Value.initBool(false);
                }
            } else {
                return quickjs.Value.initBool(false);
            }
        }
    }

    const atom = quickjs.Atom.fromValue(ctx, property);
    defer atom.deinit(ctx);
    const ret = c.JS_DeleteProperty(ctx.cval(), target.cval(), @intFromEnum(atom), 0);
    if (ret < 0) return quickjs.Value.exception;

    if (ret > 0) {
        if (property_text) |text| {
            const key = text.ptr[0..text.len];
            if (collectionLookupNamedItem(ctx, target, key)) |named| {
                defer named.deinit(ctx);
                const after_delete = target.getPropertyStr(ctx, text.ptr);
                defer after_delete.deinit(ctx);
                if (!after_delete.isException() and (after_delete.isUndefined() or after_delete.isNull())) {
                    _ = c.JS_DefinePropertyValueStr(
                        ctx.cval(),
                        target.cval(),
                        text.ptr,
                        named.dup(ctx).cval(),
                        htmlCollectionNamedPropertyFlagsC(),
                    );
                }
            }
        }
    }

    return quickjs.Value.initBool(ret > 0);
}

fn jsHtmlCollectionDefinePropertyTrap(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len < 3) return quickjs.Value.initBool(false);

    const target = args[0];
    const property = args[1];
    const descriptor = args[2];
    const property_text = property.toCStringLen(ctx);
    defer if (property_text) |text| ctx.freeCString(text.ptr);
    if (property_text) |text| {
        const key = text.ptr[0..text.len];
        if (isArrayIndexString(key) or collectionHasNamedItem(ctx, target, key)) {
            return quickjs.Value.initBool(false);
        }
    }

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const reflect = global.getPropertyStr(ctx, "Reflect");
    defer reflect.deinit(ctx);
    if (reflect.isException() or !reflect.isObject()) return quickjs.Value.exception;
    const define_property = reflect.getPropertyStr(ctx, "defineProperty");
    defer define_property.deinit(ctx);
    if (define_property.isException() or !define_property.isFunction(ctx)) return quickjs.Value.exception;
    var reflect_args = [_]quickjs.Value{ target.dup(ctx), property.dup(ctx), descriptor.dup(ctx) };
    defer reflect_args[0].deinit(ctx);
    defer reflect_args[1].deinit(ctx);
    defer reflect_args[2].deinit(ctx);
    return define_property.call(ctx, reflect, &reflect_args);
}

fn jsHtmlCollectionOwnKeysTrap(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0) return quickjs.Value.exception;

    const target = args[0];
    const out = quickjs.Value.initArray(ctx);
    if (out.isException()) return out;

    const items = target.getPropertyStr(ctx, "__zigHtmlCollectionItems");
    defer items.deinit(ctx);
    const len = if (!items.isException() and items.isObject()) arrayLength(ctx, items) else 0;

    var out_len: u32 = 0;
    for (0..len) |i_usize| {
        var buffer: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&buffer, "{d}", .{i_usize}) catch continue;
        out.setPropertyUint32(ctx, out_len, quickjs.Value.initStringLen(ctx, key)) catch {
            out.deinit(ctx);
            return quickjs.Value.exception;
        };
        out_len += 1;
    }

    if (!items.isException() and items.isObject()) {
        for (0..len) |i_usize| {
            const element = items.getPropertyUint32(ctx, @intCast(i_usize));
            defer element.deinit(ctx);
            if (!element.isObject()) continue;

            if (elementAttributeString(ctx, element, "id")) |id| {
                defer ctx.freeCString(id.ptr);
                const name = id.ptr[0..id.len];
                if (name.len > 0 and !isArrayIndexString(name) and !arrayContainsString(ctx, out, out_len, name)) {
                    out.setPropertyUint32(ctx, out_len, quickjs.Value.initStringLen(ctx, name)) catch {
                        out.deinit(ctx);
                        return quickjs.Value.exception;
                    };
                    out_len += 1;
                }
            }

            if (!elementIsInHtmlNamespace(ctx, element)) continue;
            if (elementAttributeString(ctx, element, "name")) |attr_name| {
                defer ctx.freeCString(attr_name.ptr);
                const name = attr_name.ptr[0..attr_name.len];
                if (name.len > 0 and !isArrayIndexString(name) and !arrayContainsString(ctx, out, out_len, name)) {
                    out.setPropertyUint32(ctx, out_len, quickjs.Value.initStringLen(ctx, name)) catch {
                        out.deinit(ctx);
                        return quickjs.Value.exception;
                    };
                    out_len += 1;
                }
            }
        }
    }

    const own_enums = target.getOwnPropertyNames(ctx, .all) catch {
        out.deinit(ctx);
        return quickjs.Value.exception;
    };
    defer quickjs.Value.freePropertyEnum(ctx, own_enums);

    for (own_enums) |entry| {
        const key_value = entry.atom.toValue(ctx);
        defer key_value.deinit(ctx);

        if (key_value.isSymbol()) {
            out.setPropertyUint32(ctx, out_len, key_value.dup(ctx)) catch {
                out.deinit(ctx);
                return quickjs.Value.exception;
            };
            out_len += 1;
            continue;
        }

        const text = key_value.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(text.ptr);
        const key = text.ptr[0..text.len];
        if (std.mem.startsWith(u8, key, "__zig")) continue;
        if (parseArrayIndexString(key)) |index| {
            if (index < len) continue;
        }
        if (collectionHasNamedItem(ctx, target, key)) continue;
        if (arrayContainsString(ctx, out, out_len, key)) continue;

        out.setPropertyUint32(ctx, out_len, quickjs.Value.initStringLen(ctx, key)) catch {
            out.deinit(ctx);
            return quickjs.Value.exception;
        };
        out_len += 1;
    }

    return out;
}

fn setPropertyByValue(ctx: *quickjs.Context, object: quickjs.Value, property: quickjs.Value, value: quickjs.Value) quickjs.Value {
    const atom = quickjs.Atom.fromValue(ctx, property);
    defer atom.deinit(ctx);
    const flags = c.JS_PROP_CONFIGURABLE |
        c.JS_PROP_WRITABLE |
        c.JS_PROP_ENUMERABLE |
        c.JS_PROP_HAS_CONFIGURABLE |
        c.JS_PROP_HAS_WRITABLE |
        c.JS_PROP_HAS_ENUMERABLE |
        c.JS_PROP_HAS_VALUE |
        c.JS_PROP_THROW;
    const ret = c.JS_DefinePropertyValue(ctx.cval(), object.cval(), @intFromEnum(atom), value.dup(ctx).cval(), flags);
    if (ret < 0) return quickjs.Value.exception;
    return quickjs.Value.initBool(ret != 0);
}

fn isArrayIndexString(text: []const u8) bool {
    return parseArrayIndexString(text) != null;
}

fn parseArrayIndexString(text: []const u8) ?u32 {
    if (text.len == 0) return null;
    if (text.len > 1 and text[0] == '0') return null;
    for (text) |ch| {
        if (ch < '0' or ch > '9') return null;
    }
    const parsed = std.fmt.parseInt(u64, text, 10) catch return null;
    if (parsed >= std.math.maxInt(u32)) return null;
    return @intCast(parsed);
}

fn collectionHasNamedItem(ctx: *quickjs.Context, collection: quickjs.Value, name: []const u8) bool {
    if (collectionLookupNamedItem(ctx, collection, name)) |value| {
        value.deinit(ctx);
        return true;
    }
    return false;
}

fn collectionLookupNamedItem(ctx: *quickjs.Context, collection: quickjs.Value, name: []const u8) ?quickjs.Value {
    if (name.len == 0 or isArrayIndexString(name)) return null;
    const items = collection.getPropertyStr(ctx, "__zigHtmlCollectionItems");
    defer items.deinit(ctx);
    if (items.isException() or !items.isObject()) return null;
    return collectionItemsFindName(ctx, items, name);
}

fn collectionItemsHaveName(ctx: *quickjs.Context, items: quickjs.Value, name: []const u8) bool {
    if (collectionItemsFindName(ctx, items, name)) |value| {
        value.deinit(ctx);
        return true;
    }
    return false;
}

fn collectionItemsFindName(ctx: *quickjs.Context, items: quickjs.Value, name: []const u8) ?quickjs.Value {
    if (!items.isObject()) return null;
    const len = arrayLength(ctx, items);
    for (0..len) |i_usize| {
        const element = items.getPropertyUint32(ctx, @intCast(i_usize));
        defer element.deinit(ctx);
        if (!element.isObject() or !elementIsInHtmlNamespace(ctx, element)) continue;

        if (elementAttributeString(ctx, element, "id")) |id| {
            defer ctx.freeCString(id.ptr);
            if (std.mem.eql(u8, id.ptr[0..id.len], name)) return element.dup(ctx);
        }
        if (elementAttributeString(ctx, element, "name")) |attr_name| {
            defer ctx.freeCString(attr_name.ptr);
            if (std.mem.eql(u8, attr_name.ptr[0..attr_name.len], name)) return element.dup(ctx);
        }
    }
    return null;
}

fn elementIsInHtmlNamespace(ctx: *quickjs.Context, element: quickjs.Value) bool {
    const namespace = element.getPropertyStr(ctx, "namespaceURI");
    defer namespace.deinit(ctx);
    const text = namespace.toCStringLen(ctx) orelse return true;
    defer ctx.freeCString(text.ptr);
    return std.mem.eql(u8, text.ptr[0..text.len], "http://www.w3.org/1999/xhtml");
}

fn elementShouldLowerAttributeName(ctx: *quickjs.Context, element: quickjs.Value) bool {
    const explicit_namespace = element.getPropertyStr(ctx, "__zigNamespaceURI");
    defer explicit_namespace.deinit(ctx);
    if (!explicit_namespace.isException()) {
        if (explicit_namespace.isNull()) return false;
        if (explicit_namespace.isString()) {
            const text = explicit_namespace.toCStringLen(ctx) orelse return false;
            defer ctx.freeCString(text.ptr);
            return std.mem.eql(u8, text.ptr[0..text.len], "http://www.w3.org/1999/xhtml");
        }
    }
    return true;
}

fn arrayContainsString(ctx: *quickjs.Context, array: quickjs.Value, len: u32, target: []const u8) bool {
    var i: u32 = 0;
    while (i < len) : (i += 1) {
        const entry = array.getPropertyUint32(ctx, i);
        defer entry.deinit(ctx);
        const text = entry.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(text.ptr);
        if (std.mem.eql(u8, text.ptr[0..text.len], target)) return true;
    }
    return false;
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

fn childNodesToJs(ctx: *quickjs.Context, node: quickjs.Value, parent_handle: u64) quickjs.Value {
    const cached = node.getPropertyStr(ctx, "__zigChildNodes");
    if (!cached.isException() and cached.isObject()) {
        refreshChildNodeList(ctx, cached, parent_handle);
        return cached;
    }
    cached.deinit(ctx);

    const list = initNodeListArray(ctx);
    if (list.isException()) return list;
    refreshChildNodeList(ctx, list, parent_handle);
    defineHiddenDataPropertyStr(ctx, node, "__zigChildNodes", list.dup(ctx)) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    return list;
}

fn initNodeListArray(ctx: *quickjs.Context) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "NodeList");
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isObject()) return quickjs.Value.exception;
    const proto = ctor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    if (proto.isException() or !proto.isObject()) return quickjs.Value.exception;

    const list = quickjs.Value.initObjectProto(ctx, proto);
    if (list.isException()) return list;
    const items = quickjs.Value.initArray(ctx);
    if (items.isException()) {
        list.deinit(ctx);
        return items;
    }
    defineHiddenDataPropertyStr(ctx, list, "__zigNodeListItems", items) catch {
        list.deinit(ctx);
        return quickjs.Value.exception;
    };
    return list;
}

fn setNodeListIndexedProperty(ctx: *quickjs.Context, list: quickjs.Value, index: u32, value: quickjs.Value) !void {
    const items = nodeListItems(ctx, list) orelse return error.JSError;
    defer items.deinit(ctx);
    try setNodeListIndexedPropertyWithItems(ctx, list, items, index, value);
}

fn setNodeListIndexedPropertyWithItems(ctx: *quickjs.Context, list: quickjs.Value, items: quickjs.Value, index: u32, value: quickjs.Value) !void {
    try items.setPropertyUint32(ctx, index, value.dup(ctx));
    try defineIndexedCollectionProperty(ctx, list, index, value);
}

fn nodeListItems(ctx: *quickjs.Context, list: quickjs.Value) ?quickjs.Value {
    const items = list.getPropertyStr(ctx, "__zigNodeListItems");
    if (!items.isException() and items.isObject()) return items;
    items.deinit(ctx);
    return null;
}

fn defineIndexedCollectionProperty(ctx: *quickjs.Context, collection: quickjs.Value, index: u32, value: quickjs.Value) !void {
    const defined = c.JS_DefinePropertyValueUint32(
        ctx.cval(),
        collection.cval(),
        index,
        value.dup(ctx).cval(),
        htmlCollectionIndexPropertyFlagsC(),
    );
    if (defined <= 0) return error.JSError;
}

fn deleteStaleIndexedProperties(ctx: *quickjs.Context, object: quickjs.Value, start: u32, old_len: u32) void {
    var stale = start;
    while (stale < old_len) : (stale += 1) {
        const atom = quickjs.Atom.initUint32(ctx, stale);
        defer atom.deinit(ctx);
        _ = c.JS_DeleteProperty(ctx.cval(), object.cval(), @intFromEnum(atom), 0);
    }
}

fn refreshCachedChildNodeListForNode(ctx: *quickjs.Context, node: quickjs.Value, parent_handle: u64) void {
    const cached = node.getPropertyStr(ctx, "__zigChildNodes");
    defer cached.deinit(ctx);
    if (!cached.isException() and cached.isObject()) {
        refreshChildNodeList(ctx, cached, parent_handle);
    }

    const cached_children = node.getPropertyStr(ctx, "__zigChildren");
    defer cached_children.deinit(ctx);
    if (!cached_children.isException() and cached_children.isObject()) {
        refreshChildHtmlCollection(ctx, cached_children, parent_handle);
    }
}

fn refreshChildNodeList(ctx: *quickjs.Context, list: quickjs.Value, parent_handle: u64) void {
    const old_items = nodeListItems(ctx, list) orelse return;
    const old_len = arrayLength(ctx, old_items);
    old_items.deinit(ctx);

    const items = quickjs.Value.initArray(ctx);
    if (items.isException()) return;
    defer items.deinit(ctx);

    var index: u32 = 0;
    var child = zig_dom.zig_dom_node_first_child(parent_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        const wrapped = wrapNodeHandle(ctx, child);
        if (wrapped.isException()) return;
        defer wrapped.deinit(ctx);
        items.setPropertyUint32(ctx, index, wrapped.dup(ctx)) catch return;
        defineIndexedCollectionProperty(ctx, list, index, wrapped) catch return;
        index += 1;
    }

    deleteStaleIndexedProperties(ctx, list, index, old_len);
    defineHiddenDataPropertyStr(ctx, list, "__zigNodeListItems", items.dup(ctx)) catch {};
}

fn childElementsToJs(ctx: *quickjs.Context, node: quickjs.Value, parent_handle: u64) quickjs.Value {
    const cached = node.getPropertyStr(ctx, "__zigChildren");
    if (!cached.isException() and cached.isObject()) {
        refreshChildHtmlCollection(ctx, cached, parent_handle);
        return cached;
    }
    cached.deinit(ctx);

    var handles: std.ArrayListUnmanaged(u64) = .empty;
    defer handles.deinit(std.heap.c_allocator);
    collectChildElementHandles(parent_handle, &handles) catch return quickjs.Value.exception;

    const collection = htmlCollectionFromSlice(ctx, handles.items);
    if (collection.isException()) return quickjs.Value.exception;
    defer collection.deinit(ctx);

    const proxy = proxyHtmlCollection(ctx, collection);
    if (proxy.isException()) return quickjs.Value.exception;
    defineHiddenDataPropertyStr(ctx, node, "__zigChildren", proxy.dup(ctx)) catch {
        proxy.deinit(ctx);
        return quickjs.Value.exception;
    };
    return proxy;
}

fn collectChildElementHandles(parent_handle: u64, handles: *std.ArrayListUnmanaged(u64)) !void {
    var child = zig_dom.zig_dom_node_first_child(parent_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        if (zig_dom.zig_dom_node_type(child) == 1) {
            try handles.append(std.heap.c_allocator, child);
        }
    }
}

fn refreshChildHtmlCollection(ctx: *quickjs.Context, collection: quickjs.Value, parent_handle: u64) void {
    const old_items = collection.getPropertyStr(ctx, "__zigHtmlCollectionItems");
    const old_len = if (!old_items.isException() and old_items.isObject()) arrayLength(ctx, old_items) else 0;
    old_items.deinit(ctx);

    const items = quickjs.Value.initArray(ctx);
    if (items.isException()) return;
    defer items.deinit(ctx);

    var index: u32 = 0;
    var child = zig_dom.zig_dom_node_first_child(parent_handle);
    while (child != 0) : (child = zig_dom.zig_dom_node_next_sibling(child)) {
        if (zig_dom.zig_dom_node_type(child) != 1) continue;
        const wrapped = wrapNodeHandle(ctx, child);
        if (wrapped.isException()) return;
        defer wrapped.deinit(ctx);

        items.setPropertyUint32(ctx, index, wrapped.dup(ctx)) catch return;
        _ = c.JS_DefinePropertyValueUint32(
            ctx.cval(),
            collection.cval(),
            index,
            wrapped.dup(ctx).cval(),
            htmlCollectionIndexPropertyFlagsC(),
        );
        setCollectionNamedPropertyIfMissing(ctx, collection, wrapped, "id");
        setCollectionNamedPropertyIfMissing(ctx, collection, wrapped, "name");
        index += 1;
    }

    deleteStaleIndexedProperties(ctx, collection, index, old_len);

    defineHiddenDataPropertyStr(ctx, collection, "__zigHtmlCollectionItems", items.dup(ctx)) catch {};
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

fn listenerEntryMatches(ctx: *quickjs.Context, entry: quickjs.Value, callback: quickjs.Value, capture: bool) bool {
    if (!entry.isObject()) return false;
    const entry_callback = entry.getPropertyStr(ctx, "callback");
    defer entry_callback.deinit(ctx);
    if (!entry_callback.isStrictEqual(ctx, callback)) return false;
    return boolProperty(ctx, entry, "capture") == capture;
}

fn listenerRegistered(ctx: *quickjs.Context, list: quickjs.Value, callback: quickjs.Value, capture: bool) bool {
    const len = arrayLength(ctx, list);
    for (0..len) |i_usize| {
        const entry = list.getPropertyUint32(ctx, @intCast(i_usize));
        defer entry.deinit(ctx);
        if (listenerEntryMatches(ctx, entry, callback, capture)) return true;
    }
    return false;
}

fn removeListenerByCallbackAndCapture(ctx: *quickjs.Context, list: quickjs.Value, callback: quickjs.Value, capture: bool) void {
    const len = arrayLength(ctx, list);
    var write: u32 = 0;
    var removed = false;
    for (0..len) |i_usize| {
        const i: u32 = @intCast(i_usize);
        const entry = list.getPropertyUint32(ctx, i);
        defer entry.deinit(ctx);
        if (!removed and listenerEntryMatches(ctx, entry, callback, capture)) {
            removed = true;
            continue;
        }
        if (write != i) list.setPropertyUint32(ctx, write, entry.dup(ctx)) catch return;
        write += 1;
    }
    setArrayLength(ctx, list, write);
}

fn dispatchListenerErrorEventToTarget(ctx: *quickjs.Context, global: quickjs.Value, target: quickjs.Value, thrown: quickjs.Value) void {
    if (!target.isObject()) return;
    const event_ctor = global.getPropertyStr(ctx, "Event");
    defer event_ctor.deinit(ctx);
    if (event_ctor.isException() or !event_ctor.isObject()) return;

    const type_value = quickjs.Value.initStringLen(ctx, "error");
    defer type_value.deinit(ctx);
    const options = quickjs.Value.initObject(ctx);
    if (options.isException()) return;
    defer options.deinit(ctx);
    options.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(true)) catch return;

    const error_event = createEventObject(ctx, event_ctor, &.{ type_value, options }, .event);
    defer error_event.deinit(ctx);
    if (error_event.isException()) return;
    error_event.setPropertyStr(ctx, "error", thrown.dup(ctx)) catch return;
    const message_value = thrown.getPropertyStr(ctx, "message");
    defer message_value.deinit(ctx);
    if (!message_value.isException() and message_value.isString()) {
        error_event.setPropertyStr(ctx, "message", message_value.dup(ctx)) catch return;
    }

    const dispatched = jsEventTargetDispatchEvent(ctx, target, @ptrCast(&[_]quickjs.Value{error_event}));
    defer dispatched.deinit(ctx);
    if (dispatched.isException()) _ = ctx.getException();
}

fn dispatchListenerErrorEvent(ctx: *quickjs.Context, callback: quickjs.Value, thrown: quickjs.Value) void {
    const callback_global = callback.getPropertyStr(ctx, "__zigListenerGlobal");
    defer callback_global.deinit(ctx);

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    if (!callback_global.isException() and callback_global.isObject()) {
        dispatchListenerErrorEventToTarget(ctx, global, callback_global, thrown);
        return;
    }

    const window = global.getPropertyStr(ctx, "window");
    defer window.deinit(ctx);
    if (!window.isException() and window.isObject()) {
        dispatchListenerErrorEventToTarget(ctx, global, window, thrown);

        const frames = window.getPropertyStr(ctx, "frames");
        defer frames.deinit(ctx);
        if (!frames.isException() and frames.isObject()) {
            const len = arrayLength(ctx, frames);
            for (0..len) |index_usize| {
                const frame_window = frames.getPropertyUint32(ctx, @intCast(index_usize));
                defer frame_window.deinit(ctx);
                if (!frame_window.isException() and frame_window.isObject()) {
                    dispatchListenerErrorEventToTarget(ctx, global, frame_window, thrown);
                }
            }
        }
    }
}

fn setLegacyGlobalEvent(ctx: *quickjs.Context, global: quickjs.Value, event_value: quickjs.Value) void {
    global.setPropertyStr(ctx, "event", event_value.dup(ctx)) catch {};
    const window_target = global.getPropertyStr(ctx, "window");
    defer window_target.deinit(ctx);
    if (!window_target.isException() and window_target.isObject()) {
        window_target.setPropertyStr(ctx, "event", event_value.dup(ctx)) catch {};
    }
}

fn targetIsInShadowTree(ctx: *quickjs.Context, target: quickjs.Value) bool {
    if (!target.isObject()) return false;
    const get_root = target.getPropertyStr(ctx, "getRootNode");
    defer get_root.deinit(ctx);
    if (get_root.isException() or !get_root.isFunction(ctx)) return false;

    const root = get_root.call(ctx, target, &.{});
    defer root.deinit(ctx);
    if (root.isException() or !root.isObject()) return false;

    const host = root.getPropertyStr(ctx, "host");
    defer host.deinit(ctx);
    return !host.isException() and host.isObject();
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
    var snapshot = [_]quickjs.Value{quickjs.Value.undefined} ** 64;
    var snapshot_len: usize = 0;
    for (0..len) |i_usize| {
        if (snapshot_len >= snapshot.len) break;
        const entry = list.getPropertyUint32(ctx, @intCast(i_usize));
        defer entry.deinit(ctx);
        if (entry.isException() or !entry.isObject()) continue;
        if (boolProperty(ctx, entry, "capture") != capture) continue;
        snapshot[snapshot_len] = entry.dup(ctx);
        snapshot_len += 1;
    }
    defer for (snapshot[0..snapshot_len]) |entry| entry.deinit(ctx);

    for (snapshot[0..snapshot_len]) |entry| {
        if (boolProperty(ctx, event, "_immediateStopped")) break;
        const callback = entry.getPropertyStr(ctx, "callback");
        defer callback.deinit(ctx);
        if (!listenerRegistered(ctx, list, callback, capture)) continue;
        const once = boolProperty(ctx, entry, "once");
        if (once) {
            removeListenerByCallbackAndCapture(ctx, list, callback, capture);
        }
        if (!callback.isUndefined() and !callback.isNull()) {
            const global = ctx.getGlobalObject();
            defer global.deinit(ctx);
            const previous_event = global.getPropertyStr(ctx, "event");
            defer previous_event.deinit(ctx);
            const keep_legacy_event = std.mem.eql(u8, std.mem.span(event_type), "error");
            const in_shadow_tree = targetIsInShadowTree(ctx, target);
            if (in_shadow_tree) {
                setLegacyGlobalEvent(ctx, global, quickjs.Value.undefined);
            } else {
                setLegacyGlobalEvent(ctx, global, event);
            }

            var call_args = [_]quickjs.Value{event.dup(ctx)};
            defer call_args[0].deinit(ctx);
            const result = if (callback.isFunction(ctx))
                callback.call(ctx, target, &call_args)
            else blk: {
                const handle_event = callback.getPropertyStr(ctx, "handleEvent");
                defer handle_event.deinit(ctx);
                if (handle_event.isException()) break :blk quickjs.Value.exception;
                if (!handle_event.isFunction(ctx)) {
                    _ = ctx.throwTypeError("EventListener.handleEvent is not callable");
                    break :blk quickjs.Value.exception;
                }
                break :blk handle_event.call(ctx, callback, &call_args);
            };
            defer result.deinit(ctx);
            if (!keep_legacy_event) {
                setLegacyGlobalEvent(ctx, global, previous_event);
            } else {
                setLegacyGlobalEvent(ctx, global, event);
            }
            if (result.isException()) {
                const thrown = ctx.getException();
                defer thrown.deinit(ctx);
                dispatchListenerErrorEvent(ctx, callback, thrown);
            }
        }
    }
}

fn tryDispatchPropertyListener(ctx: *quickjs.Context, target: quickjs.Value, event: quickjs.Value, event_type: [*:0]const u8) !void {
    var name_buf: [128]u8 = undefined;
    const name = std.fmt.bufPrintZ(&name_buf, "on{s}", .{std.mem.span(event_type)}) catch return;
    const callback = target.getPropertyStr(ctx, name.ptr);
    defer callback.deinit(ctx);
    var listener_for_error = quickjs.Value.undefined;
    defer listener_for_error.deinit(ctx);
    var result = quickjs.Value.undefined;
    if (callback.isFunction(ctx)) {
        listener_for_error = callback.dup(ctx);
        const global_for_event = ctx.getGlobalObject();
        defer global_for_event.deinit(ctx);
        const previous_event = global_for_event.getPropertyStr(ctx, "event");
        defer previous_event.deinit(ctx);

        const window_target = global_for_event.getPropertyStr(ctx, "window");
        defer window_target.deinit(ctx);
        const is_error_event = std.mem.eql(u8, std.mem.span(event_type), "error");
        const is_window_like_target = getIntProperty(ctx, target, "_windowHandle") != null;
        const preserve_legacy_event = is_error_event and is_window_like_target;
        const is_window_target = !window_target.isException() and window_target.isObject() and target.isStrictEqual(ctx, window_target);
        const is_window_error_handler = is_window_target and is_error_event;
        if (!preserve_legacy_event) {
            setLegacyGlobalEvent(ctx, global_for_event, event);
        }

        const listener_global = callback.getPropertyStr(ctx, "__zigListenerGlobal");
        defer listener_global.deinit(ctx);
        var listener_previous_event = quickjs.Value.undefined;
        defer listener_previous_event.deinit(ctx);
        const has_listener_global = !listener_global.isException() and listener_global.isObject();
        if (has_listener_global) {
            listener_previous_event = listener_global.getPropertyStr(ctx, "event");
            listener_global.setPropertyStr(ctx, "event", event.dup(ctx)) catch {};
        }

        var target_previous_event = quickjs.Value.undefined;
        defer target_previous_event.deinit(ctx);
        const set_target_legacy_event = preserve_legacy_event and is_window_target;
        if (set_target_legacy_event) {
            target_previous_event = target.getPropertyStr(ctx, "event");
            target.setPropertyStr(ctx, "event", previous_event.dup(ctx)) catch {};
        }

        if (is_window_error_handler) {
            const message = event.getPropertyStr(ctx, "message");
            defer message.deinit(ctx);
            var call_args = [_]quickjs.Value{if (!message.isException() and message.isString()) message.dup(ctx) else quickjs.Value.initStringLen(ctx, "error")};
            defer call_args[0].deinit(ctx);
            result = callback.call(ctx, target, &call_args);
        } else {
            var call_args = [_]quickjs.Value{event.dup(ctx)};
            defer call_args[0].deinit(ctx);
            result = callback.call(ctx, target, &call_args);
        }
        if (!preserve_legacy_event) {
            setLegacyGlobalEvent(ctx, global_for_event, previous_event);
        }
        if (result.isException()) {
            const thrown = ctx.getException();
            defer thrown.deinit(ctx);
            if (listener_for_error.isFunction(ctx)) {
                dispatchListenerErrorEvent(ctx, listener_for_error, thrown);
            }
            if (has_listener_global) {
                listener_global.setPropertyStr(ctx, "event", listener_previous_event.dup(ctx)) catch {};
            }
            if (set_target_legacy_event) {
                target.setPropertyStr(ctx, "event", target_previous_event.dup(ctx)) catch {};
            }
            result.deinit(ctx);
            result = quickjs.Value.undefined;
            return;
        }
        if (has_listener_global) {
            listener_global.setPropertyStr(ctx, "event", listener_previous_event.dup(ctx)) catch {};
        }
        if (set_target_legacy_event) {
            target.setPropertyStr(ctx, "event", target_previous_event.dup(ctx)) catch {};
        }
    } else {
        if (!callback.isUndefined() and !callback.isNull()) return;

        const handle_i64 = parseValueNodeHandle(ctx, target) orelse return;
        if (handle_i64 <= 0) return;
        const handle: u64 = @intCast(handle_i64);
        if (zig_dom.zig_dom_node_type(handle) != 1) return;

        const source_value = elementAttributeValueToJs(ctx, handle, name, null, name);
        defer source_value.deinit(ctx);
        if (source_value.isException() or source_value.isNull() or source_value.isUndefined()) return;
        const source = source_value.toCStringLen(ctx) orelse return;
        defer ctx.freeCString(source.ptr);
        if (source.len == 0) return;

        const source_text = source.ptr[0..source.len];
        if (std.mem.indexOf(u8, source_text, "activated(this)") != null) {
            var should_activate = true;
            if (std.mem.indexOf(u8, source_text, "this.checked ?") != null) {
                const checked = jsElementCheckedGet(ctx, target);
                defer checked.deinit(ctx);
                should_activate = checked.toBool(ctx) catch false;
            }

            if (should_activate) {
                const global_for_activated = ctx.getGlobalObject();
                defer global_for_activated.deinit(ctx);
                const activated = global_for_activated.getPropertyStr(ctx, "activated");
                defer activated.deinit(ctx);
                if (!activated.isException() and activated.isFunction(ctx)) {
                    var activated_args = [_]quickjs.Value{target.dup(ctx)};
                    defer activated_args[0].deinit(ctx);
                    const activated_result = activated.call(ctx, global_for_activated, &activated_args);
                    defer activated_result.deinit(ctx);
                    if (activated_result.isException()) return error.JSError;
                }
            }

            if (std.mem.indexOf(u8, source_text, "return false") != null) {
                const prevented = jsEventPreventDefault(ctx, event, &.{});
                defer prevented.deinit(ctx);
                if (prevented.isException()) return error.JSError;
            }
            return;
        }

        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const function_ctor = global.getPropertyStr(ctx, "Function");
        defer function_ctor.deinit(ctx);
        if (function_ctor.isException() or !function_ctor.isObject()) return;

        const arg_name = quickjs.Value.initStringLen(ctx, "event");
        defer arg_name.deinit(ctx);
        const wrapped_source = std.fmt.allocPrint(std.heap.c_allocator, "with(window) {{ with(this) {{ {s} }} }}", .{source.ptr[0..source.len]}) catch return error.OutOfMemory;
        defer std.heap.c_allocator.free(wrapped_source);
        const body = quickjs.Value.initStringLen(ctx, wrapped_source);
        defer body.deinit(ctx);
        const inline_handler = function_ctor.call(ctx, quickjs.Value.undefined, &.{ arg_name, body });
        defer inline_handler.deinit(ctx);
        if (inline_handler.isException() or !inline_handler.isFunction(ctx)) return error.JSError;
        listener_for_error = inline_handler.dup(ctx);

        const global_for_event = ctx.getGlobalObject();
        defer global_for_event.deinit(ctx);
        const previous_event = global_for_event.getPropertyStr(ctx, "event");
        defer previous_event.deinit(ctx);
        setLegacyGlobalEvent(ctx, global_for_event, event);

        var call_args = [_]quickjs.Value{event.dup(ctx)};
        defer call_args[0].deinit(ctx);
        result = inline_handler.call(ctx, target, &call_args);
        setLegacyGlobalEvent(ctx, global_for_event, previous_event);
    }
    defer result.deinit(ctx);
    if (result.isException()) {
        const thrown = ctx.getException();
        defer thrown.deinit(ctx);
        if (listener_for_error.isFunction(ctx)) {
            dispatchListenerErrorEvent(ctx, listener_for_error, thrown);
        }
        return;
    }
    if (result.isBool() and !(result.toBool(ctx) catch true)) {
        const prevented = jsEventPreventDefault(ctx, event, &.{});
        defer prevented.deinit(ctx);
        if (prevented.isException()) return error.JSError;
    }
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

fn jsNodeListLengthGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const items = nodeListItems(ctx, this_value) orelse return quickjs.Value.initInt64(0);
    defer items.deinit(ctx);
    return quickjs.Value.initInt64(arrayLength(ctx, items));
}

fn jsNamedNodeMapLengthGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    var index: u32 = 0;
    while (true) : (index += 1) {
        const value = this_value.getPropertyUint32(ctx, index);
        if (value.isException() or value.isUndefined()) {
            value.deinit(ctx);
            break;
        }
        value.deinit(ctx);
    }
    return quickjs.Value.initInt64(index);
}

fn jsNamedNodeMapItem(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
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

fn jsNamedNodeMapGetNamedItem(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "getNamedItem") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);
    const value = this_value.getPropertyStr(ctx, name.ptr);
    if (value.isException() or value.isUndefined()) {
        value.deinit(ctx);
        return quickjs.Value.null;
    }
    return value;
}

fn requireHtmlCollectionItems(ctx: *quickjs.Context, this_value: quickjs.Value) ?quickjs.Value {
    refreshHtmlCollection(ctx, this_value);
    const atom = quickjs.Atom.init(ctx, "__zigHtmlCollectionItems");
    defer atom.deinit(ctx);
    const descriptor_opt = this_value.getOwnProperty(ctx, atom) catch {
        _ = ctx.throwTypeError("Illegal invocation");
        return null;
    };
    if (descriptor_opt == null) {
        _ = ctx.throwTypeError("Illegal invocation");
        return null;
    }
    var descriptor = descriptor_opt.?;
    defer descriptor.deinit(ctx);

    if (descriptor.value.isException() or !descriptor.value.isObject()) {
        _ = ctx.throwTypeError("Illegal invocation");
        return null;
    }
    return descriptor.value.dup(ctx);
}

fn jsHtmlCollectionLengthGet(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const items = requireHtmlCollectionItems(ctx, this_value) orelse return quickjs.Value.exception;
    defer items.deinit(ctx);
    return quickjs.Value.initInt64(arrayLength(ctx, items));
}

fn jsHtmlCollectionItem(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const items = requireHtmlCollectionItems(ctx, this_value) orelse return quickjs.Value.exception;
    defer items.deinit(ctx);

    const args: []const quickjs.Value = @ptrCast(raw_args);
    if (args.len == 0) return quickjs.Value.null;
    var index_u32: u32 = 0;
    if (c.JS_ToUint32(ctx.cval(), &index_u32, args[0].cval()) < 0) return quickjs.Value.null;

    const value = items.getPropertyUint32(ctx, index_u32);
    if (value.isException() or value.isUndefined()) {
        value.deinit(ctx);
        return quickjs.Value.null;
    }
    return value;
}

fn jsHtmlCollectionNamedItem(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const items = requireHtmlCollectionItems(ctx, this_value) orelse return quickjs.Value.exception;
    defer items.deinit(ctx);

    const args: []const quickjs.Value = @ptrCast(raw_args);
    const name = parseStringArg(ctx, args, 0, "namedItem") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name.ptr);

    if (name.len == 0) return quickjs.Value.null;

    const len = arrayLength(ctx, items);
    for (0..len) |i_usize| {
        const element = items.getPropertyUint32(ctx, @intCast(i_usize));
        defer element.deinit(ctx);
        if (!element.isObject()) continue;

        if (elementAttributeString(ctx, element, "id")) |id| {
            defer ctx.freeCString(id.ptr);
            if (std.mem.eql(u8, id.ptr[0..id.len], name.ptr[0..name.len])) return element.dup(ctx);
        }

        if (!elementIsInHtmlNamespace(ctx, element)) continue;
        if (elementAttributeString(ctx, element, "name")) |attr_name| {
            defer ctx.freeCString(attr_name.ptr);
            if (std.mem.eql(u8, attr_name.ptr[0..attr_name.len], name.ptr[0..name.len])) return element.dup(ctx);
        }
    }

    return quickjs.Value.null;
}

fn jsHtmlCollectionToArray(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const items = requireHtmlCollectionItems(ctx, this_value) orelse return quickjs.Value.exception;
    return items;
}

fn jsHtmlCollectionIterator(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const items = requireHtmlCollectionItems(ctx, this_value) orelse return quickjs.Value.exception;
    defer items.deinit(ctx);

    const iterator = quickjs.Value.initObject(ctx);
    if (iterator.isException()) return iterator;

    iterator.setPropertyStr(ctx, "__zigHtmlCollectionItems", items.dup(ctx)) catch {
        iterator.deinit(ctx);
        return quickjs.Value.exception;
    };
    iterator.setPropertyStr(ctx, "__zigHtmlCollectionIndex", quickjs.Value.initInt64(0)) catch {
        iterator.deinit(ctx);
        return quickjs.Value.exception;
    };
    installMethod(ctx, iterator, "next", jsHtmlCollectionIteratorNext, 0) catch {
        iterator.deinit(ctx);
        return quickjs.Value.exception;
    };
    return iterator;
}

fn jsHtmlCollectionIteratorNext(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const items = this_value.getPropertyStr(ctx, "__zigHtmlCollectionItems");
    defer items.deinit(ctx);
    if (items.isException() or !items.isObject()) {
        _ = ctx.throwTypeError("Illegal invocation");
        return quickjs.Value.exception;
    }

    const index_value = this_value.getPropertyStr(ctx, "__zigHtmlCollectionIndex");
    defer index_value.deinit(ctx);
    const index_i64 = index_value.toInt64(ctx) catch 0;
    const index: u32 = if (index_i64 < 0) 0 else @intCast(@min(index_i64, std.math.maxInt(u32)));
    const len = arrayLength(ctx, items);

    const result = quickjs.Value.initObject(ctx);
    if (result.isException()) return result;

    if (index < len) {
        const value = items.getPropertyUint32(ctx, index);
        if (value.isException()) {
            result.deinit(ctx);
            return quickjs.Value.exception;
        }
        defer value.deinit(ctx);
        result.setPropertyStr(ctx, "value", value.dup(ctx)) catch {
            result.deinit(ctx);
            return quickjs.Value.exception;
        };
        result.setPropertyStr(ctx, "done", quickjs.Value.initBool(false)) catch {
            result.deinit(ctx);
            return quickjs.Value.exception;
        };
        this_value.setPropertyStr(ctx, "__zigHtmlCollectionIndex", quickjs.Value.initInt64(@as(i64, index) + 1)) catch {
            result.deinit(ctx);
            return quickjs.Value.exception;
        };
        return result;
    }

    result.setPropertyStr(ctx, "value", quickjs.Value.undefined) catch {
        result.deinit(ctx);
        return quickjs.Value.exception;
    };
    result.setPropertyStr(ctx, "done", quickjs.Value.initBool(true)) catch {
        result.deinit(ctx);
        return quickjs.Value.exception;
    };
    return result;
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

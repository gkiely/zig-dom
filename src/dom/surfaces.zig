pub const NodeConstant = struct {
    name: [:0]const u8,
    value: i64,
};

pub const node_constants = [_]NodeConstant{
    .{ .name = "ELEMENT_NODE", .value = 1 },
    .{ .name = "TEXT_NODE", .value = 3 },
    .{ .name = "COMMENT_NODE", .value = 8 },
    .{ .name = "DOCUMENT_NODE", .value = 9 },
    .{ .name = "DOCUMENT_TYPE_NODE", .value = 10 },
    .{ .name = "DOCUMENT_FRAGMENT_NODE", .value = 11 },
    .{ .name = "DOCUMENT_POSITION_DISCONNECTED", .value = 1 },
    .{ .name = "DOCUMENT_POSITION_PRECEDING", .value = 2 },
    .{ .name = "DOCUMENT_POSITION_FOLLOWING", .value = 4 },
    .{ .name = "DOCUMENT_POSITION_CONTAINS", .value = 8 },
    .{ .name = "DOCUMENT_POSITION_CONTAINED_BY", .value = 16 },
    .{ .name = "DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC", .value = 32 },
};

pub const html_element_constructors = [_][:0]const u8{
    "HTMLInputElement",
    "HTMLButtonElement",
    "HTMLFormElement",
    "HTMLSelectElement",
    "HTMLOptionElement",
    "HTMLTextAreaElement",
    "HTMLLabelElement",
    "HTMLAnchorElement",
    "HTMLIFrameElement",
    "HTMLLIElement",
    "HTMLOListElement",
    "HTMLUListElement",
};

pub const form_value_constructors = [_][*:0]const u8{
    "HTMLInputElement",
    "HTMLTextAreaElement",
    "HTMLSelectElement",
};

pub const window_constructor_exports = [_][*:0]const u8{
    "Window",
    "EventTarget",
    "Node",
    "Element",
    "HTMLElement",
    "SVGElement",
    "Document",
    "DocumentFragment",
    "DocumentType",
    "CharacterData",
    "Text",
    "Comment",
    "HTMLInputElement",
    "HTMLButtonElement",
    "HTMLFormElement",
    "HTMLSelectElement",
    "HTMLOptionElement",
    "HTMLTextAreaElement",
    "HTMLLabelElement",
    "HTMLAnchorElement",
    "HTMLIFrameElement",
    "NodeList",
    "HTMLCollection",
    "Event",
    "CustomEvent",
    "MouseEvent",
    "DOMRect",
    "MutationObserver",
    "ResizeObserver",
};

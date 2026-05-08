const quickjs = @import("quickjs");
const bindings = @import("bindings.zig");

const DomClassesError = bindings.DomClassesError;

pub fn installPrototype(ctx: *quickjs.Context, proto: quickjs.Value, comptime callbacks: type) DomClassesError!void {
    try bindings.installGetter(ctx, proto, "nodeType", callbacks.nodeTypeGet);
    try bindings.installGetter(ctx, proto, "nodeName", callbacks.nodeNameGet);
    try bindings.installGetter(ctx, proto, "parentNode", callbacks.parentNodeGet);
    try bindings.installGetter(ctx, proto, "parentElement", callbacks.parentElementGet);
    try bindings.installGetter(ctx, proto, "firstChild", callbacks.firstChildGet);
    try bindings.installGetter(ctx, proto, "lastChild", callbacks.lastChildGet);
    try bindings.installGetter(ctx, proto, "previousSibling", callbacks.previousSiblingGet);
    try bindings.installGetter(ctx, proto, "nextSibling", callbacks.nextSiblingGet);
    try bindings.installGetter(ctx, proto, "ownerDocument", callbacks.ownerDocumentGet);
    try bindings.installGetter(ctx, proto, "isConnected", callbacks.isConnectedGet);
    try bindings.installGetter(ctx, proto, "childNodes", callbacks.childNodesGet);
    try bindings.installGetter(ctx, proto, "children", callbacks.childrenGet);
    try bindings.installGetter(ctx, proto, "firstElementChild", callbacks.firstElementChildGet);
    try bindings.installGetter(ctx, proto, "lastElementChild", callbacks.lastElementChildGet);
    try bindings.installGetter(ctx, proto, "previousElementSibling", callbacks.previousElementSiblingGet);
    try bindings.installGetter(ctx, proto, "nextElementSibling", callbacks.nextElementSiblingGet);
    try bindings.installGetter(ctx, proto, "childElementCount", callbacks.childElementCountGet);
    try bindings.installAccessor(ctx, proto, "textContent", callbacks.textContentGet, callbacks.textContentSet);
    try bindings.installAccessor(ctx, proto, "nodeValue", callbacks.nodeValueGet, callbacks.nodeValueSet);
    try bindings.installGetter(ctx, proto, "outerHTML", callbacks.outerHtmlGet);
    try bindings.installMethod(ctx, proto, "contains", callbacks.contains, 1);
    try bindings.installMethod(ctx, proto, "getRootNode", callbacks.getRootNode, 0);
    try bindings.installMethod(ctx, proto, "compareDocumentPosition", callbacks.compareDocumentPosition, 1);
    try bindings.installMethod(ctx, proto, "isEqualNode", callbacks.isEqualNode, 1);
    try bindings.installMethod(ctx, proto, "normalize", callbacks.normalize, 0);
    try bindings.installMethod(ctx, proto, "appendChild", callbacks.appendChild, 1);
    try bindings.installMethod(ctx, proto, "append", callbacks.append, 1);
    try bindings.installMethod(ctx, proto, "prepend", callbacks.prepend, 1);
    try bindings.installMethod(ctx, proto, "insertBefore", callbacks.insertBefore, 2);
    try bindings.installMethod(ctx, proto, "removeChild", callbacks.removeChild, 1);
    try bindings.installMethod(ctx, proto, "remove", callbacks.remove, 0);
    try bindings.installMethod(ctx, proto, "replaceChild", callbacks.replaceChild, 2);
    try bindings.installMethod(ctx, proto, "cloneNode", callbacks.cloneNode, 1);
}

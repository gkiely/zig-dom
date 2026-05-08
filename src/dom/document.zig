const quickjs = @import("quickjs");
const bindings = @import("bindings.zig");

const DomClassesError = bindings.DomClassesError;

pub fn installPrototype(ctx: *quickjs.Context, proto: quickjs.Value, comptime callbacks: type) DomClassesError!void {
    try bindings.installGetter(ctx, proto, "documentElement", callbacks.documentElementGet);
    try bindings.installGetter(ctx, proto, "doctype", callbacks.doctypeGet);
    try bindings.installGetter(ctx, proto, "head", callbacks.headGet);
    try bindings.installGetter(ctx, proto, "body", callbacks.bodyGet);
    try bindings.installGetter(ctx, proto, "defaultView", callbacks.defaultViewGet);
    try bindings.installGetter(ctx, proto, "implementation", callbacks.implementationGet);
    try bindings.installGetter(ctx, proto, "contentType", callbacks.contentTypeGet);
    try bindings.installMethod(ctx, proto, "createElement", callbacks.createElement, 1);
    try bindings.installMethod(ctx, proto, "createElementNS", callbacks.createElementNS, 2);
    try bindings.installMethod(ctx, proto, "createAttribute", callbacks.createAttribute, 1);
    try bindings.installMethod(ctx, proto, "createTextNode", callbacks.createTextNode, 1);
    try bindings.installMethod(ctx, proto, "createComment", callbacks.createComment, 1);
    try bindings.installMethod(ctx, proto, "createProcessingInstruction", callbacks.createProcessingInstruction, 2);
    try bindings.installMethod(ctx, proto, "createDocumentFragment", callbacks.createDocumentFragment, 0);
    try bindings.installMethod(ctx, proto, "createDocumentType", callbacks.createDocumentType, 3);
    try bindings.installMethod(ctx, proto, "createEvent", callbacks.createEvent, 1);
    try bindings.installMethod(ctx, proto, "createRange", callbacks.createRange, 0);
    try bindings.installMethod(ctx, proto, "createTreeWalker", callbacks.createTreeWalker, 1);
    try bindings.installMethod(ctx, proto, "getSelection", callbacks.getSelection, 0);
    try bindings.installMethod(ctx, proto, "importNode", callbacks.importNode, 2);
    try bindings.installMethod(ctx, proto, "adoptNode", callbacks.adoptNode, 1);
    try bindings.installMethod(ctx, proto, "getElementById", callbacks.getElementById, 1);
    try bindings.installMethod(ctx, proto, "querySelector", callbacks.querySelector, 1);
    try bindings.installMethod(ctx, proto, "querySelectorAll", callbacks.querySelectorAll, 1);
    try bindings.installMethod(ctx, proto, "getElementsByTagName", callbacks.getElementsByTagName, 1);
    try bindings.installMethod(ctx, proto, "getElementsByTagNameNS", callbacks.getElementsByTagNameNS, 2);
    try bindings.installMethod(ctx, proto, "getElementsByClassName", callbacks.getElementsByClassName, 1);
}

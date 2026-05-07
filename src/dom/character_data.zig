const quickjs = @import("quickjs");
const bindings = @import("bindings.zig");

const DomClassesError = bindings.DomClassesError;

pub fn installPrototype(ctx: *quickjs.Context, proto: quickjs.Value, comptime callbacks: type) DomClassesError!void {
    try bindings.installAccessor(ctx, proto, "data", callbacks.dataGet, callbacks.dataSet);
    try bindings.installGetter(ctx, proto, "length", callbacks.lengthGet);
    try bindings.installMethod(ctx, proto, "appendData", callbacks.appendData, 1);
    try bindings.installMethod(ctx, proto, "deleteData", callbacks.deleteData, 2);
    try bindings.installMethod(ctx, proto, "insertData", callbacks.insertData, 2);
    try bindings.installMethod(ctx, proto, "replaceData", callbacks.replaceData, 3);
    try bindings.installMethod(ctx, proto, "substringData", callbacks.substringData, 2);
}

const quickjs = @import("quickjs");
const bindings = @import("bindings.zig");

const DomClassesError = bindings.DomClassesError;

pub fn installPrototype(ctx: *quickjs.Context, proto: quickjs.Value, comptime callbacks: type) DomClassesError!void {
    try bindings.installMethod(ctx, proto, "addEventListener", callbacks.addEventListener, 3);
    try bindings.installMethod(ctx, proto, "removeEventListener", callbacks.removeEventListener, 3);
    try bindings.installMethod(ctx, proto, "dispatchEvent", callbacks.dispatchEvent, 1);
}

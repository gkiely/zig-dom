const runtime = @import("runtime.zig");

pub fn initRuntime(allocator: @import("std").mem.Allocator) runtime.RuntimeError!runtime.Runtime {
    return runtime.Runtime.init(allocator);
}

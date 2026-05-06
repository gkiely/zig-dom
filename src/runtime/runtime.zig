const std = @import("std");

pub const RuntimeError = error{
    NotImplemented,
};

pub const ScriptKind = enum {
    script,
    module,
};

pub const Exception = struct {
    message: []const u8,
    stack: ?[]const u8 = null,
};

pub const Runtime = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RuntimeError!Runtime {
        _ = allocator;
        return error.NotImplemented;
    }

    pub fn deinit(self: *Runtime) void {
        _ = self;
    }
};

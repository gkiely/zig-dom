const std = @import("std");
const quickjs_ng = @import("quickjs_ng.zig");

pub const RuntimeError = error{
    OutOfMemory,
    EvaluationFailed,
    JobExecutionFailed,
    PropertyAccessFailed,
    ValueConversionFailed,
};

pub const Exception = struct {
    message: []u8,
    stack: ?[]u8 = null,

    pub fn deinit(self: Exception, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.stack) |stack| {
            allocator.free(stack);
        }
    }
};

pub const ModuleContext = quickjs_ng.Context;
pub const ModuleDef = quickjs_ng.ModuleDef;
pub const OnLoadResult = quickjs_ng.OnLoadResult;

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    adapter: quickjs_ng.Runtime,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) RuntimeError!Runtime {
        return initWithDom(allocator, io, true);
    }

    pub fn initWithDom(allocator: std.mem.Allocator, io: std.Io, install_dom: bool) RuntimeError!Runtime {
        return .{
            .allocator = allocator,
            .adapter = try quickjs_ng.Runtime.initWithDom(allocator, io, install_dom),
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.adapter.deinit();
    }

    pub fn evalScript(self: *Runtime, filename: []const u8, source: []const u8) RuntimeError!void {
        try self.adapter.evalScript(filename, source);
    }

    pub fn evalModule(self: *Runtime, filename: []const u8, source: []const u8) RuntimeError!void {
        try self.adapter.evalModule(filename, source);
    }

    pub fn setModuleLoaderFunc(
        self: *Runtime,
        comptime T: type,
        userdata: ?*T,
        comptime module_normalize: ?quickjs_ng.Runtime.ModuleNormalizeFunc(T),
        comptime module_loader: ?quickjs_ng.Runtime.ModuleLoaderFunc(T),
    ) void {
        self.adapter.setModuleLoaderFunc(T, userdata, module_normalize, module_loader);
    }

    pub fn isJobPending(self: *Runtime) bool {
        return self.adapter.isJobPending();
    }

    pub fn executePendingJob(self: *Runtime) RuntimeError!bool {
        return self.adapter.executePendingJob();
    }

    pub fn hasPendingNativeTimers(self: *Runtime) bool {
        return self.adapter.hasPendingNativeTimers();
    }

    pub fn executePendingJobOrNativeTimer(self: *Runtime) RuntimeError!bool {
        return self.adapter.executePendingJobOrNativeTimer();
    }

    pub fn loadFromOnLoad(self: *Runtime, path: []const u8) RuntimeError!?OnLoadResult {
        return self.adapter.loadFromOnLoad(path);
    }

    pub fn matchesOnLoad(self: *Runtime, path: []const u8) RuntimeError!bool {
        return self.adapter.matchesOnLoad(path);
    }

    pub fn getGlobalBool(self: *Runtime, name: []const u8) RuntimeError!bool {
        return self.adapter.getGlobalBool(name);
    }

    pub fn getGlobalInt32(self: *Runtime, name: []const u8) RuntimeError!i32 {
        return self.adapter.getGlobalInt32(name);
    }

    pub fn getGlobalStringDup(self: *Runtime, name: []const u8) RuntimeError![]u8 {
        return self.adapter.getGlobalStringDup(name);
    }

    pub fn takeException(self: *Runtime) RuntimeError!Exception {
        const exception = try self.adapter.takeException();
        return .{
            .message = exception.message,
            .stack = exception.stack,
        };
    }
};

const std = @import("std");
const quickjs = @import("quickjs");

const Allocator = std.mem.Allocator;

pub const RuntimeError = error{
    OutOfMemory,
    EvaluationFailed,
    JobExecutionFailed,
    PropertyAccessFailed,
    ValueConversionFailed,
};

pub const Exception = struct {
    message: []u8,
    stack: ?[]u8,

    pub fn deinit(self: Exception, allocator: Allocator) void {
        allocator.free(self.message);
        if (self.stack) |stack| {
            allocator.free(stack);
        }
    }
};

pub const Runtime = struct {
    allocator: Allocator,
    rt: *quickjs.Runtime,
    ctx: *quickjs.Context,

    pub fn init(allocator: Allocator) RuntimeError!Runtime {
        const rt = quickjs.Runtime.init() catch return error.OutOfMemory;
        errdefer rt.deinit();

        const ctx = rt.newContext() catch return error.OutOfMemory;
        errdefer ctx.deinit();

        return .{
            .allocator = allocator,
            .rt = rt,
            .ctx = ctx,
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.ctx.deinit();
        self.rt.deinit();
    }

    pub fn evalScript(self: *Runtime, filename: []const u8, source: []const u8) RuntimeError!void {
        const filename_z = self.allocator.dupeZ(u8, filename) catch return error.OutOfMemory;
        defer self.allocator.free(filename_z);

        const result = self.ctx.eval(source, filename_z, .{});
        defer result.deinit(self.ctx);

        if (result.isException()) {
            return error.EvaluationFailed;
        }
    }

    pub fn isJobPending(self: *Runtime) bool {
        return self.rt.isJobPending();
    }

    pub fn executePendingJob(self: *Runtime) RuntimeError!bool {
        const maybe_ctx = self.rt.executePendingJob() catch return error.JobExecutionFailed;
        return maybe_ctx != null;
    }

    pub fn getGlobalBool(self: *Runtime, name: []const u8) RuntimeError!bool {
        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);

        const name_z = self.allocator.dupeZ(u8, name) catch return error.OutOfMemory;
        defer self.allocator.free(name_z);

        const value = global.getPropertyStr(self.ctx, name_z);
        defer value.deinit(self.ctx);

        if (value.isException()) {
            return error.PropertyAccessFailed;
        }

        return value.toBool(self.ctx) catch error.ValueConversionFailed;
    }

    pub fn getGlobalInt32(self: *Runtime, name: []const u8) RuntimeError!i32 {
        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);

        const name_z = self.allocator.dupeZ(u8, name) catch return error.OutOfMemory;
        defer self.allocator.free(name_z);

        const value = global.getPropertyStr(self.ctx, name_z);
        defer value.deinit(self.ctx);

        if (value.isException()) {
            return error.PropertyAccessFailed;
        }

        return value.toInt32(self.ctx) catch error.ValueConversionFailed;
    }

    pub fn getGlobalStringDup(self: *Runtime, name: []const u8) RuntimeError![]u8 {
        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);

        const name_z = self.allocator.dupeZ(u8, name) catch return error.OutOfMemory;
        defer self.allocator.free(name_z);

        const value = global.getPropertyStr(self.ctx, name_z);
        defer value.deinit(self.ctx);

        if (value.isException()) {
            return error.PropertyAccessFailed;
        }

        const c_str = value.toCString(self.ctx) orelse return error.ValueConversionFailed;
        defer self.ctx.freeCString(c_str);

        return self.allocator.dupe(u8, std.mem.span(c_str)) catch error.OutOfMemory;
    }

    pub fn takeException(self: *Runtime) RuntimeError!Exception {
        const exc = self.ctx.getException();
        defer exc.deinit(self.ctx);

        const message = try self.extractStringProperty(exc, "message");
        const stack = self.extractOptionalStringProperty(exc, "stack") catch null;

        return .{ .message = message, .stack = stack };
    }

    fn extractOptionalStringProperty(self: *Runtime, value: quickjs.Value, property_name: []const u8) RuntimeError!?[]u8 {
        const property_name_z = self.allocator.dupeZ(u8, property_name) catch return error.OutOfMemory;
        defer self.allocator.free(property_name_z);

        const prop = value.getPropertyStr(self.ctx, property_name_z);
        defer prop.deinit(self.ctx);

        if (prop.isException()) {
            return error.PropertyAccessFailed;
        }

        if (prop.isUndefined() or prop.isNull()) {
            return null;
        }

        const c_str = prop.toCString(self.ctx) orelse return error.ValueConversionFailed;
        defer self.ctx.freeCString(c_str);
        return self.allocator.dupe(u8, std.mem.span(c_str)) catch error.OutOfMemory;
    }

    fn extractStringProperty(self: *Runtime, value: quickjs.Value, property_name: []const u8) RuntimeError![]u8 {
        if (try self.extractOptionalStringProperty(value, property_name)) |message| {
            return message;
        }

        const fallback = value.toCString(self.ctx) orelse return error.ValueConversionFailed;
        defer self.ctx.freeCString(fallback);
        return self.allocator.dupe(u8, std.mem.span(fallback)) catch error.OutOfMemory;
    }
};

pub fn isLinked() bool {
    _ = quickjs.Runtime;
    return true;
}

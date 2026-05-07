const std = @import("std");
const quickjs = @import("quickjs");
const zig_dom = @import("../zig_dom.zig");
const c = quickjs.c;

const Allocator = std.mem.Allocator;

pub const DomClassesError = error{
    OutOfMemory,
    RegistrationFailed,
    PropertyAccessFailed,
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

        try installMethod(ctx, node_proto, "contains", jsNodeContains, 1);
        try installMethod(ctx, node_proto, "appendChild", jsNodeAppendChild, 1);

        const info = global.getPropertyStr(ctx, "__zigDomNativeClasses");
        defer info.deinit(ctx);
        if (!info.isException() and info.isObject()) {
            info.setPropertyStr(ctx, "nodeSliceInstalled", quickjs.Value.initBool(true)) catch return error.PropertyAccessFailed;
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

fn installMethod(
    ctx: *quickjs.Context,
    target: quickjs.Value,
    name: [:0]const u8,
    comptime func: quickjs.cfunc.Func,
    arg_count: i32,
) DomClassesError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) {
        return error.OutOfMemory;
    }

    target.setPropertyStr(ctx, name.ptr, value) catch {
        return error.PropertyAccessFailed;
    };
}

fn jsNodeContains(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "contains") orelse return quickjs.Value.exception;
    const other_handle = parseOptionalNodeArgHandle(ctx, args, 0) orelse return quickjs.Value.initBool(false);

    return quickjs.Value.initBool(zig_dom.zig_dom_node_contains(this_handle, other_handle) == 1);
}

fn jsNodeAppendChild(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const this_handle = parseThisHandle(ctx, this_value, "appendChild") orelse return quickjs.Value.exception;
    const child_handle = parseRequiredNodeArgHandle(ctx, args, 0, "appendChild") orelse return quickjs.Value.exception;

    const status = if (zig_dom.zig_dom_node_type(child_handle) == 11)
        zig_dom.zig_dom_node_append_fragment(this_handle, child_handle)
    else
        zig_dom.zig_dom_node_append_child(this_handle, child_handle);
    if (status != 0) {
        return throwStatus(ctx, "appendChild", status);
    }

    return args[0].dup(ctx);
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

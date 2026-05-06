const std = @import("std");
const quickjs = @import("quickjs");
const zig_dom = @import("../zig_dom.zig");

const Allocator = std.mem.Allocator;

const dom_bootstrap_source =
    \\(() => {
    \\  const native = globalThis.__zigDomNative;
    \\  const windowHandle = globalThis.__zigDomWindowHandle;
    \\  const documentHandle = globalThis.__zigDomDocumentHandle;
    \\  const handleSymbol = Symbol("zigDomHandle");
    \\  const ownerDocumentSymbol = Symbol("zigDomOwnerDocument");
    \\
    \\  function getHandle(value, typeName) {
    \\    if (!value || typeof value !== "object" || typeof value[handleSymbol] !== "number") {
    \\      throw new TypeError(typeName + " is not a native zig-dom node");
    \\    }
    \\    return value[handleSymbol];
    \\  }
    \\
    \\  class Node {
    \\    constructor(handle, ownerDocumentHandle) {
    \\      this[handleSymbol] = handle;
    \\      this[ownerDocumentSymbol] = ownerDocumentHandle;
    \\    }
    \\
    \\    appendChild(child) {
    \\      native.nodeAppendChild(getHandle(this, "this"), getHandle(child, "child"));
    \\      return child;
    \\    }
    \\
    \\    get textContent() {
    \\      return native.nodeTextContent(getHandle(this, "this"));
    \\    }
    \\
    \\    set textContent(value) {
    \\      native.nodeSetTextContent(getHandle(this, "this"), value == null ? "" : String(value));
    \\    }
    \\  }
    \\
    \\  class Element extends Node {}
    \\
    \\  class Text extends Node {
    \\    constructor(data = "") {
    \\      const handle = native.documentCreateTextNode(documentHandle, String(data));
    \\      super(handle, documentHandle);
    \\    }
    \\  }
    \\
    \\  class Document extends Node {
    \\    constructor(handle) {
    \\      super(handle, handle);
    \\    }
    \\
    \\    createElement(name) {
    \\      const handle = native.documentCreateElement(getHandle(this, "this"), String(name));
    \\      return new Element(handle, this[ownerDocumentSymbol]);
    \\    }
    \\  }
    \\
    \\  class Window {
    \\    constructor(handle, document) {
    \\      this[handleSymbol] = handle;
    \\      this.document = document;
    \\    }
    \\  }
    \\
    \\  const document = new Document(documentHandle);
    \\  const window = new Window(windowHandle, document);
    \\  Object.assign(globalThis, { Window, Document, Node, Element, Text, window, document });
    \\
    \\  delete globalThis.__zigDomNative;
    \\  delete globalThis.__zigDomWindowHandle;
    \\  delete globalThis.__zigDomDocumentHandle;
    \\})();
;

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
    dom_window_handle: u64,

    pub fn init(allocator: Allocator) RuntimeError!Runtime {
        const rt = quickjs.Runtime.init() catch return error.OutOfMemory;
        errdefer rt.deinit();

        const ctx = rt.newContext() catch return error.OutOfMemory;
        errdefer ctx.deinit();

        var runtime: Runtime = .{
            .allocator = allocator,
            .rt = rt,
            .ctx = ctx,
            .dom_window_handle = 0,
        };

        try runtime.installNativeDomGlobals();
        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        if (self.dom_window_handle != 0) {
            zig_dom.zig_dom_destroy_window(self.dom_window_handle);
            self.dom_window_handle = 0;
        }
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

    fn installNativeDomGlobals(self: *Runtime) RuntimeError!void {
        var window_handle: u64 = 0;
        if (zig_dom.zig_dom_create_window(&window_handle) != 0) {
            return error.EvaluationFailed;
        }
        errdefer zig_dom.zig_dom_destroy_window(window_handle);

        var document_handle: u64 = 0;
        if (zig_dom.zig_dom_window_document(window_handle, &document_handle) != 0) {
            return error.EvaluationFailed;
        }

        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);

        const native = quickjs.Value.initObject(self.ctx);
        if (native.isException()) {
            return error.OutOfMemory;
        }

        installNativeFunction(self.ctx, native, "documentCreateElement", jsDocumentCreateElement, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "documentCreateTextNode", jsDocumentCreateTextNode, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeAppendChild", jsNodeAppendChild, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeTextContent", jsNodeTextContent, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeSetTextContent", jsNodeSetTextContent, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };

        global.setPropertyStr(self.ctx, "__zigDomNative", native) catch return error.EvaluationFailed;
        global.setPropertyStr(self.ctx, "__zigDomWindowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch return error.EvaluationFailed;
        global.setPropertyStr(self.ctx, "__zigDomDocumentHandle", quickjs.Value.initInt64(@intCast(document_handle))) catch return error.EvaluationFailed;

        try self.evalScript("<zig-dom-bootstrap>", dom_bootstrap_source);
        self.dom_window_handle = window_handle;
    }
};

fn installNativeFunction(
    ctx: *quickjs.Context,
    target: quickjs.Value,
    name: [:0]const u8,
    comptime func: quickjs.cfunc.Func,
    arg_count: i32,
) RuntimeError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) {
        return error.EvaluationFailed;
    }

    target.setPropertyStr(ctx, name.ptr, value) catch return error.EvaluationFailed;
}

fn jsDocumentCreateElement(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const document_handle = parseHandleArg(ctx, args, 0, "documentCreateElement") orelse return quickjs.Value.exception;
    const name_value = parseStringArg(ctx, args, 1, "documentCreateElement") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name_value.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_element(document_handle, name_value.ptr, name_value.len, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "documentCreateElement", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsDocumentCreateTextNode(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const document_handle = parseHandleArg(ctx, args, 0, "documentCreateTextNode") orelse return quickjs.Value.exception;
    const text_value = parseStringArg(ctx, args, 1, "documentCreateTextNode") orelse return quickjs.Value.exception;
    defer ctx.freeCString(text_value.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_text_node(document_handle, text_value.ptr, text_value.len, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "documentCreateTextNode", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsNodeAppendChild(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const parent_handle = parseHandleArg(ctx, args, 0, "nodeAppendChild") orelse return quickjs.Value.exception;
    const child_handle = parseHandleArg(ctx, args, 1, "nodeAppendChild") orelse return quickjs.Value.exception;

    const status = zig_dom.zig_dom_node_append_child(parent_handle, child_handle);
    if (status != 0) {
        return throwStatus(ctx, "nodeAppendChild", status);
    }

    return quickjs.Value.initInt64(@intCast(child_handle));
}

fn jsNodeTextContent(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const node_handle = parseHandleArg(ctx, args, 0, "nodeTextContent") orelse return quickjs.Value.exception;

    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_text_content(node_handle, &out_ptr, &out_len);
    if (status != 0) {
        return throwStatus(ctx, "nodeTextContent", status);
    }
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);

    if (out_ptr == null or out_len == 0) {
        return quickjs.Value.initStringLen(ctx, "");
    }

    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
}

fn jsNodeSetTextContent(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const node_handle = parseHandleArg(ctx, args, 0, "nodeSetTextContent") orelse return quickjs.Value.exception;

    if (args.len < 2) {
        const empty: []const u8 = "";
        const status_missing = zig_dom.zig_dom_node_set_text_content(node_handle, empty.ptr, empty.len);
        if (status_missing != 0) {
            return throwStatus(ctx, "nodeSetTextContent", status_missing);
        }
        return quickjs.Value.initInt64(0);
    }

    const text_value = parseStringArg(ctx, args, 1, "nodeSetTextContent") orelse return quickjs.Value.exception;
    defer ctx.freeCString(text_value.ptr);

    const status = zig_dom.zig_dom_node_set_text_content(node_handle, text_value.ptr, text_value.len);
    if (status != 0) {
        return throwStatus(ctx, "nodeSetTextContent", status);
    }

    return quickjs.Value.initInt64(0);
}

const CStringArg = struct {
    ptr: [*:0]const u8,
    len: usize,
};

fn parseHandleArg(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize, operation: []const u8) ?u64 {
    if (index >= args.len) {
        _ = throwOperationMessage(ctx, operation, "missing handle argument");
        return null;
    }

    const handle_i64 = args[index].toInt64(ctx) catch {
        _ = throwOperationMessage(ctx, operation, "handle must be numeric");
        return null;
    };

    if (handle_i64 <= 0) {
        _ = throwOperationMessage(ctx, operation, "handle must be positive");
        return null;
    }

    return @intCast(handle_i64);
}

fn parseStringArg(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize, operation: []const u8) ?CStringArg {
    if (index >= args.len) {
        _ = throwOperationMessage(ctx, operation, "missing string argument");
        return null;
    }

    const string_value = args[index].toCStringLen(ctx) orelse {
        _ = throwOperationMessage(ctx, operation, "argument could not be converted to string");
        return null;
    };

    return .{ .ptr = string_value.ptr, .len = string_value.len };
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

pub fn isLinked() bool {
    _ = quickjs.Runtime;
    return true;
}

const std = @import("std");
const quickjs = @import("quickjs");
const zig_dom = @import("../zig_dom.zig");
const dom_classes = @import("dom_classes.zig");
const host_platform = @import("host_platform.zig");
const host_assertions = @import("host_assertions.zig");
const host_runner = @import("host_runner.zig");

const Allocator = std.mem.Allocator;
var host_io: ?std.Io = null;

pub const Context = quickjs.Context;
pub const ModuleDef = quickjs.ModuleDef;

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
    dom_classes_state: ?*dom_classes.DomClasses,
    host_runner_state: ?*host_runner.HostRunner,

    pub fn init(allocator: Allocator, io: std.Io) RuntimeError!Runtime {
        host_io = io;

        const rt = quickjs.Runtime.init() catch return error.OutOfMemory;
        errdefer rt.deinit();

        const ctx = rt.newContext() catch return error.OutOfMemory;
        errdefer ctx.deinit();

        var runtime: Runtime = .{
            .allocator = allocator,
            .rt = rt,
            .ctx = ctx,
            .dom_window_handle = 0,
            .dom_classes_state = null,
            .host_runner_state = null,
        };

        try runtime.installHostGlobals();
        try runtime.installNativeDomGlobals();
        try runtime.installHostPlatformGlobals();
        try runtime.installHostAssertions();
        try runtime.installHostRunner();
        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        if (self.host_runner_state) |runner| {
            runner.deinit();
            self.host_runner_state = null;
        }
        if (self.dom_classes_state) |classes| {
            classes.deinit();
            self.allocator.destroy(classes);
            self.dom_classes_state = null;
        }
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
        const source_z = self.allocator.dupeZ(u8, source) catch return error.OutOfMemory;
        defer self.allocator.free(source_z);

        const result = self.ctx.eval(source_z[0..source.len], filename_z, .{});
        defer result.deinit(self.ctx);

        if (result.isException()) {
            return error.EvaluationFailed;
        }
    }

    pub fn evalModule(self: *Runtime, filename: []const u8, source: []const u8) RuntimeError!void {
        const filename_z = self.allocator.dupeZ(u8, filename) catch return error.OutOfMemory;
        defer self.allocator.free(filename_z);
        const source_z = self.allocator.dupeZ(u8, source) catch return error.OutOfMemory;
        defer self.allocator.free(source_z);

        const compiled = self.ctx.eval(source_z[0..source.len], filename_z, .{ .type = .module, .compile_only = true });
        if (compiled.isException()) {
            compiled.deinit(self.ctx);
            return error.EvaluationFailed;
        }

        compiled.resolveModule(self.ctx) catch {
            compiled.deinit(self.ctx);
            return error.EvaluationFailed;
        };

        const result = self.ctx.evalFunction(compiled);
        defer result.deinit(self.ctx);
        if (result.isException()) {
            return error.EvaluationFailed;
        }

        if (result.isPromise()) {
            var pump_iterations: usize = 0;
            while (true) : (pump_iterations += 1) {
                const state = result.promiseState(self.ctx);
                switch (state) {
                    .fulfilled => break,
                    .rejected => {
                        const rejection = result.promiseResult(self.ctx);
                        defer rejection.deinit(self.ctx);

                        var rejection_text: []const u8 = "<null rejection>";
                        var rejection_text_owned: ?[]u8 = null;
                        defer if (rejection_text_owned) |owned| self.allocator.free(owned);
                        const rejection_stack = self.extractOptionalStringProperty(rejection, "stack") catch null;
                        defer if (rejection_stack) |stack| self.allocator.free(stack);

                        const text_value = rejection.toStringValue(self.ctx);
                        defer text_value.deinit(self.ctx);

                        if (text_value.isException()) {
                            rejection_text = "<failed to stringify rejection>";
                        } else if (text_value.toCStringLen(self.ctx)) |text_cstr| {
                            defer self.ctx.freeCString(text_cstr.ptr);
                            const owned = self.allocator.dupe(u8, text_cstr.ptr[0..text_cstr.len]) catch return error.OutOfMemory;
                            rejection_text_owned = owned;
                            rejection_text = owned;
                        }

                        const message_buf = if (rejection_stack) |stack|
                            std.fmt.allocPrint(
                                self.allocator,
                                "module evaluation rejected: {s} ({s})\n{s}",
                                .{ filename, rejection_text, stack },
                            ) catch return error.OutOfMemory
                        else
                            std.fmt.allocPrint(
                                self.allocator,
                                "module evaluation rejected: {s} ({s})",
                                .{ filename, rejection_text },
                            ) catch return error.OutOfMemory;
                        defer self.allocator.free(message_buf);
                        const message = self.allocator.dupeZ(u8, message_buf) catch return error.OutOfMemory;
                        defer self.allocator.free(message);
                        _ = self.ctx.throwInternalError(message);
                        return error.EvaluationFailed;
                    },
                    .pending => {
                        if (!self.isJobPending()) {
                            const message_buf = std.fmt.allocPrint(
                                self.allocator,
                                "module evaluation pending with no jobs: {s}",
                                .{filename},
                            ) catch return error.OutOfMemory;
                            defer self.allocator.free(message_buf);
                            const message = self.allocator.dupeZ(u8, message_buf) catch return error.OutOfMemory;
                            defer self.allocator.free(message);
                            _ = self.ctx.throwInternalError(message);
                            return error.EvaluationFailed;
                        }

                        _ = self.executePendingJob() catch return error.EvaluationFailed;

                        if (pump_iterations > 100_000) {
                            const message_buf = std.fmt.allocPrint(
                                self.allocator,
                                "module evaluation promise pump limit exceeded: {s}",
                                .{filename},
                            ) catch return error.OutOfMemory;
                            defer self.allocator.free(message_buf);
                            const message = self.allocator.dupeZ(u8, message_buf) catch return error.OutOfMemory;
                            defer self.allocator.free(message);
                            _ = self.ctx.throwInternalError(message);
                            return error.EvaluationFailed;
                        }
                    },
                    else => break,
                }
            }
        }
    }

    pub fn ModuleNormalizeFunc(comptime T: type) type {
        return quickjs.Runtime.ModuleNormalizeFunc(T);
    }

    pub fn ModuleLoaderFunc(comptime T: type) type {
        return quickjs.Runtime.ModuleLoaderFunc(T);
    }

    pub fn setModuleLoaderFunc(
        self: *Runtime,
        comptime T: type,
        userdata: ?*T,
        comptime module_normalize: ?quickjs.Runtime.ModuleNormalizeFunc(T),
        comptime module_loader: ?quickjs.Runtime.ModuleLoaderFunc(T),
    ) void {
        self.rt.setModuleLoaderFunc(T, userdata, module_normalize, module_loader);
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

    fn installHostGlobals(self: *Runtime) RuntimeError!void {
        const global = self.ctx.getGlobalObject();
        defer global.deinit(self.ctx);

        try installNativeFunction(self.ctx, global, "__zigReadFileSync", jsReadFileSync, 2);
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

        const classes_state = self.allocator.create(dom_classes.DomClasses) catch return error.OutOfMemory;
        errdefer self.allocator.destroy(classes_state);
        classes_state.* = dom_classes.DomClasses.init(self.allocator, self.rt, self.ctx, global) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.EvaluationFailed,
            };
        };
        errdefer classes_state.deinit();
        self.dom_classes_state = classes_state;
        self.ctx.setOpaque(dom_classes.DomClasses, classes_state);

        const native = quickjs.Value.initObject(self.ctx);
        if (native.isException()) {
            return error.OutOfMemory;
        }

        installNativeFunction(self.ctx, native, "createWindow", jsCreateWindow, 0) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "windowDocument", jsWindowDocument, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "windowDocumentElement", jsWindowDocumentElement, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "windowHead", jsWindowHead, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "windowBody", jsWindowBody, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "documentCreateElement", jsDocumentCreateElement, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "documentCreateTextNode", jsDocumentCreateTextNode, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "documentCreateComment", jsDocumentCreateComment, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "documentCreateDocumentFragment", jsDocumentCreateDocumentFragment, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "documentGetElementById", jsDocumentGetElementById, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "documentQuerySelector", jsDocumentQuerySelector, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "documentQuerySelectorAll", jsDocumentQuerySelectorAll, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeType", jsNodeType, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeOwnerDocument", jsNodeOwnerDocument, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeParent", jsNodeParent, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeFirstChild", jsNodeFirstChild, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeLastChild", jsNodeLastChild, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodePreviousSibling", jsNodePreviousSibling, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeNextSibling", jsNodeNextSibling, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeContains", jsNodeContains, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeName", jsNodeName, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeAppendChild", jsNodeAppendChild, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeAppendFragment", jsNodeAppendFragment, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeInsertBefore", jsNodeInsertBefore, 3) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeRemoveChild", jsNodeRemoveChild, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeReplaceChild", jsNodeReplaceChild, 3) catch |err| {
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
        installNativeFunction(self.ctx, native, "nodeOuterHtml", jsNodeOuterHtml, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeSetInnerHtml", jsNodeSetInnerHtml, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeQuerySelector", jsNodeQuerySelector, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "nodeQuerySelectorAll", jsNodeQuerySelectorAll, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "elementGetAttribute", jsElementGetAttribute, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "elementSetAttribute", jsElementSetAttribute, 3) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "elementRemoveAttribute", jsElementRemoveAttribute, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "elementHasAttribute", jsElementHasAttribute, 2) catch |err| {
            native.deinit(self.ctx);
            return err;
        };
        installNativeFunction(self.ctx, native, "elementAttributesJson", jsElementAttributesJson, 1) catch |err| {
            native.deinit(self.ctx);
            return err;
        };

        global.setPropertyStr(self.ctx, "__zigDomNative", native) catch return error.EvaluationFailed;
        global.setPropertyStr(self.ctx, "__zigDomWindowHandle", quickjs.Value.initInt64(@intCast(window_handle))) catch return error.EvaluationFailed;
        global.setPropertyStr(self.ctx, "__zigDomDocumentHandle", quickjs.Value.initInt64(@intCast(document_handle))) catch return error.EvaluationFailed;

        if (self.dom_classes_state) |classes| {
            classes.installNativeGlobals(self.ctx, global, window_handle, document_handle) catch |err| {
                return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    else => error.EvaluationFailed,
                };
            };
        }
        self.dom_window_handle = window_handle;
    }

    fn installHostPlatformGlobals(self: *Runtime) RuntimeError!void {
        host_platform.install(self.ctx) catch return error.EvaluationFailed;
        host_platform.linkWindow(self.ctx) catch return error.EvaluationFailed;
    }

    fn installHostAssertions(self: *Runtime) RuntimeError!void {
        host_assertions.install(self.ctx) catch return error.EvaluationFailed;
    }

    fn installHostRunner(self: *Runtime) RuntimeError!void {
        self.host_runner_state = host_runner.HostRunner.init(self.allocator, self.rt, self.ctx) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.EvaluationFailed,
            };
        };
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

fn jsReadFileSync(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const path_value = parseStringArg(ctx, args, 0, "readFileSync") orelse return quickjs.Value.exception;
    defer ctx.freeCString(path_value.ptr);

    const path = path_value.ptr[0..path_value.len];
    const io = host_io orelse {
        return quickjs.Value.initStringLen(ctx, "readFileSync failed: host I/O is unavailable").throw(ctx);
    };

    const source = std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.c_allocator, .limited(10 * 1024 * 1024)) catch |err| {
        var message_buffer: [512]u8 = undefined;
        const message = std.fmt.bufPrint(&message_buffer, "readFileSync failed for {s}: {s}", .{ path, @errorName(err) }) catch "readFileSync failed";
        return quickjs.Value.initStringLen(ctx, message).throw(ctx);
    };
    defer std.heap.c_allocator.free(source);

    return quickjs.Value.initStringLen(ctx, source);
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

fn jsCreateWindow(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;

    var out_window: u64 = 0;
    const status = zig_dom.zig_dom_create_window(&out_window);
    if (status != 0) {
        return throwStatus(ctx, "createWindow", status);
    }

    return quickjs.Value.initInt64(@intCast(out_window));
}

fn jsWindowDocument(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const window_handle = parseHandleArg(ctx, args, 0, "windowDocument") orelse return quickjs.Value.exception;
    var out_document: u64 = 0;
    const status = zig_dom.zig_dom_window_document(window_handle, &out_document);
    if (status != 0) {
        return throwStatus(ctx, "windowDocument", status);
    }

    return quickjs.Value.initInt64(@intCast(out_document));
}

fn jsWindowDocumentElement(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const window_handle = parseHandleArg(ctx, args, 0, "windowDocumentElement") orelse return quickjs.Value.exception;
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_window_document_element(window_handle, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "windowDocumentElement", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsWindowHead(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const window_handle = parseHandleArg(ctx, args, 0, "windowHead") orelse return quickjs.Value.exception;
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_window_head(window_handle, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "windowHead", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsWindowBody(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const window_handle = parseHandleArg(ctx, args, 0, "windowBody") orelse return quickjs.Value.exception;
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_window_body(window_handle, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "windowBody", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsDocumentCreateComment(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const document_handle = parseHandleArg(ctx, args, 0, "documentCreateComment") orelse return quickjs.Value.exception;
    const text_value = parseStringArg(ctx, args, 1, "documentCreateComment") orelse return quickjs.Value.exception;
    defer ctx.freeCString(text_value.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_comment(document_handle, text_value.ptr, text_value.len, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "documentCreateComment", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsDocumentCreateDocumentFragment(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const document_handle = parseHandleArg(ctx, args, 0, "documentCreateDocumentFragment") orelse return quickjs.Value.exception;
    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_create_document_fragment(document_handle, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "documentCreateDocumentFragment", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsDocumentGetElementById(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const document_handle = parseHandleArg(ctx, args, 0, "documentGetElementById") orelse return quickjs.Value.exception;
    const id_value = parseStringArg(ctx, args, 1, "documentGetElementById") orelse return quickjs.Value.exception;
    defer ctx.freeCString(id_value.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_get_element_by_id(document_handle, id_value.ptr, id_value.len, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "documentGetElementById", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsDocumentQuerySelector(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const document_handle = parseHandleArg(ctx, args, 0, "documentQuerySelector") orelse return quickjs.Value.exception;
    const selector_value = parseStringArg(ctx, args, 1, "documentQuerySelector") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector_value.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_document_query_selector(document_handle, selector_value.ptr, selector_value.len, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "documentQuerySelector", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsDocumentQuerySelectorAll(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const document_handle = parseHandleArg(ctx, args, 0, "documentQuerySelectorAll") orelse return quickjs.Value.exception;
    const selector_value = parseStringArg(ctx, args, 1, "documentQuerySelectorAll") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector_value.ptr);

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_document_query_selector_all(document_handle, selector_value.ptr, selector_value.len, &out_ptr, &out_len);
    if (status != 0) {
        return throwStatus(ctx, "documentQuerySelectorAll", status);
    }
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);

    return handleArrayToJs(ctx, out_ptr, out_len);
}

fn jsNodeType(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const node_handle = parseHandleArg(ctx, args, 0, "nodeType") orelse return quickjs.Value.exception;
    return quickjs.Value.initInt64(@intCast(zig_dom.zig_dom_node_type(node_handle)));
}

fn jsNodeOwnerDocument(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const node_handle = parseHandleArg(ctx, args, 0, "nodeOwnerDocument") orelse return quickjs.Value.exception;
    var out_document: u64 = 0;
    const status = zig_dom.zig_dom_node_owner_document(node_handle, &out_document);
    if (status != 0) {
        return throwStatus(ctx, "nodeOwnerDocument", status);
    }
    return quickjs.Value.initInt64(@intCast(out_document));
}

fn jsNodeParent(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const node_handle = parseHandleArg(ctx, args, 0, "nodeParent") orelse return quickjs.Value.exception;
    return quickjs.Value.initInt64(@intCast(zig_dom.zig_dom_node_parent(node_handle)));
}

fn jsNodeFirstChild(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const node_handle = parseHandleArg(ctx, args, 0, "nodeFirstChild") orelse return quickjs.Value.exception;
    return quickjs.Value.initInt64(@intCast(zig_dom.zig_dom_node_first_child(node_handle)));
}

fn jsNodeLastChild(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const node_handle = parseHandleArg(ctx, args, 0, "nodeLastChild") orelse return quickjs.Value.exception;
    return quickjs.Value.initInt64(@intCast(zig_dom.zig_dom_node_last_child(node_handle)));
}

fn jsNodePreviousSibling(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const node_handle = parseHandleArg(ctx, args, 0, "nodePreviousSibling") orelse return quickjs.Value.exception;
    return quickjs.Value.initInt64(@intCast(zig_dom.zig_dom_node_previous_sibling(node_handle)));
}

fn jsNodeNextSibling(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const node_handle = parseHandleArg(ctx, args, 0, "nodeNextSibling") orelse return quickjs.Value.exception;
    return quickjs.Value.initInt64(@intCast(zig_dom.zig_dom_node_next_sibling(node_handle)));
}

fn jsNodeContains(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const ancestor_handle = parseHandleArg(ctx, args, 0, "nodeContains") orelse return quickjs.Value.exception;
    const node_handle = parseHandleArg(ctx, args, 1, "nodeContains") orelse return quickjs.Value.exception;
    return quickjs.Value.initBool(zig_dom.zig_dom_node_contains(ancestor_handle, node_handle) == 1);
}

fn jsNodeName(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const node_handle = parseHandleArg(ctx, args, 0, "nodeName") orelse return quickjs.Value.exception;
    return nodeNameToJs(ctx, node_handle, "nodeName");
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

fn jsNodeAppendFragment(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const parent_handle = parseHandleArg(ctx, args, 0, "nodeAppendFragment") orelse return quickjs.Value.exception;
    const fragment_handle = parseHandleArg(ctx, args, 1, "nodeAppendFragment") orelse return quickjs.Value.exception;

    const status = zig_dom.zig_dom_node_append_fragment(parent_handle, fragment_handle);
    if (status != 0) {
        return throwStatus(ctx, "nodeAppendFragment", status);
    }

    return quickjs.Value.initInt64(@intCast(fragment_handle));
}

fn jsNodeInsertBefore(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const parent_handle = parseHandleArg(ctx, args, 0, "nodeInsertBefore") orelse return quickjs.Value.exception;
    const child_handle = parseHandleArg(ctx, args, 1, "nodeInsertBefore") orelse return quickjs.Value.exception;
    const reference_handle = parseOptionalHandleArg(ctx, args, 2, "nodeInsertBefore") orelse return quickjs.Value.exception;

    const status = zig_dom.zig_dom_node_insert_before(parent_handle, child_handle, reference_handle);
    if (status != 0) {
        return throwStatus(ctx, "nodeInsertBefore", status);
    }

    return quickjs.Value.initInt64(@intCast(child_handle));
}

fn jsNodeRemoveChild(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const parent_handle = parseHandleArg(ctx, args, 0, "nodeRemoveChild") orelse return quickjs.Value.exception;
    const child_handle = parseHandleArg(ctx, args, 1, "nodeRemoveChild") orelse return quickjs.Value.exception;
    const status = zig_dom.zig_dom_node_remove_child(parent_handle, child_handle);
    if (status != 0) {
        return throwStatus(ctx, "nodeRemoveChild", status);
    }

    return quickjs.Value.initInt64(@intCast(child_handle));
}

fn jsNodeReplaceChild(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const parent_handle = parseHandleArg(ctx, args, 0, "nodeReplaceChild") orelse return quickjs.Value.exception;
    const new_child_handle = parseHandleArg(ctx, args, 1, "nodeReplaceChild") orelse return quickjs.Value.exception;
    const old_child_handle = parseHandleArg(ctx, args, 2, "nodeReplaceChild") orelse return quickjs.Value.exception;
    const status = zig_dom.zig_dom_node_replace_child(parent_handle, new_child_handle, old_child_handle);
    if (status != 0) {
        return throwStatus(ctx, "nodeReplaceChild", status);
    }

    return quickjs.Value.initInt64(@intCast(old_child_handle));
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

fn jsNodeOuterHtml(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const node_handle = parseHandleArg(ctx, args, 0, "nodeOuterHtml") orelse return quickjs.Value.exception;
    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_outer_html(node_handle, &out_ptr, &out_len);
    if (status != 0) {
        return throwStatus(ctx, "nodeOuterHtml", status);
    }
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);

    if (out_ptr == null or out_len == 0) {
        return quickjs.Value.initStringLen(ctx, "");
    }

    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
}

fn jsNodeSetInnerHtml(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const node_handle = parseHandleArg(ctx, args, 0, "nodeSetInnerHtml") orelse return quickjs.Value.exception;
    const html_value = parseStringArg(ctx, args, 1, "nodeSetInnerHtml") orelse return quickjs.Value.exception;
    defer ctx.freeCString(html_value.ptr);

    const status = zig_dom.zig_dom_node_set_inner_html(node_handle, html_value.ptr, html_value.len);
    if (status != 0) {
        return throwStatus(ctx, "nodeSetInnerHtml", status);
    }

    return quickjs.Value.initInt64(0);
}

fn jsNodeQuerySelector(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const root_handle = parseHandleArg(ctx, args, 0, "nodeQuerySelector") orelse return quickjs.Value.exception;
    const selector_value = parseStringArg(ctx, args, 1, "nodeQuerySelector") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector_value.ptr);

    var out_handle: u64 = 0;
    const status = zig_dom.zig_dom_node_query_selector(root_handle, selector_value.ptr, selector_value.len, &out_handle);
    if (status != 0) {
        return throwStatus(ctx, "nodeQuerySelector", status);
    }

    return quickjs.Value.initInt64(@intCast(out_handle));
}

fn jsNodeQuerySelectorAll(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const root_handle = parseHandleArg(ctx, args, 0, "nodeQuerySelectorAll") orelse return quickjs.Value.exception;
    const selector_value = parseStringArg(ctx, args, 1, "nodeQuerySelectorAll") orelse return quickjs.Value.exception;
    defer ctx.freeCString(selector_value.ptr);

    var out_ptr: [*c]u64 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_node_query_selector_all(root_handle, selector_value.ptr, selector_value.len, &out_ptr, &out_len);
    if (status != 0) {
        return throwStatus(ctx, "nodeQuerySelectorAll", status);
    }
    defer zig_dom.zig_dom_free_handle_array(out_ptr, out_len);

    return handleArrayToJs(ctx, out_ptr, out_len);
}

fn jsElementGetAttribute(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const element_handle = parseHandleArg(ctx, args, 0, "elementGetAttribute") orelse return quickjs.Value.exception;
    const name_value = parseStringArg(ctx, args, 1, "elementGetAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name_value.ptr);

    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    var out_exists: u8 = 0;
    const status = zig_dom.zig_dom_element_get_attribute(element_handle, name_value.ptr, name_value.len, &out_ptr, &out_len, &out_exists);
    if (status != 0) {
        return throwStatus(ctx, "elementGetAttribute", status);
    }
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);

    if (out_exists == 0) {
        return quickjs.Value.null;
    }
    if (out_ptr == null or out_len == 0) {
        return quickjs.Value.initStringLen(ctx, "");
    }

    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
}

fn jsElementSetAttribute(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const element_handle = parseHandleArg(ctx, args, 0, "elementSetAttribute") orelse return quickjs.Value.exception;
    const name_value = parseStringArg(ctx, args, 1, "elementSetAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name_value.ptr);
    const attr_value = parseStringArg(ctx, args, 2, "elementSetAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(attr_value.ptr);

    const status = zig_dom.zig_dom_element_set_attribute(element_handle, name_value.ptr, name_value.len, attr_value.ptr, attr_value.len);
    if (status != 0) {
        return throwStatus(ctx, "elementSetAttribute", status);
    }

    return quickjs.Value.initInt64(0);
}

fn jsElementRemoveAttribute(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const element_handle = parseHandleArg(ctx, args, 0, "elementRemoveAttribute") orelse return quickjs.Value.exception;
    const name_value = parseStringArg(ctx, args, 1, "elementRemoveAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name_value.ptr);

    const status = zig_dom.zig_dom_element_remove_attribute(element_handle, name_value.ptr, name_value.len);
    if (status != 0) {
        return throwStatus(ctx, "elementRemoveAttribute", status);
    }

    return quickjs.Value.initInt64(0);
}

fn jsElementHasAttribute(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const element_handle = parseHandleArg(ctx, args, 0, "elementHasAttribute") orelse return quickjs.Value.exception;
    const name_value = parseStringArg(ctx, args, 1, "elementHasAttribute") orelse return quickjs.Value.exception;
    defer ctx.freeCString(name_value.ptr);

    return quickjs.Value.initBool(zig_dom.zig_dom_element_has_attribute(element_handle, name_value.ptr, name_value.len) == 1);
}

fn jsElementAttributesJson(ctx_opt: ?*quickjs.Context, _: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);

    const element_handle = parseHandleArg(ctx, args, 0, "elementAttributesJson") orelse return quickjs.Value.exception;
    var out_ptr: [*c]u8 = null;
    var out_len: usize = 0;
    const status = zig_dom.zig_dom_element_attributes_json(element_handle, &out_ptr, &out_len);
    if (status != 0) {
        return throwStatus(ctx, "elementAttributesJson", status);
    }
    defer zig_dom.zig_dom_free_string(out_ptr, out_len);

    if (out_ptr == null or out_len == 0) {
        return quickjs.Value.initStringLen(ctx, "[]");
    }

    const text = @as([*]const u8, @ptrCast(out_ptr))[0..out_len];
    return quickjs.Value.initStringLen(ctx, text);
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

fn parseOptionalHandleArg(ctx: *quickjs.Context, args: []const quickjs.Value, index: usize, operation: []const u8) ?u64 {
    if (index >= args.len) {
        return 0;
    }

    if (args[index].isUndefined() or args[index].isNull()) {
        return 0;
    }

    const handle_i64 = args[index].toInt64(ctx) catch {
        _ = throwOperationMessage(ctx, operation, "handle must be numeric");
        return null;
    };
    if (handle_i64 < 0) {
        _ = throwOperationMessage(ctx, operation, "handle must be non-negative");
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

fn handleArrayToJs(ctx: *quickjs.Context, out_ptr: [*c]u64, out_len: usize) quickjs.Value {
    const array = quickjs.Value.initArray(ctx);
    if (array.isException()) {
        return quickjs.Value.exception;
    }

    if (out_ptr == null or out_len == 0) {
        return array;
    }

    const handles = @as([*]const u64, @ptrCast(out_ptr))[0..out_len];
    for (handles, 0..) |handle, index| {
        array.setPropertyUint32(ctx, @intCast(index), quickjs.Value.initInt64(@intCast(handle))) catch {
            array.deinit(ctx);
            return throwOperationMessage(ctx, "handleArrayToJs", "failed to set array element");
        };
    }

    return array;
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

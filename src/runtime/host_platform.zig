const std = @import("std");
const quickjs = @import("quickjs");

pub const PlatformError = error{
    JSError,
};

pub fn install(ctx: *quickjs.Context) PlatformError!void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    try installConsole(ctx, global);
    try installLocation(ctx, global);
    try installNavigator(ctx, global);
    try installProcess(ctx, global);
    try installImportMetaEnv(ctx, global);
    try installGlobals(ctx, global);
    try installTimers(ctx, global);
    try installMatchMedia(ctx, global);
    try installKeyboardEvent(ctx, global);
    try installUrl(ctx, global);
    try installIntl(ctx, global);
    try installDomParser(ctx, global);
    try installImportMetaRequire(ctx, global);
    try installStorage(ctx, global);
}

pub fn linkWindow(ctx: *quickjs.Context) PlatformError!void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const window = global.getPropertyStr(ctx, "window");
    defer window.deinit(ctx);
    if (window.isException() or window.isUndefined() or window.isNull() or !window.isObject()) return;

    try linkWindowProperty(ctx, global, window, "location");
    try linkWindowProperty(ctx, global, window, "navigator");
    try linkWindowProperty(ctx, global, window, "matchMedia");
    try linkWindowProperty(ctx, global, window, "KeyboardEvent");
    try linkWindowProperty(ctx, global, window, "URL");
    try linkWindowProperty(ctx, global, window, "URLSearchParams");
    try linkWindowProperty(ctx, global, window, "Intl");
    try linkWindowProperty(ctx, global, window, "DOMParser");
    try linkWindowProperty(ctx, global, window, "localStorage");
    try linkWindowProperty(ctx, global, window, "sessionStorage");
    try linkWindowProperty(ctx, global, window, "queueMicrotask");
    try linkWindowProperty(ctx, global, window, "setTimeout");
    try linkWindowProperty(ctx, global, window, "clearTimeout");
    try linkWindowProperty(ctx, global, window, "setInterval");
    try linkWindowProperty(ctx, global, window, "clearInterval");
    try linkWindowProperty(ctx, global, window, "setImmediate");
    try linkWindowProperty(ctx, global, window, "clearImmediate");
}

fn linkWindowProperty(ctx: *quickjs.Context, global: quickjs.Value, window: quickjs.Value, comptime name: [:0]const u8) PlatformError!void {
    const existing = window.getPropertyStr(ctx, name);
    defer existing.deinit(ctx);
    if (!existing.isUndefined() and !existing.isNull()) return;

    const value = global.getPropertyStr(ctx, name);
    defer value.deinit(ctx);
    if (value.isException() or value.isUndefined() or value.isNull()) return;
    window.setPropertyStr(ctx, name, value.dup(ctx)) catch return error.JSError;
}

fn installConsole(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "console");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const console = quickjs.Value.initObject(ctx);
    if (console.isException()) return error.JSError;
    errdefer console.deinit(ctx);

    inline for (.{ "assert", "clear", "debug", "error", "info", "log", "trace", "warn" }) |name| {
        try setFunction(ctx, console, name, jsNoop, 0);
    }

    global.setPropertyStr(ctx, "console", console) catch return error.JSError;
}

fn installLocation(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "location");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const location = quickjs.Value.initObject(ctx);
    if (location.isException()) return error.JSError;
    errdefer location.deinit(ctx);

    try setString(ctx, location, "href", "http://localhost/");
    try setString(ctx, location, "protocol", "http:");
    try setString(ctx, location, "host", "localhost");
    try setString(ctx, location, "hostname", "localhost");
    try setString(ctx, location, "port", "");
    try setString(ctx, location, "pathname", "/");
    try setString(ctx, location, "search", "");
    try setString(ctx, location, "hash", "");

    global.setPropertyStr(ctx, "location", location) catch return error.JSError;
}

fn installNavigator(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "navigator");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const navigator = quickjs.Value.initObject(ctx);
    if (navigator.isException()) return error.JSError;
    errdefer navigator.deinit(ctx);
    try setString(ctx, navigator, "userAgent", "zig-dom");

    global.setPropertyStr(ctx, "navigator", navigator) catch return error.JSError;
}

fn installProcess(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    var process = global.getPropertyStr(ctx, "process");
    defer process.deinit(ctx);
    if (process.isException() or process.isUndefined() or process.isNull() or !process.isObject()) {
        process.deinit(ctx);
        process = quickjs.Value.initObject(ctx);
        if (process.isException()) return error.JSError;
        global.setPropertyStr(ctx, "process", process.dup(ctx)) catch return error.JSError;
    }

    var env = process.getPropertyStr(ctx, "env");
    defer env.deinit(ctx);
    if (env.isException() or env.isUndefined() or env.isNull() or !env.isObject()) {
        env.deinit(ctx);
        env = quickjs.Value.initObject(ctx);
        if (env.isException()) return error.JSError;
        process.setPropertyStr(ctx, "env", env.dup(ctx)) catch return error.JSError;
    }
    try setString(ctx, env, "ZIG_DOM_SKIP_TESTING_LIBRARY", "1");

    const argv = quickjs.Value.initArray(ctx);
    if (argv.isException()) return error.JSError;
    process.setPropertyStr(ctx, "argv", argv) catch return error.JSError;
    try setString(ctx, process, "platform", "darwin");
    try setString(ctx, process, "arch", "arm64");
    try setFunction(ctx, process, "cwd", jsProcessCwd, 0);
}

fn installImportMetaEnv(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "__zigImportMetaEnv");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const env = quickjs.Value.initObject(ctx);
    if (env.isException()) return error.JSError;
    errdefer env.deinit(ctx);
    env.setPropertyStr(ctx, "DEV", quickjs.Value.initBool(false)) catch return error.JSError;
    env.setPropertyStr(ctx, "PROD", quickjs.Value.initBool(false)) catch return error.JSError;
    try setString(ctx, env, "VITE_LEGACY", "false");
    try setString(ctx, env, "VITE_PLAYWRIGHT_TEST", "false");

    global.setPropertyStr(ctx, "__zigImportMetaEnv", env) catch return error.JSError;
}

fn installGlobals(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    global.setPropertyStr(ctx, "global", global.dup(ctx)) catch return error.JSError;
}

fn installTimers(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    try setFunctionIfMissing(ctx, global, "queueMicrotask", jsCallFirstArg, 1);
    try setFunctionIfMissing(ctx, global, "setTimeout", jsCallFirstArg, 1);
    try setFunctionIfMissing(ctx, global, "setInterval", jsCallFirstArg, 1);
    try setFunctionIfMissing(ctx, global, "setImmediate", jsCallFirstArg, 1);
    try setFunctionIfMissing(ctx, global, "clearTimeout", jsNoop, 1);
    try setFunctionIfMissing(ctx, global, "clearInterval", jsNoop, 1);
    try setFunctionIfMissing(ctx, global, "clearImmediate", jsNoop, 1);
}

fn setFunctionIfMissing(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) PlatformError!void {
    const current = object.getPropertyStr(ctx, name);
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;
    try setFunction(ctx, object, name, func, arg_count);
}

fn installMatchMedia(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "matchMedia");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;
    try setFunction(ctx, global, "matchMedia", jsMatchMedia, 1);
}

fn installKeyboardEvent(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "KeyboardEvent");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const ctor = quickjs.Value.initCFunction2(ctx, jsKeyboardEventCtor, "KeyboardEvent", 1, .constructor_or_func, 0);
    if (ctor.isException()) return error.JSError;
    global.setPropertyStr(ctx, "KeyboardEvent", ctor) catch return error.JSError;
}

fn installUrl(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const params_current = global.getPropertyStr(ctx, "URLSearchParams");
    defer params_current.deinit(ctx);
    if (params_current.isUndefined() or params_current.isNull()) {
        const params_ctor = quickjs.Value.initCFunction2(ctx, jsUrlSearchParamsCtor, "URLSearchParams", 1, .constructor_or_func, 0);
        if (params_ctor.isException()) return error.JSError;
        global.setPropertyStr(ctx, "URLSearchParams", params_ctor) catch return error.JSError;
    }

    const current = global.getPropertyStr(ctx, "URL");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const ctor = quickjs.Value.initCFunction2(ctx, jsUrlCtor, "URL", 1, .constructor_or_func, 0);
    if (ctor.isException()) return error.JSError;
    global.setPropertyStr(ctx, "URL", ctor) catch return error.JSError;
}

fn installIntl(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    var intl = global.getPropertyStr(ctx, "Intl");
    defer intl.deinit(ctx);
    if (intl.isException() or intl.isUndefined() or intl.isNull() or !intl.isObject()) {
        intl.deinit(ctx);
        intl = quickjs.Value.initObject(ctx);
        if (intl.isException()) return error.JSError;
        global.setPropertyStr(ctx, "Intl", intl.dup(ctx)) catch return error.JSError;
    }

    const current = intl.getPropertyStr(ctx, "Collator");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const ctor = quickjs.Value.initCFunction2(ctx, jsCollatorCtor, "Collator", 0, .constructor_or_func, 0);
    if (ctor.isException()) return error.JSError;
    intl.setPropertyStr(ctx, "Collator", ctor) catch return error.JSError;
}

fn installDomParser(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "DOMParser");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const ctor = quickjs.Value.initCFunction2(ctx, jsDomParserCtor, "DOMParser", 0, .constructor_or_func, 0);
    if (ctor.isException()) return error.JSError;
    global.setPropertyStr(ctx, "DOMParser", ctor) catch return error.JSError;
}

fn installImportMetaRequire(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    try setFunction(ctx, global, "__zigImportMetaRequire", jsImportMetaRequire, 1);
}

fn installStorage(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    try installStorageObject(ctx, global, "localStorage");
    try installStorageObject(ctx, global, "sessionStorage");
}

fn installStorageObject(ctx: *quickjs.Context, global: quickjs.Value, comptime name: [:0]const u8) PlatformError!void {
    const current = global.getPropertyStr(ctx, name);
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const storage = quickjs.Value.initObject(ctx);
    if (storage.isException()) return error.JSError;
    errdefer storage.deinit(ctx);
    const data = quickjs.Value.initObject(ctx);
    if (data.isException()) return error.JSError;
    storage.setPropertyStr(ctx, "__zigStorageData", data) catch return error.JSError;
    storage.setPropertyStr(ctx, "length", quickjs.Value.initInt32(0)) catch return error.JSError;
    try setFunction(ctx, storage, "getItem", jsStorageGetItem, 1);
    try setFunction(ctx, storage, "setItem", jsStorageSetItem, 2);
    try setFunction(ctx, storage, "removeItem", jsStorageRemoveItem, 1);
    try setFunction(ctx, storage, "clear", jsStorageClear, 0);
    try setFunction(ctx, storage, "key", jsStorageKey, 1);

    global.setPropertyStr(ctx, name, storage) catch return error.JSError;
}

fn jsNoop(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsCallFirstArg(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (args.len == 0) return quickjs.Value.initInt32(1);
    const callback = quickjs.Value.fromCVal(args[0]);
    if (callback.isFunction(ctx)) {
        var call_args_buf: [8]quickjs.Value = undefined;
        const count = @min(args.len - 1, call_args_buf.len);
        for (0..count) |index| {
            call_args_buf[index] = quickjs.Value.fromCVal(args[index + 1]).dup(ctx);
        }
        defer for (call_args_buf[0..count]) |value| value.deinit(ctx);
        const result = callback.call(ctx, quickjs.Value.undefined, call_args_buf[0..count]);
        defer result.deinit(ctx);
        if (result.isException()) return quickjs.Value.exception;
    }
    return quickjs.Value.initInt32(1);
}

fn jsProcessCwd(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    return quickjs.Value.initStringLen(ctx, "/");
}

fn jsMatchMedia(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const query = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (query) |text| ctx.freeCString(text.ptr);

    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "media", quickjs.Value.initStringLen(ctx, if (query) |text| text.ptr[0..text.len] else "")) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "matches", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "onchange", quickjs.Value.null) catch return quickjs.Value.exception;
    inline for (.{ "addListener", "removeListener", "addEventListener", "removeEventListener" }) |name| {
        setFunction(ctx, obj, name, jsNoop, 0) catch return quickjs.Value.exception;
    }
    setFunction(ctx, obj, "dispatchEvent", jsReturnFalse, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsReturnFalse(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.initBool(false);
}

fn jsKeyboardEventCtor(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = if (this_value.isUndefined() or this_value.isNull()) quickjs.Value.initObject(ctx) else this_value.dup(ctx);
    if (obj.isException()) return quickjs.Value.exception;

    const type_text = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (type_text) |text| ctx.freeCString(text.ptr);
    obj.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, if (type_text) |text| text.ptr[0..text.len] else "")) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    if (args.len > 1) {
        const init = quickjs.Value.fromCVal(args[1]);
        inline for (.{ "key", "code", "ctrlKey", "shiftKey", "altKey", "metaKey" }) |name| {
            const value = init.getPropertyStr(ctx, name);
            defer value.deinit(ctx);
            if (!value.isException() and !value.isUndefined()) {
                obj.setPropertyStr(ctx, name, value.dup(ctx)) catch return quickjs.Value.exception;
            }
        }
    }
    return obj;
}

fn jsUrlSearchParamsCtor(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = if (this_value.isUndefined() or this_value.isNull()) quickjs.Value.initObject(ctx) else this_value.dup(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (input) |text| ctx.freeCString(text.ptr);
    const raw = if (input) |text| text.ptr[0..text.len] else "";
    initUrlSearchParamsObject(ctx, obj, raw) catch return quickjs.Value.exception;
    return obj;
}

fn initUrlSearchParamsObject(ctx: *quickjs.Context, obj: quickjs.Value, raw: []const u8) PlatformError!void {
    obj.setPropertyStr(ctx, "__zigRawSearch", quickjs.Value.initStringLen(ctx, if (std.mem.startsWith(u8, raw, "?")) raw[1..] else raw)) catch return error.JSError;
    setFunction(ctx, obj, "get", jsUrlSearchParamsGet, 1) catch return error.JSError;
    setFunction(ctx, obj, "delete", jsUrlSearchParamsDelete, 1) catch return error.JSError;
    setFunction(ctx, obj, "toString", jsUrlSearchParamsToString, 0) catch return error.JSError;
}

fn jsUrlSearchParamsGet(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const key = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (key) |text| ctx.freeCString(text.ptr);
    const raw_value = this_value.getPropertyStr(ctx, "__zigRawSearch");
    defer raw_value.deinit(ctx);
    const raw = raw_value.toCStringLen(ctx) orelse return quickjs.Value.null;
    defer ctx.freeCString(raw.ptr);
    if (key) |lookup| {
        var it = std.mem.splitScalar(u8, raw.ptr[0..raw.len], '&');
        while (it.next()) |part| {
            const eq = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
            if (std.mem.eql(u8, part[0..eq], lookup.ptr[0..lookup.len])) {
                const value = if (eq < part.len) part[eq + 1 ..] else "";
                return quickjs.Value.initStringLen(ctx, value);
            }
        }
    }
    return quickjs.Value.null;
}

fn jsUrlSearchParamsDelete(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "__zigRawSearch", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsUrlSearchParamsToString(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const raw = this_value.getPropertyStr(ctx, "__zigRawSearch");
    if (raw.isException()) return quickjs.Value.initStringLen(ctx, "");
    return raw;
}

fn jsUrlCtor(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = if (this_value.isUndefined() or this_value.isNull()) quickjs.Value.initObject(ctx) else this_value.dup(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (input) |text| ctx.freeCString(text.ptr);
    const href = if (input) |text| text.ptr[0..text.len] else "";
    const protocol_end = std.mem.indexOf(u8, href, "://");
    const protocol = if (protocol_end) |index| href[0 .. index + 1] else "";
    const after_protocol = if (protocol_end) |index| href[index + 3 ..] else href;
    const path_start = std.mem.indexOfAny(u8, after_protocol, "/?#") orelse after_protocol.len;
    const host = after_protocol[0..path_start];
    const rest = after_protocol[path_start..];
    const hash_start = std.mem.indexOfScalar(u8, rest, '#') orelse rest.len;
    const before_hash = rest[0..hash_start];
    const hash = if (hash_start < rest.len) rest[hash_start..] else "";
    const search_start = std.mem.indexOfScalar(u8, before_hash, '?') orelse before_hash.len;
    const pathname = if (search_start > 0) before_hash[0..search_start] else "/";
    const search = if (search_start < before_hash.len) before_hash[search_start..] else "";
    const hostname_end = std.mem.indexOfScalar(u8, host, ':') orelse host.len;

    obj.setPropertyStr(ctx, "href", quickjs.Value.initStringLen(ctx, href)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "protocol", quickjs.Value.initStringLen(ctx, protocol)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "host", quickjs.Value.initStringLen(ctx, host)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "hostname", quickjs.Value.initStringLen(ctx, host[0..hostname_end])) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "pathname", quickjs.Value.initStringLen(ctx, pathname)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "search", quickjs.Value.initStringLen(ctx, search)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "hash", quickjs.Value.initStringLen(ctx, hash)) catch return quickjs.Value.exception;
    const origin = if (protocol.len > 0 and host.len > 0) href[0 .. (protocol.len + 2 + host.len)] else "";
    obj.setPropertyStr(ctx, "origin", quickjs.Value.initStringLen(ctx, origin)) catch return quickjs.Value.exception;
    const params = quickjs.Value.initObject(ctx);
    if (params.isException()) return quickjs.Value.exception;
    initUrlSearchParamsObject(ctx, params, search) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "searchParams", params) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "toString", jsUrlToString, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsUrlToString(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const href = this_value.getPropertyStr(ctx, "href");
    if (href.isException()) return quickjs.Value.initStringLen(ctx, "");
    return href;
}

fn jsCollatorCtor(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = if (this_value.isUndefined() or this_value.isNull()) quickjs.Value.initObject(ctx) else this_value.dup(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    setFunction(ctx, obj, "compare", jsCollatorCompare, 2) catch return quickjs.Value.exception;
    return obj;
}

fn jsCollatorCompare(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const left = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (left) |text| ctx.freeCString(text.ptr);
    const right = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toCStringLen(ctx) else null;
    defer if (right) |text| ctx.freeCString(text.ptr);
    const left_slice = if (left) |text| text.ptr[0..text.len] else "";
    const right_slice = if (right) |text| text.ptr[0..text.len] else "";
    const order: i32 = switch (std.mem.order(u8, left_slice, right_slice)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
    return quickjs.Value.initInt32(order);
}

fn jsDomParserCtor(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = if (this_value.isUndefined() or this_value.isNull()) quickjs.Value.initObject(ctx) else this_value.dup(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    setFunction(ctx, obj, "parseFromString", jsDomParserParseFromString, 1) catch return quickjs.Value.exception;
    return obj;
}

fn jsDomParserParseFromString(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (input) |text| ctx.freeCString(text.ptr);
    const html = if (input) |text| text.ptr[0..text.len] else "";
    const parsed = quickjs.Value.initObject(ctx);
    if (parsed.isException()) return quickjs.Value.exception;
    const body = quickjs.Value.initObject(ctx);
    if (body.isException()) return quickjs.Value.exception;
    body.setPropertyStr(ctx, "innerHTML", quickjs.Value.initStringLen(ctx, html)) catch return quickjs.Value.exception;
    body.setPropertyStr(ctx, "textContent", quickjs.Value.initStringLen(ctx, html)) catch return quickjs.Value.exception;
    parsed.setPropertyStr(ctx, "body", body) catch return quickjs.Value.exception;
    return parsed;
}

fn jsImportMetaRequire(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const raw = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (raw) |text| ctx.freeCString(text.ptr);
    const specifier = if (raw) |text| text.ptr[0..text.len] else "";
    const normalized = if (std.mem.startsWith(u8, specifier, "node:")) specifier[5..] else specifier;

    if (std.mem.eql(u8, normalized, "path")) return pathBuiltin(ctx);
    if (std.mem.eql(u8, normalized, "fs")) return fsBuiltin(ctx);
    if (std.mem.eql(u8, normalized, "util")) return utilBuiltin(ctx);
    if (std.mem.eql(u8, normalized, "url")) return urlBuiltin(ctx);
    if (std.mem.eql(u8, normalized, "buffer")) return bufferBuiltin(ctx);
    if (std.mem.eql(u8, normalized, "events")) return eventEmitterBuiltin(ctx);

    return unsupportedBuiltin(ctx, specifier);
}

fn jsStorageGetItem(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const key = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (key) |text| ctx.freeCString(text.ptr);
    const data = this_value.getPropertyStr(ctx, "__zigStorageData");
    defer data.deinit(ctx);
    if (data.isException() or data.isUndefined()) return quickjs.Value.null;
    if (key) |text| {
        const value = data.getPropertyStr(ctx, text.ptr);
        if (value.isException() or value.isUndefined()) {
            value.deinit(ctx);
            return quickjs.Value.null;
        }
        return value;
    }
    return quickjs.Value.null;
}

fn jsStorageSetItem(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const key = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (key) |text| ctx.freeCString(text.ptr);
    const value = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toCStringLen(ctx) else null;
    defer if (value) |text| ctx.freeCString(text.ptr);
    const data = this_value.getPropertyStr(ctx, "__zigStorageData");
    defer data.deinit(ctx);
    if (data.isException() or data.isUndefined()) return quickjs.Value.exception;
    if (key) |key_text| {
        const existing = data.getPropertyStr(ctx, key_text.ptr);
        defer existing.deinit(ctx);
        if (existing.isUndefined()) {
            const length = this_value.getPropertyStr(ctx, "length");
            defer length.deinit(ctx);
            const next = (length.toInt32(ctx) catch 0) + 1;
            this_value.setPropertyStr(ctx, "length", quickjs.Value.initInt32(next)) catch return quickjs.Value.exception;
        }
        data.setPropertyStr(ctx, key_text.ptr, quickjs.Value.initStringLen(ctx, if (value) |value_text| value_text.ptr[0..value_text.len] else "")) catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsStorageRemoveItem(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const key = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (key) |text| ctx.freeCString(text.ptr);
    const data = this_value.getPropertyStr(ctx, "__zigStorageData");
    defer data.deinit(ctx);
    if (data.isException() or data.isUndefined()) return quickjs.Value.undefined;
    if (key) |key_text| {
        const existing = data.getPropertyStr(ctx, key_text.ptr);
        defer existing.deinit(ctx);
        if (!existing.isUndefined()) {
            _ = data.deletePropertyStr(ctx, key_text.ptr) catch {};
            const length = this_value.getPropertyStr(ctx, "length");
            defer length.deinit(ctx);
            const current = length.toInt32(ctx) catch 0;
            this_value.setPropertyStr(ctx, "length", quickjs.Value.initInt32(@max(0, current - 1))) catch return quickjs.Value.exception;
        }
    }
    return quickjs.Value.undefined;
}

fn jsStorageClear(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const data = quickjs.Value.initObject(ctx);
    if (data.isException()) return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "__zigStorageData", data) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "length", quickjs.Value.initInt32(0)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsStorageKey(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.null;
}

fn pathBuiltin(ctx: *quickjs.Context) quickjs.Value {
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    setFunction(ctx, obj, "join", jsPathJoin, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "resolve", jsPathJoin, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "dirname", jsPathDirname, 1) catch return quickjs.Value.exception;
    return obj;
}

fn fsBuiltin(ctx: *quickjs.Context) quickjs.Value {
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    setFunction(ctx, obj, "readFileSync", jsUnsupportedFunction, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "writeFileSync", jsUnsupportedFunction, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "existsSync", jsReturnFalse, 0) catch return quickjs.Value.exception;
    return obj;
}

fn utilBuiltin(ctx: *quickjs.Context) quickjs.Value {
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    setFunction(ctx, obj, "inspect", jsStringifyFirstArg, 1) catch return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    inline for (.{ "TextEncoder", "TextDecoder" }) |name| {
        const value = global.getPropertyStr(ctx, name);
        defer value.deinit(ctx);
        if (!value.isException() and !value.isUndefined()) obj.setPropertyStr(ctx, name, value.dup(ctx)) catch return quickjs.Value.exception;
    }
    return obj;
}

fn urlBuiltin(ctx: *quickjs.Context) quickjs.Value {
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    inline for (.{ "URL", "URLSearchParams" }) |name| {
        const value = global.getPropertyStr(ctx, name);
        defer value.deinit(ctx);
        if (!value.isException() and !value.isUndefined()) obj.setPropertyStr(ctx, name, value.dup(ctx)) catch return quickjs.Value.exception;
    }
    return obj;
}

fn bufferBuiltin(ctx: *quickjs.Context) quickjs.Value {
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    inline for (.{ "Buffer", "Blob" }) |name| {
        const value = global.getPropertyStr(ctx, name);
        defer value.deinit(ctx);
        if (!value.isException() and !value.isUndefined()) obj.setPropertyStr(ctx, name, value.dup(ctx)) catch return quickjs.Value.exception;
    }
    return obj;
}

fn eventEmitterBuiltin(ctx: *quickjs.Context) quickjs.Value {
    const ctor = quickjs.Value.initCFunction2(ctx, jsEventEmitterCtor, "EventEmitter", 0, .constructor_or_func, 0);
    if (ctor.isException()) return quickjs.Value.exception;
    ctor.setPropertyStr(ctx, "EventEmitter", ctor.dup(ctx)) catch return quickjs.Value.exception;
    return ctor;
}

fn unsupportedBuiltin(ctx: *quickjs.Context, specifier: []const u8) quickjs.Value {
    _ = specifier;
    return ctx.throwInternalError("import.meta.require() unsupported module");
}

fn jsPathJoin(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.heap.c_allocator);
    for (args, 0..) |arg, index| {
        const text = quickjs.Value.fromCVal(arg).toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(text.ptr);
        if (text.len == 0) continue;
        if (index > 0 and out.items.len > 0 and out.items[out.items.len - 1] != '/') out.append(std.heap.c_allocator, '/') catch return quickjs.Value.exception;
        out.appendSlice(std.heap.c_allocator, text.ptr[0..text.len]) catch return quickjs.Value.exception;
    }
    return quickjs.Value.initStringLen(ctx, out.items);
}

fn jsPathDirname(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const text = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (text) |value| ctx.freeCString(value.ptr);
    const input = if (text) |value| value.ptr[0..value.len] else "";
    const index = std.mem.lastIndexOfScalar(u8, input, '/') orelse return quickjs.Value.initStringLen(ctx, ".");
    if (index == 0) return quickjs.Value.initStringLen(ctx, ".");
    return quickjs.Value.initStringLen(ctx, input[0..index]);
}

fn jsUnsupportedFunction(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    return ctx.throwInternalError("Unsupported builtin function");
}

fn jsStringifyFirstArg(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (args.len == 0) return quickjs.Value.initStringLen(ctx, "");
    const value = quickjs.Value.fromCVal(args[0]).toStringValue(ctx);
    return value;
}

fn jsEventEmitterCtor(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = if (this_value.isUndefined() or this_value.isNull()) quickjs.Value.initObject(ctx) else this_value.dup(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    setFunction(ctx, obj, "on", jsReturnThis, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "once", jsReturnThis, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "removeListener", jsReturnThis, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "emit", jsReturnFalse, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "listenerCount", jsReturnZero, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsReturnThis(_: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return this_value;
}

fn jsReturnZero(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.initInt32(0);
}

fn setString(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, value: []const u8) PlatformError!void {
    object.setPropertyStr(ctx, name, quickjs.Value.initStringLen(ctx, value)) catch return error.JSError;
}

fn setFunction(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) PlatformError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

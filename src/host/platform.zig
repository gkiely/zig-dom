const std = @import("std");
const quickjs = @import("quickjs");
const c_allocator = std.heap.c_allocator;

pub const PlatformError = error{
    JSError,
};

const NativeTimerKind = enum {
    timeout,
    interval,
    immediate,
};

const NativeTimer = struct {
    id: i32,
    kind: NativeTimerKind,
    callback: quickjs.Value,
    args: std.ArrayListUnmanaged(quickjs.Value) = .empty,
    remaining_turns: u32,
    interval_turns: u32,

    fn deinit(self: *NativeTimer, ctx: *quickjs.Context) void {
        self.callback.deinit(ctx);
        for (self.args.items) |value| value.deinit(ctx);
        self.args.deinit(c_allocator);
    }
};

var native_timer_ctx: ?*quickjs.Context = null;
var native_timers: std.ArrayListUnmanaged(NativeTimer) = .empty;
var native_next_timer_id: i32 = 1;
var crypto_uuid_counter: u64 = 0;
var crypto_uuid_state: u64 = 0xA409_3822_299F_31D0;
var object_url_counter: u64 = 0;

pub fn reset(ctx: *quickjs.Context) void {
    if (native_timer_ctx != ctx) return;
    clearNativeTimers(ctx);
    native_timer_ctx = null;
    native_next_timer_id = 1;
    crypto_uuid_counter = 0;
    crypto_uuid_state = 0xA409_3822_299F_31D0;
    object_url_counter = 0;
}

pub fn install(ctx: *quickjs.Context) PlatformError!void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    try installConsole(ctx, global);
    try installLocation(ctx, global);
    try installNavigator(ctx, global);
    try installProcess(ctx, global);
    try installObjectPrototypeHelpers(ctx, global);
    try installImportMetaEnv(ctx, global);
    try installGlobals(ctx, global);
    try installErrorDefaults(ctx, global);
    try installTimers(ctx, global);
    try installMatchMedia(ctx, global);
    try installKeyboardEvent(ctx, global);
    try installUrl(ctx, global);
    try installFetchApi(ctx, global);
    try installImage(ctx, global);
    try installIntl(ctx, global);
    try installCrypto(ctx, global);
    try installDateLocale(ctx, global);
    try installDomParser(ctx, global);
    try installImportMetaRequire(ctx, global);
    try installStorage(ctx, global);
    try installSymbolDisposers(ctx, global);
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
    try linkWindowProperty(ctx, global, window, "Headers");
    try linkWindowProperty(ctx, global, window, "Request");
    try linkWindowProperty(ctx, global, window, "Response");
    try linkWindowProperty(ctx, global, window, "FormData");
    try linkWindowProperty(ctx, global, window, "Blob");
    try linkWindowProperty(ctx, global, window, "File");
    try linkWindowProperty(ctx, global, window, "fetch");
    try linkWindowProperty(ctx, global, window, "Image");
    try linkWindowProperty(ctx, global, window, "Intl");
    try linkWindowProperty(ctx, global, window, "console");
    try linkWindowProperty(ctx, global, window, "history");
    try linkWindowProperty(ctx, global, window, "crypto");
    try linkWindowProperty(ctx, global, window, "DOMParser");
    try linkWindowProperty(ctx, global, window, "localStorage");
    try linkWindowProperty(ctx, global, window, "sessionStorage");
    try linkWindowProperty(ctx, global, window, "queueMicrotask");
    try linkWindowProperty(ctx, global, window, "setTimeout");
    try linkWindowProperty(ctx, global, window, "clearTimeout");
    try linkWindowProperty(ctx, global, window, "requestAnimationFrame");
    try linkWindowProperty(ctx, global, window, "cancelAnimationFrame");
    try linkWindowProperty(ctx, global, window, "setInterval");
    try linkWindowProperty(ctx, global, window, "clearInterval");
    try linkWindowProperty(ctx, global, window, "setImmediate");
    try linkWindowProperty(ctx, global, window, "clearImmediate");
    try linkWindowProperty(ctx, global, window, "MessageChannel");
    try linkWindowProperty(ctx, global, window, "scrollTo");
    try linkWindowProperty(ctx, global, window, "scrollBy");
    try linkWindowProperty(ctx, global, window, "innerWidth");
    try linkWindowProperty(ctx, global, window, "innerHeight");
    try linkWindowProperty(ctx, global, window, "outerWidth");
    try linkWindowProperty(ctx, global, window, "outerHeight");
    try linkWindowProperty(ctx, global, window, "scrollX");
    try linkWindowProperty(ctx, global, window, "scrollY");
    try linkWindowProperty(ctx, global, window, "pageXOffset");
    try linkWindowProperty(ctx, global, window, "pageYOffset");
    try linkWindowProperty(ctx, global, window, "getComputedStyle");

    // Keep global location aligned with window.location.
    // Libraries often read bare `location` instead of `window.location`.
    try syncGlobalWithWindowProperty(ctx, global, window, "location");
    try syncGlobalWithWindowProperty(ctx, global, window, "getComputedStyle");
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

fn syncGlobalWithWindowProperty(ctx: *quickjs.Context, global: quickjs.Value, window: quickjs.Value, comptime name: [:0]const u8) PlatformError!void {
    const window_value = window.getPropertyStr(ctx, name);
    defer window_value.deinit(ctx);
    if (window_value.isException() or window_value.isUndefined() or window_value.isNull()) return;
    global.setPropertyStr(ctx, name, window_value.dup(ctx)) catch return error.JSError;
}

fn installConsole(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "console");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const console = quickjs.Value.initObject(ctx);
    if (console.isException()) return error.JSError;
    errdefer console.deinit(ctx);

    try setFunction(ctx, console, "assert", jsConsoleAssert, 1);
    try setFunction(ctx, console, "clear", jsNoop, 0);
    try setFunction(ctx, console, "debug", jsConsoleLog, 1);
    try setFunction(ctx, console, "error", jsConsoleError, 1);
    try setFunction(ctx, console, "info", jsConsoleLog, 1);
    try setFunction(ctx, console, "log", jsConsoleLog, 1);
    try setFunction(ctx, console, "trace", jsConsoleTrace, 1);
    try setFunction(ctx, console, "warn", jsConsoleWarn, 1);

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
    var navigator = current;
    if (current.isUndefined() or current.isNull() or !current.isObject()) {
        navigator = quickjs.Value.initObject(ctx);
        if (navigator.isException()) return error.JSError;
        errdefer navigator.deinit(ctx);
    }

    try setString(ctx, navigator, "userAgent", "zig-dom");
    try installClipboard(ctx, navigator);

    if (current.isUndefined() or current.isNull() or !current.isObject()) {
        global.setPropertyStr(ctx, "navigator", navigator) catch return error.JSError;
    }
}

fn installClipboard(ctx: *quickjs.Context, navigator: quickjs.Value) PlatformError!void {
    const current = navigator.getPropertyStr(ctx, "clipboard");
    defer current.deinit(ctx);

    var clipboard = current;
    if (current.isUndefined() or current.isNull() or !current.isObject()) {
        clipboard = quickjs.Value.initObject(ctx);
        if (clipboard.isException()) return error.JSError;
        errdefer clipboard.deinit(ctx);
    }

    try setFunctionIfMissing(ctx, clipboard, "readText", jsClipboardReadText, 0);
    try setFunctionIfMissing(ctx, clipboard, "writeText", jsClipboardWriteText, 1);

    if (current.isUndefined() or current.isNull() or !current.isObject()) {
        navigator.setPropertyStr(ctx, "clipboard", clipboard) catch return error.JSError;
    }
}

fn installCrypto(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    var crypto = global.getPropertyStr(ctx, "crypto");
    defer crypto.deinit(ctx);
    if (crypto.isException() or crypto.isUndefined() or crypto.isNull() or !crypto.isObject()) {
        crypto.deinit(ctx);
        crypto = quickjs.Value.initObject(ctx);
        if (crypto.isException()) return error.JSError;
        global.setPropertyStr(ctx, "crypto", crypto.dup(ctx)) catch return error.JSError;
    }

    const random_uuid = crypto.getPropertyStr(ctx, "randomUUID");
    defer random_uuid.deinit(ctx);
    if (random_uuid.isException() or !random_uuid.isFunction(ctx)) {
        try setFunction(ctx, crypto, "randomUUID", jsCryptoRandomUUID, 0);
    }
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
    try setString(ctx, env, "ZIG_DOM", "1");
    const node_env = if (std.c.getenv("NODE_ENV")) |raw| std.mem.span(raw) else "test";
    try setString(ctx, env, "NODE_ENV", node_env);

    const argv = quickjs.Value.initArray(ctx);
    if (argv.isException()) return error.JSError;
    process.setPropertyStr(ctx, "argv", argv) catch return error.JSError;

    var versions = process.getPropertyStr(ctx, "versions");
    defer versions.deinit(ctx);
    if (versions.isException() or versions.isUndefined() or versions.isNull() or !versions.isObject()) {
        versions.deinit(ctx);
        versions = quickjs.Value.initObject(ctx);
        if (versions.isException()) return error.JSError;
        process.setPropertyStr(ctx, "versions", versions.dup(ctx)) catch return error.JSError;
    }
    try setString(ctx, versions, "node", "20.0.0");
    try setString(ctx, process, "version", "v20.0.0");

    try setString(ctx, process, "platform", "darwin");
    try setString(ctx, process, "arch", "arm64");
    try setFunction(ctx, process, "cwd", jsProcessCwd, 0);
}

fn installObjectPrototypeHelpers(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const object_ctor = global.getPropertyStr(ctx, "Object");
    defer object_ctor.deinit(ctx);
    if (object_ctor.isException() or !object_ctor.isObject()) return;

    const object_prototype = object_ctor.getPropertyStr(ctx, "prototype");
    defer object_prototype.deinit(ctx);
    if (object_prototype.isException() or !object_prototype.isObject()) return;

    const existing = object_prototype.getPropertyStr(ctx, "getAutoHeightDuration");
    defer existing.deinit(ctx);
    if (!existing.isException() and existing.isFunction(ctx)) return;

    try setNonEnumerableFunction(ctx, object_prototype, "getAutoHeightDuration", jsObjectGetAutoHeightDuration, 1);
}

fn installImportMetaEnv(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "__zigImportMetaEnv");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const env = quickjs.Value.initObject(ctx);
    if (env.isException()) return error.JSError;
    errdefer env.deinit(ctx);

    const process = global.getPropertyStr(ctx, "process");
    defer process.deinit(ctx);
    if (!process.isException() and process.isObject()) {
        const process_env = process.getPropertyStr(ctx, "env");
        defer process_env.deinit(ctx);
        if (!process_env.isException() and process_env.isObject()) {
            try copyImportMetaEnvEntries(ctx, env, process_env);
        }
    }

    global.setPropertyStr(ctx, "__zigImportMetaEnv", env) catch return error.JSError;
}

fn copyImportMetaEnvEntries(ctx: *quickjs.Context, target_env: quickjs.Value, source_env: quickjs.Value) PlatformError!void {
    const keys_fn = getObjectKeys(ctx) catch return error.JSError;
    defer keys_fn.deinit(ctx);

    var call_args = [_]quickjs.Value{source_env.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const keys = keys_fn.call(ctx, quickjs.Value.undefined, &call_args);
    defer keys.deinit(ctx);
    if (keys.isException()) return error.JSError;

    const length_value = keys.getPropertyStr(ctx, "length");
    defer length_value.deinit(ctx);
    const length = length_value.toInt32(ctx) catch 0;
    var index: i32 = 0;
    while (index < length) : (index += 1) {
        const key_value = keys.getPropertyUint32(ctx, @intCast(index));
        defer key_value.deinit(ctx);
        if (key_value.isException()) return error.JSError;

        const key_text = key_value.toCStringLen(ctx) orelse return error.JSError;
        defer ctx.freeCString(key_text.ptr);

        const raw_value = source_env.getPropertyStr(ctx, key_text.ptr);
        defer raw_value.deinit(ctx);
        if (raw_value.isException() or raw_value.isUndefined()) continue;

        const normalized = normalizeImportMetaEnvValue(ctx, raw_value);
        errdefer normalized.deinit(ctx);
        target_env.setPropertyStr(ctx, key_text.ptr, normalized) catch return error.JSError;
    }
}

fn normalizeImportMetaEnvValue(ctx: *quickjs.Context, value: quickjs.Value) quickjs.Value {
    const text = value.toCStringLen(ctx) orelse return value.dup(ctx);
    defer ctx.freeCString(text.ptr);

    const slice = text.ptr[0..text.len];
    if (std.ascii.eqlIgnoreCase(slice, "true")) return quickjs.Value.initBool(true);
    if (std.ascii.eqlIgnoreCase(slice, "false")) return quickjs.Value.initBool(false);
    return quickjs.Value.initStringLen(ctx, slice);
}

fn installErrorDefaults(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const error_ctor = global.getPropertyStr(ctx, "Error");
    defer error_ctor.deinit(ctx);
    if (error_ctor.isException() or !error_ctor.isObject()) return;
    error_ctor.setPropertyStr(ctx, "stackTraceLimit", quickjs.Value.initInt32(0)) catch return error.JSError;
}

fn installGlobals(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    global.setPropertyStr(ctx, "global", global.dup(ctx)) catch return error.JSError;
    global.setPropertyStr(ctx, "innerWidth", quickjs.Value.initInt32(1024)) catch return error.JSError;
    global.setPropertyStr(ctx, "innerHeight", quickjs.Value.initInt32(768)) catch return error.JSError;
    global.setPropertyStr(ctx, "outerWidth", quickjs.Value.initInt32(1024)) catch return error.JSError;
    global.setPropertyStr(ctx, "outerHeight", quickjs.Value.initInt32(768)) catch return error.JSError;
    global.setPropertyStr(ctx, "scrollX", quickjs.Value.initInt32(0)) catch return error.JSError;
    global.setPropertyStr(ctx, "scrollY", quickjs.Value.initInt32(0)) catch return error.JSError;
    global.setPropertyStr(ctx, "pageXOffset", quickjs.Value.initInt32(0)) catch return error.JSError;
    global.setPropertyStr(ctx, "pageYOffset", quickjs.Value.initInt32(0)) catch return error.JSError;

    var history = global.getPropertyStr(ctx, "history");
    defer history.deinit(ctx);
    if (history.isException() or history.isUndefined() or history.isNull() or !history.isObject()) {
        history.deinit(ctx);
        history = quickjs.Value.initObject(ctx);
        if (history.isException()) return error.JSError;
        global.setPropertyStr(ctx, "history", history.dup(ctx)) catch return error.JSError;
    }

    try setFunctionIfMissing(ctx, history, "pushState", jsHistoryPushState, 3);
    try setFunctionIfMissing(ctx, history, "replaceState", jsHistoryReplaceState, 3);
    try setFunctionIfMissing(ctx, history, "back", jsNoop, 0);
    try setFunctionIfMissing(ctx, history, "forward", jsNoop, 0);
    try setFunctionIfMissing(ctx, history, "go", jsNoop, 1);

    try setFunctionIfMissing(ctx, global, "scrollTo", jsScrollTo, 2);
    try setFunctionIfMissing(ctx, global, "scrollBy", jsScrollBy, 2);
}

fn installTimers(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    // Platform state is process-global but timer callbacks are context-specific.
    // Start each runtime with an empty native event queue, even if allocator
    // reuse gives the new QuickJS context the same pointer as the previous one.
    native_timers = .empty;
    native_timer_ctx = ctx;
    native_next_timer_id = 1;
    crypto_uuid_counter = 0;
    crypto_uuid_state = 0xA409_3822_299F_31D0;
    object_url_counter = 0;

    try setFunction(ctx, global, "queueMicrotask", jsQueueMicrotask, 1);
    try setFunction(ctx, global, "setTimeout", jsSetTimeout, 2);
    try setFunction(ctx, global, "clearTimeout", jsClearTimeout, 1);
    try setFunction(ctx, global, "requestAnimationFrame", jsRequestAnimationFrame, 1);
    try setFunction(ctx, global, "cancelAnimationFrame", jsCancelAnimationFrame, 1);
    try setFunction(ctx, global, "setInterval", jsSetInterval, 2);
    try setFunction(ctx, global, "clearInterval", jsClearInterval, 1);
    try setFunction(ctx, global, "setImmediate", jsSetImmediate, 1);
    try setFunction(ctx, global, "clearImmediate", jsClearImmediate, 1);
    try installMessageChannel(ctx, global);
}

fn installMessageChannel(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const current = global.getPropertyStr(ctx, "MessageChannel");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const ctor = quickjs.Value.initCFunction2(ctx, jsMessageChannelCtor, "MessageChannel", 0, .constructor_or_func, 0);
    if (ctor.isException()) return error.JSError;
    global.setPropertyStr(ctx, "MessageChannel", ctor) catch return error.JSError;
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

    var url_ctor = current.dup(ctx);
    defer url_ctor.deinit(ctx);
    if (current.isUndefined() or current.isNull()) {
        url_ctor.deinit(ctx);
        url_ctor = quickjs.Value.initCFunction2(ctx, jsUrlCtor, "URL", 1, .constructor_or_func, 0);
        if (url_ctor.isException()) return error.JSError;
        global.setPropertyStr(ctx, "URL", url_ctor.dup(ctx)) catch return error.JSError;
    }

    if (!url_ctor.isObject()) return;
    try setFunctionIfMissing(ctx, url_ctor, "createObjectURL", jsUrlCreateObjectURL, 1);
    try setFunctionIfMissing(ctx, url_ctor, "revokeObjectURL", jsUrlRevokeObjectURL, 1);
}

fn installFetchApi(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    if (isMissing(ctx, global, "Headers")) {
        const ctor = quickjs.Value.initCFunction2(ctx, jsHeadersCtor, "Headers", 1, .constructor_or_func, 0);
        if (ctor.isException()) return error.JSError;
        global.setPropertyStr(ctx, "Headers", ctor) catch return error.JSError;
    }
    if (isMissing(ctx, global, "Request")) {
        const ctor = quickjs.Value.initCFunction2(ctx, jsRequestCtor, "Request", 1, .constructor_or_func, 0);
        if (ctor.isException()) return error.JSError;
        global.setPropertyStr(ctx, "Request", ctor) catch return error.JSError;
    }
    if (isMissing(ctx, global, "Response")) {
        const ctor = quickjs.Value.initCFunction2(ctx, jsResponseCtor, "Response", 2, .constructor_or_func, 0);
        if (ctor.isException()) return error.JSError;
        global.setPropertyStr(ctx, "Response", ctor) catch return error.JSError;
    }
    if (isMissing(ctx, global, "Blob")) {
        const ctor = quickjs.Value.initCFunction2(ctx, jsBlobCtor, "Blob", 1, .constructor_or_func, 0);
        if (ctor.isException()) return error.JSError;
        global.setPropertyStr(ctx, "Blob", ctor) catch return error.JSError;
    }
    if (isMissing(ctx, global, "File")) {
        const ctor = quickjs.Value.initCFunction2(ctx, jsFileCtor, "File", 2, .constructor_or_func, 0);
        if (ctor.isException()) return error.JSError;
        global.setPropertyStr(ctx, "File", ctor) catch return error.JSError;
    }
    // Always install a runner-specific FormData to support new FormData(form) in DOM tests.
    const form_data_ctor = quickjs.Value.initCFunction2(ctx, jsFormDataCtor, "FormData", 1, .constructor_or_func, 0);
    if (form_data_ctor.isException()) return error.JSError;
    global.setPropertyStr(ctx, "FormData", form_data_ctor) catch return error.JSError;
    try setFunctionIfMissing(ctx, global, "fetch", jsFetch, 1);
}

fn installImage(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    if (!isMissing(ctx, global, "Image")) return;
    const ctor = quickjs.Value.initCFunction2(ctx, jsImageCtor, "Image", 0, .constructor_or_func, 0);
    if (ctor.isException()) return error.JSError;
    global.setPropertyStr(ctx, "Image", ctor) catch return error.JSError;
}

fn isMissing(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8) bool {
    const current = object.getPropertyStr(ctx, name);
    defer current.deinit(ctx);
    return current.isUndefined() or current.isNull();
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

    const collator_current = intl.getPropertyStr(ctx, "Collator");
    defer collator_current.deinit(ctx);
    if (collator_current.isUndefined() or collator_current.isNull()) {
        const collator_ctor = quickjs.Value.initCFunction2(ctx, jsCollatorCtor, "Collator", 0, .constructor_or_func, 0);
        if (collator_ctor.isException()) return error.JSError;
        intl.setPropertyStr(ctx, "Collator", collator_ctor) catch return error.JSError;
    }

    const number_format_current = intl.getPropertyStr(ctx, "NumberFormat");
    defer number_format_current.deinit(ctx);
    if (number_format_current.isUndefined() or number_format_current.isNull()) {
        const number_format_ctor = quickjs.Value.initCFunction2(ctx, jsNumberFormatCtor, "NumberFormat", 2, .constructor_or_func, 0);
        if (number_format_ctor.isException()) return error.JSError;
        intl.setPropertyStr(ctx, "NumberFormat", number_format_ctor) catch return error.JSError;
    }
}

fn installDateLocale(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const date_ctor = global.getPropertyStr(ctx, "Date");
    defer date_ctor.deinit(ctx);
    if (date_ctor.isException() or date_ctor.isUndefined() or date_ctor.isNull() or !date_ctor.isObject()) return;

    const proto = date_ctor.getPropertyStr(ctx, "prototype");
    defer proto.deinit(ctx);
    if (proto.isException() or proto.isUndefined() or proto.isNull() or !proto.isObject()) return;

    try setFunction(ctx, proto, "toLocaleDateString", jsDateToLocaleDateString, 2);
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

fn installSymbolDisposers(ctx: *quickjs.Context, global: quickjs.Value) PlatformError!void {
    const symbol_ctor = global.getPropertyStr(ctx, "Symbol");
    defer symbol_ctor.deinit(ctx);
    if (symbol_ctor.isException() or !symbol_ctor.isObject()) return;

    const symbol_for = symbol_ctor.getPropertyStr(ctx, "for");
    defer symbol_for.deinit(ctx);
    if (symbol_for.isException() or !symbol_for.isFunction(ctx)) return;

    const ensure_symbol = struct {
        fn ensure(ctx2: *quickjs.Context, symbol_obj: quickjs.Value, for_fn: quickjs.Value, name: [:0]const u8, key: []const u8) PlatformError!void {
            const current = symbol_obj.getPropertyStr(ctx2, name);
            defer current.deinit(ctx2);
            if (!current.isUndefined() and !current.isNull()) return;

            var args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx2, key)};
            defer args[0].deinit(ctx2);
            const symbol_value = for_fn.call(ctx2, symbol_obj, &args);
            defer symbol_value.deinit(ctx2);
            if (symbol_value.isException()) return;
            symbol_obj.setPropertyStr(ctx2, name, symbol_value.dup(ctx2)) catch return error.JSError;
        }
    }.ensure;

    try ensure_symbol(ctx, symbol_ctor, symbol_for, "dispose", "Symbol.dispose");
    try ensure_symbol(ctx, symbol_ctor, symbol_for, "asyncDispose", "Symbol.asyncDispose");
}

fn jsNoop(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsConsoleLog(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    emitConsoleLine(ctx, null, args);
    return quickjs.Value.undefined;
}

fn jsConsoleWarn(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    emitConsoleLine(ctx, null, args);
    return quickjs.Value.undefined;
}

fn jsConsoleError(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    emitConsoleLine(ctx, null, args);
    return quickjs.Value.undefined;
}

fn jsConsoleTrace(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    emitConsoleLine(ctx, "Trace", args);
    return quickjs.Value.undefined;
}

fn jsConsoleAssert(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (args.len > 0 and (quickjs.Value.fromCVal(args[0]).toBool(ctx) catch false)) return quickjs.Value.undefined;
    if (args.len > 1) {
        emitConsoleLine(ctx, "Assertion failed:", args[1..]);
    } else {
        emitConsoleLine(ctx, "Assertion failed", &[_]quickjs.c.JSValue{});
    }
    return quickjs.Value.undefined;
}

fn consoleStdioEnabled() bool {
    const raw = std.c.getenv("ZIG_DOM_CONSOLE_STDIO") orelse return true;
    const value = std.mem.trim(u8, std.mem.span(raw), " \t\r\n");
    if (value.len == 0) return true;
    if (std.mem.eql(u8, value, "0") or
        std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.ascii.eqlIgnoreCase(value, "off"))
    {
        return false;
    }
    return true;
}

fn emitConsoleLine(ctx: *quickjs.Context, prefix: ?[]const u8, args: []const quickjs.c.JSValue) void {
    if (!consoleStdioEnabled()) return;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(c_allocator);

    if (prefix) |text| {
        out.appendSlice(c_allocator, text) catch return;
    }

    for (args, 0..) |arg, index| {
        if (out.items.len > 0 and (prefix != null or index > 0)) {
            out.append(c_allocator, ' ') catch return;
        }
        appendConsoleArg(ctx, &out, quickjs.Value.fromCVal(arg));
    }

    std.debug.print("{s}\n", .{out.items});
}

fn appendConsoleArg(ctx: *quickjs.Context, out: *std.ArrayList(u8), value: quickjs.Value) void {
    if (value.isUndefined()) {
        out.appendSlice(c_allocator, "undefined") catch {};
        return;
    }
    if (value.isNull()) {
        out.appendSlice(c_allocator, "null") catch {};
        return;
    }

    const rendered = value.toStringValue(ctx);
    defer rendered.deinit(ctx);
    if (rendered.isException()) {
        out.appendSlice(c_allocator, "[console-arg-error]") catch {};
        return;
    }

    const text = rendered.toCStringLen(ctx) orelse {
        out.appendSlice(c_allocator, "[console-arg-error]") catch {};
        return;
    };
    defer ctx.freeCString(text.ptr);
    out.appendSlice(c_allocator, text.ptr[0..text.len]) catch {};
}

fn jsClipboardReadText(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (!this_value.isObject()) {
        const empty = quickjs.Value.initStringLen(ctx, "");
        if (empty.isException()) return quickjs.Value.exception;
        defer empty.deinit(ctx);
        return resolvedPromise(ctx, empty);
    }

    const value = this_value.getPropertyStr(ctx, "__zigClipboardText");
    defer value.deinit(ctx);
    if (value.isException() or value.isUndefined() or value.isNull()) {
        const empty = quickjs.Value.initStringLen(ctx, "");
        if (empty.isException()) return quickjs.Value.exception;
        defer empty.deinit(ctx);
        return resolvedPromise(ctx, empty);
    }

    const text = value.toCStringLen(ctx) orelse {
        const empty = quickjs.Value.initStringLen(ctx, "");
        if (empty.isException()) return quickjs.Value.exception;
        defer empty.deinit(ctx);
        return resolvedPromise(ctx, empty);
    };
    defer ctx.freeCString(text.ptr);
    const text_value = quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
    if (text_value.isException()) return quickjs.Value.exception;
    defer text_value.deinit(ctx);
    return resolvedPromise(ctx, text_value);
}

fn jsClipboardWriteText(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (!this_value.isObject()) return resolvedPromise(ctx, quickjs.Value.undefined);

    const text = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    if (text) |value| {
        defer ctx.freeCString(value.ptr);
        this_value.setPropertyStr(ctx, "__zigClipboardText", quickjs.Value.initStringLen(ctx, value.ptr[0..value.len])) catch return quickjs.Value.exception;
    } else {
        this_value.setPropertyStr(ctx, "__zigClipboardText", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    }

    return resolvedPromise(ctx, quickjs.Value.undefined);
}

fn resolvedPromise(ctx: *quickjs.Context, value: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const promise_ctor = global.getPropertyStr(ctx, "Promise");
    defer promise_ctor.deinit(ctx);
    if (promise_ctor.isException() or !promise_ctor.isObject()) return value.dup(ctx);

    const resolve_fn = promise_ctor.getPropertyStr(ctx, "resolve");
    defer resolve_fn.deinit(ctx);
    if (resolve_fn.isException() or !resolve_fn.isFunction(ctx)) return value.dup(ctx);

    var args = [_]quickjs.Value{value.dup(ctx)};
    defer args[0].deinit(ctx);
    const resolved = resolve_fn.call(ctx, promise_ctor, &args);
    if (resolved.isException()) return value.dup(ctx);
    return resolved;
}

fn jsHistoryPushState(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsHistoryReplaceState(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsScrollTo(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    var next_x: f64 = 0;
    var next_y: f64 = 0;
    if (args.len > 0) {
        const first = quickjs.Value.fromCVal(args[0]);
        if (first.isObject()) {
            const left = first.getPropertyStr(ctx, "left");
            defer left.deinit(ctx);
            const top = first.getPropertyStr(ctx, "top");
            defer top.deinit(ctx);
            next_x = left.toFloat64(ctx) catch 0;
            next_y = top.toFloat64(ctx) catch 0;
        } else {
            next_x = first.toFloat64(ctx) catch 0;
            next_y = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toFloat64(ctx) catch 0 else 0;
        }
    }

    setScrollPosition(ctx, global, next_x, next_y) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsScrollBy(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const current_x_value = global.getPropertyStr(ctx, "scrollX");
    defer current_x_value.deinit(ctx);
    const current_y_value = global.getPropertyStr(ctx, "scrollY");
    defer current_y_value.deinit(ctx);

    const current_x = current_x_value.toFloat64(ctx) catch 0;
    const current_y = current_y_value.toFloat64(ctx) catch 0;

    const delta_x = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toFloat64(ctx) catch 0 else 0;
    const delta_y = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toFloat64(ctx) catch 0 else 0;

    setScrollPosition(ctx, global, current_x + delta_x, current_y + delta_y) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn setScrollPosition(ctx: *quickjs.Context, global: quickjs.Value, x: f64, y: f64) !void {
    global.setPropertyStr(ctx, "scrollX", quickjs.Value.initFloat64(x)) catch return error.JSError;
    global.setPropertyStr(ctx, "scrollY", quickjs.Value.initFloat64(y)) catch return error.JSError;
    global.setPropertyStr(ctx, "pageXOffset", quickjs.Value.initFloat64(x)) catch return error.JSError;
    global.setPropertyStr(ctx, "pageYOffset", quickjs.Value.initFloat64(y)) catch return error.JSError;

    const window = global.getPropertyStr(ctx, "window");
    defer window.deinit(ctx);
    if (!window.isException() and window.isObject()) {
        window.setPropertyStr(ctx, "scrollX", quickjs.Value.initFloat64(x)) catch return error.JSError;
        window.setPropertyStr(ctx, "scrollY", quickjs.Value.initFloat64(y)) catch return error.JSError;
        window.setPropertyStr(ctx, "pageXOffset", quickjs.Value.initFloat64(x)) catch return error.JSError;
        window.setPropertyStr(ctx, "pageYOffset", quickjs.Value.initFloat64(y)) catch return error.JSError;
    }
}

fn jsCryptoRandomUUID(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;

    crypto_uuid_counter +%= 1;
    crypto_uuid_state +%= crypto_uuid_counter *% 0x9E37_79B9_7F4A_7C15;

    var bytes: [16]u8 = undefined;
    for (bytes[0..]) |*byte| {
        crypto_uuid_state ^= crypto_uuid_state << 13;
        crypto_uuid_state ^= crypto_uuid_state >> 7;
        crypto_uuid_state ^= crypto_uuid_state << 17;
        byte.* = @truncate(crypto_uuid_state);
    }

    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    var buf: [36]u8 = undefined;
    const text = std.fmt.bufPrint(
        &buf,
        "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            bytes[6],
            bytes[7],
            bytes[8],
            bytes[9],
            bytes[10],
            bytes[11],
            bytes[12],
            bytes[13],
            bytes[14],
            bytes[15],
        },
    ) catch return quickjs.Value.exception;

    return quickjs.Value.initStringLen(ctx, text);
}

fn jsObjectGetAutoHeightDuration(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const height = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toFloat64(ctx) catch 0.0 else 0.0;
    if (!(height > 0.0)) return quickjs.Value.initInt32(0);

    const constant = height / 36.0;
    const duration = @min(@round((4.0 + 15.0 * std.math.pow(f64, constant, 0.25) + constant / 5.0) * 10.0), 3000.0);
    return quickjs.Value.initFloat64(duration);
}

fn clearNativeTimers(ctx: *quickjs.Context) void {
    for (native_timers.items) |*timer| timer.deinit(ctx);
    native_timers.deinit(c_allocator);
    native_timers = .empty;
}

fn findNativeTimerIndex(id: i32) ?usize {
    for (native_timers.items, 0..) |timer, index| {
        if (timer.id == id) return index;
    }
    return null;
}

fn removeNativeTimerAt(ctx: *quickjs.Context, index: usize) void {
    var timer = native_timers.swapRemove(index);
    timer.deinit(ctx);
}

fn delayToTimerTurns(delay_ms: f64) u32 {
    if (!std.math.isFinite(delay_ms) or delay_ms <= 0) return 1;
    const turns = @as(i64, @intFromFloat(@ceil(delay_ms / 25.0)));
    return @intCast(@max(1, @min(turns, 10_000)));
}

fn timerDelayFromArgs(ctx: *quickjs.Context, args: []const quickjs.c.JSValue) u32 {
    if (args.len < 2) return 1;
    const delay = quickjs.Value.fromCVal(args[1]).toFloat64(ctx) catch 0;
    return delayToTimerTurns(delay);
}

fn runQueuedMicrotaskCallback(ctx: *quickjs.Context, args: []const quickjs.Value) quickjs.Value {
    if (args.len == 0) return quickjs.Value.undefined;
    const callback = args[0];
    if (!callback.isFunction(ctx)) return quickjs.Value.undefined;
    const result = callback.call(ctx, quickjs.Value.undefined, &.{});
    defer result.deinit(ctx);
    if (result.isException()) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn enqueueMicrotaskCallback(ctx: *quickjs.Context, callback: quickjs.Value) bool {
    var callback_args = [_]quickjs.Value{callback.dup(ctx)};
    defer callback_args[0].deinit(ctx);
    ctx.enqueueJob(runQueuedMicrotaskCallback, &callback_args) catch return false;
    return true;
}

fn invokeNativeTimerAt(ctx: *quickjs.Context, initial_index: usize) quickjs.Value {
    if (initial_index >= native_timers.items.len) return quickjs.Value.undefined;
    const timer = &native_timers.items[initial_index];
    const id = timer.id;
    const callback = timer.callback.dup(ctx);
    defer callback.deinit(ctx);

    var call_args = std.ArrayListUnmanaged(quickjs.Value).empty;
    defer {
        for (call_args.items) |value| value.deinit(ctx);
        call_args.deinit(c_allocator);
    }
    call_args.ensureTotalCapacity(c_allocator, timer.args.items.len) catch return quickjs.Value.exception;
    for (timer.args.items) |value| {
        call_args.appendAssumeCapacity(value.dup(ctx));
    }

    const callback_result = callback.call(ctx, quickjs.Value.undefined, call_args.items);
    defer callback_result.deinit(ctx);
    const callback_failed = callback_result.isException();

    const current_index = findNativeTimerIndex(id) orelse {
        if (callback_failed) return quickjs.Value.exception;
        return quickjs.Value.undefined;
    };
    const current = &native_timers.items[current_index];
    switch (current.kind) {
        .timeout => removeNativeTimerAt(ctx, current_index),
        .immediate => removeNativeTimerAt(ctx, current_index),
        .interval => {
            current.remaining_turns = current.interval_turns;
        },
    }

    if (callback_failed) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn installNativeTimer(
    ctx: *quickjs.Context,
    args: []const quickjs.c.JSValue,
    kind: NativeTimerKind,
    explicit_delay_turns: ?u32,
) quickjs.Value {
    if (args.len == 0) return ctx.throwInternalError("Timer callback is required");
    const callback = quickjs.Value.fromCVal(args[0]);
    if (!callback.isFunction(ctx)) return ctx.throwInternalError("Timer callback must be a function");

    const timer_turns = explicit_delay_turns orelse timerDelayFromArgs(ctx, args);
    var timer = NativeTimer{
        .id = native_next_timer_id,
        .kind = kind,
        .callback = callback.dup(ctx),
        .remaining_turns = timer_turns,
        .interval_turns = timer_turns,
    };
    errdefer timer.deinit(ctx);

    timer.args.ensureTotalCapacity(c_allocator, if (args.len > 2) args.len - 2 else 0) catch return quickjs.Value.exception;
    if (args.len > 2) {
        for (args[2..]) |arg| {
            timer.args.appendAssumeCapacity(quickjs.Value.fromCVal(arg).dup(ctx));
        }
    }

    native_timers.append(c_allocator, timer) catch return quickjs.Value.exception;
    const id = timer.id;
    native_next_timer_id += 1;
    return quickjs.Value.initInt32(id);
}

fn clearNativeTimerByArgs(ctx: *quickjs.Context, args: []const quickjs.c.JSValue) void {
    if (args.len == 0) return;
    const id = quickjs.Value.fromCVal(args[0]).toInt32(ctx) catch return;
    const index = findNativeTimerIndex(id) orelse return;
    removeNativeTimerAt(ctx, index);
}

fn jsQueueMicrotask(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (args.len == 0) return ctx.throwInternalError("queueMicrotask callback is required");
    const callback = quickjs.Value.fromCVal(args[0]);
    if (!callback.isFunction(ctx)) return ctx.throwInternalError("queueMicrotask callback must be a function");
    if (!enqueueMicrotaskCallback(ctx, callback)) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsSetTimeout(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    return installNativeTimer(ctx, args, .timeout, null);
}

fn jsClearTimeout(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    clearNativeTimerByArgs(ctx, args);
    return quickjs.Value.undefined;
}

fn jsSetInterval(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const base_turns = timerDelayFromArgs(ctx, args);
    const scaled_turns = @as(u64, base_turns) * 50;
    const interval_turns: u32 = @intCast(@max(@as(u64, 40), @min(scaled_turns, 200_000)));
    return installNativeTimer(ctx, args, .interval, interval_turns);
}

fn jsRequestAnimationFrame(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (args.len == 0) return ctx.throwInternalError("requestAnimationFrame callback is required");

    const callback = quickjs.Value.fromCVal(args[0]);
    if (!callback.isFunction(ctx)) return ctx.throwInternalError("requestAnimationFrame callback must be a function");

    var delay = quickjs.Value.initInt32(16);
    defer delay.deinit(ctx);
    var raf_args = [_]quickjs.Value{ callback.dup(ctx), delay };
    defer raf_args[0].deinit(ctx);

    return installNativeTimer(ctx, @ptrCast(&raf_args), .timeout, null);
}

fn jsCancelAnimationFrame(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    return jsClearTimeout(maybe_ctx, quickjs.Value.undefined, args);
}

fn jsClearInterval(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    return jsClearTimeout(maybe_ctx, quickjs.Value.undefined, args);
}

fn jsSetImmediate(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    return installNativeTimer(ctx, args, .immediate, 1);
}

fn jsClearImmediate(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    return jsClearTimeout(maybe_ctx, quickjs.Value.undefined, args);
}

fn jsMessagePortPostMessage(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, raw_args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const args: []const quickjs.Value = @ptrCast(raw_args);
    const peer = this_value.getPropertyStr(ctx, "__zigPeer");
    defer peer.deinit(ctx);
    if (peer.isException() or !peer.isObject()) return quickjs.Value.undefined;

    const message = if (args.len > 0) args[0].dup(ctx) else quickjs.Value.undefined;
    var data = [_]quickjs.Value{ peer.dup(ctx), message };
    defer {
        data[0].deinit(ctx);
        data[1].deinit(ctx);
    }
    const deliver = quickjs.Value.initCFunctionData2(ctx, jsMessagePortDeliver, "__zigMessagePortDeliver", 0, 0, &data);
    if (deliver.isException()) return quickjs.Value.exception;
    defer deliver.deinit(ctx);
    if (!enqueueMicrotaskCallback(ctx, deliver)) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsMessagePortDeliver(
    maybe_ctx: ?*quickjs.Context,
    _: quickjs.Value,
    _: []const quickjs.c.JSValue,
    _: i32,
    raw_data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const port = quickjs.Value.fromCVal(raw_data[0]);
    const message = quickjs.Value.fromCVal(raw_data[1]);
    const onmessage = port.getPropertyStr(ctx, "onmessage");
    defer onmessage.deinit(ctx);
    if (!onmessage.isFunction(ctx)) return quickjs.Value.undefined;

    const event = quickjs.Value.initObject(ctx);
    if (event.isException()) return event;
    defer event.deinit(ctx);
    event.setPropertyStr(ctx, "data", message.dup(ctx)) catch return quickjs.Value.exception;
    const result = onmessage.call(ctx, port, &.{event});
    defer result.deinit(ctx);
    if (result.isException()) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn createMessagePort(ctx: *quickjs.Context) PlatformError!quickjs.Value {
    const port = quickjs.Value.initObject(ctx);
    if (port.isException()) return error.JSError;
    errdefer port.deinit(ctx);
    port.setPropertyStr(ctx, "onmessage", quickjs.Value.null) catch return error.JSError;
    try setFunction(ctx, port, "postMessage", jsMessagePortPostMessage, 1);
    try setFunction(ctx, port, "start", jsNoop, 0);
    try setFunction(ctx, port, "close", jsNoop, 0);
    return port;
}

fn jsMessageChannelCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const channel = quickjs.Value.initObject(ctx);
    if (channel.isException()) return channel;

    const port1 = createMessagePort(ctx) catch return quickjs.Value.exception;
    defer port1.deinit(ctx);
    const port2 = createMessagePort(ctx) catch return quickjs.Value.exception;
    defer port2.deinit(ctx);

    port1.setPropertyStr(ctx, "__zigPeer", port2.dup(ctx)) catch return quickjs.Value.exception;
    port2.setPropertyStr(ctx, "__zigPeer", port1.dup(ctx)) catch return quickjs.Value.exception;
    channel.setPropertyStr(ctx, "port1", port1.dup(ctx)) catch return quickjs.Value.exception;
    channel.setPropertyStr(ctx, "port2", port2.dup(ctx)) catch return quickjs.Value.exception;
    return channel;
}

pub fn hasPendingNativeTimers() bool {
    return native_timers.items.len > 0;
}

pub fn hasDueNativeTimers() bool {
    for (native_timers.items) |timer| {
        if (timer.remaining_turns <= 1) return true;
    }
    return false;
}

pub fn runNativeTimerTurn(ctx: *quickjs.Context) quickjs.Value {
    if (native_timers.items.len == 0) return quickjs.Value.undefined;

    var due_index: ?usize = null;
    for (native_timers.items, 0..) |*timer, index| {
        if (timer.remaining_turns <= 1) {
            due_index = index;
            break;
        }
        timer.remaining_turns -= 1;
    }

    if (due_index) |index| {
        return invokeNativeTimerAt(ctx, index);
    }

    return quickjs.Value.undefined;
}

fn jsNativeTimerTick(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    return runNativeTimerTurn(ctx);
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

fn jsKeyboardEventCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
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

fn jsUrlSearchParamsCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (input) |text| ctx.freeCString(text.ptr);
    const raw = if (input) |text| text.ptr[0..text.len] else "";
    initUrlSearchParamsObject(ctx, obj, raw) catch return quickjs.Value.exception;
    return obj;
}

fn initUrlSearchParamsObject(ctx: *quickjs.Context, obj: quickjs.Value, raw: []const u8) PlatformError!void {
    obj.setPropertyStr(ctx, "__zigRawSearch", quickjs.Value.initStringLen(ctx, if (std.mem.startsWith(u8, raw, "?")) raw[1..] else raw)) catch return error.JSError;
    setFunction(ctx, obj, "append", jsUrlSearchParamsAppend, 2) catch return error.JSError;
    setFunction(ctx, obj, "set", jsUrlSearchParamsAppend, 2) catch return error.JSError;
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

fn jsUrlSearchParamsAppend(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const key = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (key) |text| ctx.freeCString(text.ptr);
    const value = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toCStringLen(ctx) else null;
    defer if (value) |text| ctx.freeCString(text.ptr);
    if (key == null) return quickjs.Value.undefined;
    const raw_value = this_value.getPropertyStr(ctx, "__zigRawSearch");
    defer raw_value.deinit(ctx);
    const raw = raw_value.toCStringLen(ctx);
    defer if (raw) |text| ctx.freeCString(text.ptr);
    const prefix = if (raw) |text| if (text.len > 0) "&" else "" else "";
    var buffer: [1024]u8 = undefined;
    const next = std.fmt.bufPrint(
        &buffer,
        "{s}{s}{s}={s}",
        .{
            if (raw) |text| text.ptr[0..text.len] else "",
            prefix,
            key.?.ptr[0..key.?.len],
            if (value) |text| text.ptr[0..text.len] else "",
        },
    ) catch return quickjs.Value.exception;
    this_value.setPropertyStr(ctx, "__zigRawSearch", quickjs.Value.initStringLen(ctx, next)) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
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

fn jsUrlCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
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
    const origin = if (protocol.len > 0 and host.len > 0) href[0..(protocol.len + 2 + host.len)] else "";
    obj.setPropertyStr(ctx, "origin", quickjs.Value.initStringLen(ctx, origin)) catch return quickjs.Value.exception;
    const params = quickjs.Value.initObject(ctx);
    if (params.isException()) return quickjs.Value.exception;
    initUrlSearchParamsObject(ctx, params, search) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "searchParams", params) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "toString", jsUrlToString, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsUrlCreateObjectURL(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    object_url_counter +%= 1;

    var buffer: [64]u8 = undefined;
    const value = std.fmt.bufPrint(&buffer, "blob:zig-dom/{x}", .{object_url_counter}) catch "blob:zig-dom/0";
    return quickjs.Value.initStringLen(ctx, value);
}

fn jsUrlRevokeObjectURL(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsUrlToString(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const href = this_value.getPropertyStr(ctx, "href");
    if (href.isException()) return quickjs.Value.initStringLen(ctx, "");
    return href;
}

fn jsHeadersCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const store = quickjs.Value.initObject(ctx);
    if (store.isException()) return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "__zigHeaders", store) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "get", jsHeadersGet, 1) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "set", jsHeadersSet, 2) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "has", jsHeadersHas, 1) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "append", jsHeadersSet, 2) catch return quickjs.Value.exception;
    if (args.len > 0) {
        const init = quickjs.Value.fromCVal(args[0]);
        if (init.isObject()) copyHeaderObject(ctx, obj, init) catch return quickjs.Value.exception;
    }
    return obj;
}

fn jsFormDataCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;

    const map = quickjs.Value.initObject(ctx);
    if (map.isException()) return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "__zigFormDataMap", map) catch return quickjs.Value.exception;

    setFunction(ctx, obj, "append", jsFormDataAppend, 2) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "get", jsFormDataGet, 1) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "getAll", jsFormDataGetAll, 1) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "set", jsFormDataSet, 2) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "has", jsFormDataHas, 1) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "delete", jsFormDataDelete, 1) catch return quickjs.Value.exception;

    if (args.len > 0) {
        const source = quickjs.Value.fromCVal(args[0]);
        if (source.isObject()) {
            populateFormDataFromFormLike(ctx, obj, source) catch return quickjs.Value.exception;
        }
    }

    return obj;
}

fn jsFormDataAppend(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    const value = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toCStringLen(ctx) else null;
    defer if (value) |text| ctx.freeCString(text.ptr);

    if (name) |key| {
        appendFormDataValue(
            ctx,
            this_value,
            key.ptr,
            key.len,
            if (value) |v| v.ptr[0..v.len] else "",
        ) catch return quickjs.Value.exception;
    }

    return quickjs.Value.undefined;
}

fn jsFormDataGet(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    const key = if (name) |text| text else return quickjs.Value.null;

    const map = this_value.getPropertyStr(ctx, "__zigFormDataMap");
    defer map.deinit(ctx);
    if (map.isException() or !map.isObject()) return quickjs.Value.null;

    const bucket = map.getPropertyStr(ctx, key.ptr);
    defer bucket.deinit(ctx);
    if (bucket.isException() or bucket.isUndefined() or bucket.isNull() or !bucket.isObject()) return quickjs.Value.null;

    const first = bucket.getPropertyUint32(ctx, 0);
    if (first.isException() or first.isUndefined()) {
        first.deinit(ctx);
        return quickjs.Value.null;
    }
    return first;
}

fn jsFormDataGetAll(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    const key = if (name) |text| text else return quickjs.Value.initArray(ctx);

    const map = this_value.getPropertyStr(ctx, "__zigFormDataMap");
    defer map.deinit(ctx);
    if (map.isException() or !map.isObject()) return quickjs.Value.initArray(ctx);

    const bucket = map.getPropertyStr(ctx, key.ptr);
    defer bucket.deinit(ctx);
    if (bucket.isException() or bucket.isUndefined() or bucket.isNull() or !bucket.isObject()) return quickjs.Value.initArray(ctx);
    return bucket.dup(ctx);
}

fn jsFormDataSet(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    const value = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toCStringLen(ctx) else null;
    defer if (value) |text| ctx.freeCString(text.ptr);
    const key = if (name) |text| text else return quickjs.Value.undefined;

    const map = this_value.getPropertyStr(ctx, "__zigFormDataMap");
    defer map.deinit(ctx);
    if (map.isException() or !map.isObject()) return quickjs.Value.exception;

    const bucket = quickjs.Value.initArray(ctx);
    if (bucket.isException()) return quickjs.Value.exception;
    bucket.setPropertyUint32(ctx, 0, quickjs.Value.initStringLen(ctx, if (value) |v| v.ptr[0..v.len] else "")) catch return quickjs.Value.exception;
    map.setPropertyStr(ctx, key.ptr, bucket) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsFormDataHas(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    const key = if (name) |text| text else return quickjs.Value.initBool(false);

    const map = this_value.getPropertyStr(ctx, "__zigFormDataMap");
    defer map.deinit(ctx);
    if (map.isException() or !map.isObject()) return quickjs.Value.initBool(false);

    const has = map.hasPropertyStr(ctx, key.ptr) catch false;
    return quickjs.Value.initBool(has);
}

fn jsFormDataDelete(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    const key = if (name) |text| text else return quickjs.Value.undefined;

    const map = this_value.getPropertyStr(ctx, "__zigFormDataMap");
    defer map.deinit(ctx);
    if (map.isException() or !map.isObject()) return quickjs.Value.undefined;

    _ = map.deletePropertyStr(ctx, key.ptr) catch false;
    return quickjs.Value.undefined;
}

fn appendFormDataValue(ctx: *quickjs.Context, form_data: quickjs.Value, key_ptr: [*:0]const u8, key_len: usize, value: []const u8) PlatformError!void {
    const map = form_data.getPropertyStr(ctx, "__zigFormDataMap");
    defer map.deinit(ctx);
    if (map.isException() or !map.isObject()) return error.JSError;

    var bucket = map.getPropertyStr(ctx, key_ptr);
    defer bucket.deinit(ctx);
    if (bucket.isException() or bucket.isUndefined() or bucket.isNull() or !bucket.isObject()) {
        bucket.deinit(ctx);
        bucket = quickjs.Value.initArray(ctx);
        if (bucket.isException()) return error.JSError;
        map.setPropertyStr(ctx, key_ptr, bucket.dup(ctx)) catch return error.JSError;
    }

    const length = bucket.getLength(ctx) catch 0;
    bucket.setPropertyUint32(ctx, @intCast(@max(length, 0)), quickjs.Value.initStringLen(ctx, value)) catch return error.JSError;

    _ = key_len;
}

fn populateFormDataFromFormLike(ctx: *quickjs.Context, form_data: quickjs.Value, form: quickjs.Value) PlatformError!void {
    const elements = form.getPropertyStr(ctx, "elements");
    defer elements.deinit(ctx);
    if (elements.isException() or !elements.isObject()) return;

    const length = elements.getLength(ctx) catch 0;
    var index: i64 = 0;
    while (index < length) : (index += 1) {
        const control = elements.getPropertyUint32(ctx, @intCast(index));
        defer control.deinit(ctx);
        if (control.isException() or !control.isObject()) continue;

        const disabled = control.getPropertyStr(ctx, "disabled");
        defer disabled.deinit(ctx);
        if (!disabled.isException() and (disabled.toBool(ctx) catch false)) continue;

        const name_value = control.getPropertyStr(ctx, "name");
        defer name_value.deinit(ctx);
        const name = name_value.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(name.ptr);
        if (name.len == 0) continue;

        const tag_name_value = control.getPropertyStr(ctx, "tagName");
        defer tag_name_value.deinit(ctx);
        const tag_name = tag_name_value.toCStringLen(ctx);
        defer if (tag_name) |text| ctx.freeCString(text.ptr);
        const is_select = if (tag_name) |text| std.ascii.eqlIgnoreCase(text.ptr[0..text.len], "select") else false;

        if (is_select) {
            const multiple = control.getPropertyStr(ctx, "multiple");
            defer multiple.deinit(ctx);
            if (!multiple.isException() and (multiple.toBool(ctx) catch false)) {
                const options = control.getPropertyStr(ctx, "options");
                defer options.deinit(ctx);
                if (!options.isException() and options.isObject()) {
                    const option_len = options.getLength(ctx) catch 0;
                    var option_index: i64 = 0;
                    while (option_index < option_len) : (option_index += 1) {
                        const option = options.getPropertyUint32(ctx, @intCast(option_index));
                        defer option.deinit(ctx);
                        if (option.isException() or !option.isObject()) continue;

                        const selected = option.getPropertyStr(ctx, "selected");
                        defer selected.deinit(ctx);
                        if (selected.isException() or !(selected.toBool(ctx) catch false)) continue;

                        const option_value = option.getPropertyStr(ctx, "value");
                        defer option_value.deinit(ctx);
                        const text = option_value.toCStringLen(ctx) orelse continue;
                        defer ctx.freeCString(text.ptr);
                        try appendFormDataValue(ctx, form_data, name.ptr, name.len, text.ptr[0..text.len]);
                    }
                }
                continue;
            }
        }

        const type_value = control.getPropertyStr(ctx, "type");
        defer type_value.deinit(ctx);
        const input_type = type_value.toCStringLen(ctx);
        defer if (input_type) |text| ctx.freeCString(text.ptr);
        if (input_type) |kind| {
            const kind_slice = kind.ptr[0..kind.len];
            if (std.ascii.eqlIgnoreCase(kind_slice, "checkbox") or std.ascii.eqlIgnoreCase(kind_slice, "radio")) {
                const checked = control.getPropertyStr(ctx, "checked");
                defer checked.deinit(ctx);
                if (checked.isException() or !(checked.toBool(ctx) catch false)) continue;
            }
            if (std.ascii.eqlIgnoreCase(kind_slice, "file")) continue;
        }

        const value_prop = control.getPropertyStr(ctx, "value");
        defer value_prop.deinit(ctx);
        const value = value_prop.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(value.ptr);
        try appendFormDataValue(ctx, form_data, name.ptr, name.len, value.ptr[0..value.len]);
    }
}

fn copyHeaderObject(ctx: *quickjs.Context, headers: quickjs.Value, init: quickjs.Value) PlatformError!void {
    const keys_fn = getObjectKeys(ctx) catch return error.JSError;
    defer keys_fn.deinit(ctx);
    var call_args = [_]quickjs.Value{init.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const keys = keys_fn.call(ctx, quickjs.Value.undefined, &call_args);
    defer keys.deinit(ctx);
    if (keys.isException()) return error.JSError;
    const length_value = keys.getPropertyStr(ctx, "length");
    defer length_value.deinit(ctx);
    const length = length_value.toInt32(ctx) catch 0;
    var index: i32 = 0;
    while (index < length) : (index += 1) {
        const key_value = keys.getPropertyUint32(ctx, @intCast(index));
        defer key_value.deinit(ctx);
        if (key_value.isException()) return error.JSError;
        const key_text = key_value.toCStringLen(ctx) orelse return error.JSError;
        defer ctx.freeCString(key_text.ptr);
        const value = init.getPropertyStr(ctx, key_text.ptr);
        defer value.deinit(ctx);
        if (value.isException() or value.isUndefined() or value.isNull()) continue;
        var method_args = [_]quickjs.Value{ key_value.dup(ctx), value.dup(ctx) };
        defer method_args[0].deinit(ctx);
        defer method_args[1].deinit(ctx);
        const ignored = jsHeadersSet(ctx, headers, @ptrCast(&method_args));
        defer ignored.deinit(ctx);
        if (ignored.isException()) return error.JSError;
    }
}

fn getObjectKeys(ctx: *quickjs.Context) PlatformError!quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const object = global.getPropertyStr(ctx, "Object");
    defer object.deinit(ctx);
    if (object.isException()) return error.JSError;
    const keys = object.getPropertyStr(ctx, "keys");
    if (!keys.isFunction(ctx)) {
        keys.deinit(ctx);
        return error.JSError;
    }
    return keys;
}

fn jsHeadersGet(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    const store = this_value.getPropertyStr(ctx, "__zigHeaders");
    defer store.deinit(ctx);
    if (store.isException() or store.isUndefined()) return quickjs.Value.null;
    if (name) |text| {
        const key = lowerHeaderName(text.ptr[0..text.len]);
        defer std.heap.c_allocator.free(key);
        const value = store.getPropertyStr(ctx, key.ptr);
        if (value.isException() or value.isUndefined()) {
            value.deinit(ctx);
            return quickjs.Value.null;
        }
        return value;
    }
    return quickjs.Value.null;
}

fn jsHeadersSet(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const name = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    const value = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toCStringLen(ctx) else null;
    defer if (value) |text| ctx.freeCString(text.ptr);
    const store = this_value.getPropertyStr(ctx, "__zigHeaders");
    defer store.deinit(ctx);
    if (store.isException() or store.isUndefined()) return quickjs.Value.exception;
    if (name) |text| {
        const key = lowerHeaderName(text.ptr[0..text.len]);
        defer std.heap.c_allocator.free(key);
        store.setPropertyStr(ctx, key.ptr, quickjs.Value.initStringLen(ctx, if (value) |v| v.ptr[0..v.len] else "")) catch return quickjs.Value.exception;
    }
    return quickjs.Value.undefined;
}

fn jsHeadersHas(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const value = jsHeadersGet(ctx, this_value, args);
    defer value.deinit(ctx);
    return quickjs.Value.initBool(!value.isNull() and !value.isUndefined());
}

fn lowerHeaderName(input: []const u8) [:0]u8 {
    const buffer = std.heap.c_allocator.allocSentinel(u8, input.len, 0) catch unreachable;
    for (input, 0..) |ch, index| buffer[index] = std.ascii.toLower(ch);
    return buffer;
}

fn jsRequestCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (input) |text| ctx.freeCString(text.ptr);
    const url = if (input) |text| text.ptr[0..text.len] else "";
    obj.setPropertyStr(ctx, "url", quickjs.Value.initStringLen(ctx, url)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "method", quickjs.Value.initStringLen(ctx, "GET")) catch return quickjs.Value.exception;
    return obj;
}

fn jsResponseCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const body = if (args.len > 0 and !quickjs.Value.fromCVal(args[0]).isUndefined() and !quickjs.Value.fromCVal(args[0]).isNull())
        quickjs.Value.fromCVal(args[0]).toCStringLen(ctx)
    else
        null;
    defer if (body) |text| ctx.freeCString(text.ptr);
    const init = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    var status: i32 = 200;
    if (init.isObject()) {
        const status_value = init.getPropertyStr(ctx, "status");
        defer status_value.deinit(ctx);
        if (!status_value.isException() and !status_value.isUndefined()) status = status_value.toInt32(ctx) catch 200;
    }
    obj.setPropertyStr(ctx, "__zigBody", quickjs.Value.initStringLen(ctx, if (body) |text| text.ptr[0..text.len] else "")) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "status", quickjs.Value.initInt32(status)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "ok", quickjs.Value.initBool(status >= 200 and status < 300)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "statusText", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "url", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    const headers = jsHeadersCtor(ctx, quickjs.Value.undefined, &.{});
    if (headers.isException()) return headers;
    obj.setPropertyStr(ctx, "headers", headers) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "text", jsBodyText, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "json", jsBodyJson, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "blob", jsBodyBlob, 0) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "arrayBuffer", jsBodyArrayBuffer, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsBlobCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const body = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (body) |text| ctx.freeCString(text.ptr);
    const text = if (body) |value| value.ptr[0..value.len] else "";
    obj.setPropertyStr(ctx, "__zigBody", quickjs.Value.initStringLen(ctx, text)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "size", quickjs.Value.initInt32(@intCast(text.len))) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "type", quickjs.Value.initStringLen(ctx, "")) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "text", jsBodyText, 0) catch return quickjs.Value.exception;
    return obj;
}

fn jsFileCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = jsBlobCtor(ctx, quickjs.Value.undefined, args);
    if (obj.isException()) return obj;
    const name = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toCStringLen(ctx) else null;
    defer if (name) |text| ctx.freeCString(text.ptr);
    obj.setPropertyStr(ctx, "name", quickjs.Value.initStringLen(ctx, if (name) |text| text.ptr[0..text.len] else "")) catch return quickjs.Value.exception;
    return obj;
}

fn resolvePromiseValue(ctx: *quickjs.Context, value: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const promise_ctor = global.getPropertyStr(ctx, "Promise");
    defer promise_ctor.deinit(ctx);
    if (!promise_ctor.isObject()) return value;

    const resolve = promise_ctor.getPropertyStr(ctx, "resolve");
    defer resolve.deinit(ctx);
    if (!resolve.isFunction(ctx)) return value;

    var call_args = [_]quickjs.Value{value.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const promise = resolve.call(ctx, promise_ctor, &call_args);
    if (promise.isException()) return value;
    value.deinit(ctx);
    return promise;
}

fn jsBodyText(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const body = this_value.getPropertyStr(ctx, "__zigBody");
    if (body.isException()) {
        body.deinit(ctx);
        return resolvePromiseValue(ctx, quickjs.Value.initStringLen(ctx, ""));
    }
    return resolvePromiseValue(ctx, body);
}

fn jsBodyJson(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const body = this_value.getPropertyStr(ctx, "__zigBody");
    defer body.deinit(ctx);
    if (body.isException() or body.isUndefined()) return resolvePromiseValue(ctx, quickjs.Value.null);
    const json = body.toCStringLen(ctx) orelse return resolvePromiseValue(ctx, quickjs.Value.null);
    defer ctx.freeCString(json.ptr);
    if (json.len == 0) return resolvePromiseValue(ctx, quickjs.Value.null);
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const json_obj = global.getPropertyStr(ctx, "JSON");
    defer json_obj.deinit(ctx);
    const parse = json_obj.getPropertyStr(ctx, "parse");
    defer parse.deinit(ctx);
    var call_args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, json.ptr[0..json.len])};
    defer call_args[0].deinit(ctx);
    const parsed = parse.call(ctx, json_obj, &call_args);
    if (parsed.isException()) return parsed;
    return resolvePromiseValue(ctx, parsed);
}

fn jsBodyBlob(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const body = this_value.getPropertyStr(ctx, "__zigBody");
    defer body.deinit(ctx);
    var args = [_]quickjs.Value{body.dup(ctx)};
    defer args[0].deinit(ctx);
    const blob = jsBlobCtor(ctx, quickjs.Value.undefined, @ptrCast(&args));
    if (blob.isException()) return blob;
    return resolvePromiseValue(ctx, blob);
}

fn jsBodyArrayBuffer(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    return resolvePromiseValue(ctx, quickjs.Value.undefined);
}

fn jsFetch(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (input) |text| ctx.freeCString(text.ptr);
    const url = if (input) |text| text.ptr[0..text.len] else "";
    const body = if (std.mem.startsWith(u8, url, "data:")) blk: {
        const comma = std.mem.indexOfScalar(u8, url, ',') orelse url.len;
        break :blk url[@min(comma + 1, url.len)..];
    } else "";
    var response_args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, body)};
    defer response_args[0].deinit(ctx);
    const response = jsResponseCtor(ctx, quickjs.Value.undefined, @ptrCast(&response_args));
    if (response.isException()) return quickjs.Value.exception;
    response.setPropertyStr(ctx, "url", quickjs.Value.initStringLen(ctx, url)) catch {
        response.deinit(ctx);
        return quickjs.Value.exception;
    };
    return resolvePromiseValue(ctx, response);
}

fn jsImageCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (!document.isException() and document.isObject()) {
        const create = document.getPropertyStr(ctx, "createElement");
        defer create.deinit(ctx);
        if (create.isFunction(ctx)) {
            var call_args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, "img")};
            defer call_args[0].deinit(ctx);
            const image = create.call(ctx, document, &call_args);
            if (!image.isException()) return image;
            image.deinit(ctx);
        }
    }
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "complete", quickjs.Value.initBool(false)) catch return quickjs.Value.exception;
    return obj;
}

fn jsCollatorCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    const options = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    const numeric = readCollatorBooleanOption(ctx, options, "numeric");
    const sensitivity_base = readCollatorSensitivityBase(ctx, options);
    obj.setPropertyStr(ctx, "__zigCollatorNumeric", quickjs.Value.initBool(numeric)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "__zigCollatorSensitivityBase", quickjs.Value.initBool(sensitivity_base)) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "compare", jsCollatorCompare, 2) catch return quickjs.Value.exception;
    return obj;
}

fn jsCollatorCompare(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const left = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (left) |text| ctx.freeCString(text.ptr);
    const right = if (args.len > 1) quickjs.Value.fromCVal(args[1]).toCStringLen(ctx) else null;
    defer if (right) |text| ctx.freeCString(text.ptr);
    const left_slice = if (left) |text| text.ptr[0..text.len] else "";
    const right_slice = if (right) |text| text.ptr[0..text.len] else "";
    const options = readCollatorOptions(ctx, this_value);
    const order = compareCollatorSlices(left_slice, right_slice, options);
    return quickjs.Value.initInt32(order);
}

fn jsNumberFormatCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;

    var style_value = quickjs.Value.initStringLen(ctx, "decimal");
    defer style_value.deinit(ctx);
    var currency_value = quickjs.Value.initStringLen(ctx, "USD");
    defer currency_value.deinit(ctx);

    const options = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    if (options.isObject()) {
        const style = options.getPropertyStr(ctx, "style");
        defer style.deinit(ctx);
        if (!style.isException() and !style.isUndefined() and !style.isNull()) {
            const style_text = style.toCStringLen(ctx);
            if (style_text) |text| {
                defer ctx.freeCString(text.ptr);
                style_value.deinit(ctx);
                style_value = quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
                if (style_value.isException()) return quickjs.Value.exception;
            }
        }

        const currency = options.getPropertyStr(ctx, "currency");
        defer currency.deinit(ctx);
        if (!currency.isException() and !currency.isUndefined() and !currency.isNull()) {
            const currency_text = currency.toCStringLen(ctx);
            if (currency_text) |text| {
                defer ctx.freeCString(text.ptr);
                currency_value.deinit(ctx);
                currency_value = quickjs.Value.initStringLen(ctx, text.ptr[0..text.len]);
                if (currency_value.isException()) return quickjs.Value.exception;
            }
        }
    }

    obj.setPropertyStr(ctx, "__zigNumberFormatStyle", style_value.dup(ctx)) catch return quickjs.Value.exception;
    obj.setPropertyStr(ctx, "__zigNumberFormatCurrency", currency_value.dup(ctx)) catch return quickjs.Value.exception;
    setFunction(ctx, obj, "format", jsNumberFormatFormat, 1) catch return quickjs.Value.exception;
    return obj;
}

fn jsNumberFormatFormat(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.initInt32(0);
    const value = input.toFloat64(ctx) catch 0;

    const style_prop = if (this_value.isObject()) this_value.getPropertyStr(ctx, "__zigNumberFormatStyle") else quickjs.Value.undefined;
    defer style_prop.deinit(ctx);
    const style_text = style_prop.toCStringLen(ctx);
    defer if (style_text) |text| ctx.freeCString(text.ptr);
    const style = if (style_text) |text| text.ptr[0..text.len] else "";

    const currency_prop = if (this_value.isObject()) this_value.getPropertyStr(ctx, "__zigNumberFormatCurrency") else quickjs.Value.undefined;
    defer currency_prop.deinit(ctx);
    const currency_text = currency_prop.toCStringLen(ctx);
    defer if (currency_text) |text| ctx.freeCString(text.ptr);
    const currency = if (currency_text) |text| text.ptr[0..text.len] else "USD";

    const formatted = if (std.mem.eql(u8, style, "currency")) blk: {
        const prefix = if (std.ascii.eqlIgnoreCase(currency, "USD")) "$" else "";
        break :blk std.fmt.allocPrint(c_allocator, "{s}{d:.2}", .{ prefix, value }) catch return quickjs.Value.exception;
    } else std.fmt.allocPrint(c_allocator, "{d}", .{value}) catch return quickjs.Value.exception;
    defer c_allocator.free(formatted);
    return quickjs.Value.initStringLen(ctx, formatted);
}

const CollatorOptions = struct {
    numeric: bool = false,
    sensitivity_base: bool = false,
};

fn readCollatorOptions(ctx: *quickjs.Context, collator: quickjs.Value) CollatorOptions {
    if (!collator.isObject()) return .{};
    const numeric_value = collator.getPropertyStr(ctx, "__zigCollatorNumeric");
    defer numeric_value.deinit(ctx);
    const base_value = collator.getPropertyStr(ctx, "__zigCollatorSensitivityBase");
    defer base_value.deinit(ctx);

    return .{
        .numeric = numeric_value.toBool(ctx) catch false,
        .sensitivity_base = base_value.toBool(ctx) catch false,
    };
}

fn readCollatorBooleanOption(ctx: *quickjs.Context, options: quickjs.Value, key: [:0]const u8) bool {
    if (!options.isObject()) return false;
    const value = options.getPropertyStr(ctx, key);
    defer value.deinit(ctx);
    return value.toBool(ctx) catch false;
}

fn readCollatorSensitivityBase(ctx: *quickjs.Context, options: quickjs.Value) bool {
    if (!options.isObject()) return false;
    const value = options.getPropertyStr(ctx, "sensitivity");
    defer value.deinit(ctx);
    const text = value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    return std.ascii.eqlIgnoreCase(text.ptr[0..text.len], "base");
}

fn compareCollatorSlices(left: []const u8, right: []const u8, options: CollatorOptions) i32 {
    var li: usize = 0;
    var ri: usize = 0;

    while (true) {
        const left_token = nextCollatorToken(left, &li, options);
        const right_token = nextCollatorToken(right, &ri, options);

        if (left_token == .end and right_token == .end) return 0;
        if (left_token == .end) return -1;
        if (right_token == .end) return 1;

        switch (left_token) {
            .char => |left_char| switch (right_token) {
                .char => |right_char| {
                    if (left_char < right_char) return -1;
                    if (left_char > right_char) return 1;
                },
                .number => return 1,
                .end => unreachable,
            },
            .number => |left_number| switch (right_token) {
                .number => |right_number| {
                    const cmp = compareNumberSlices(left_number, right_number);
                    if (cmp != 0) return cmp;
                },
                .char => return -1,
                .end => unreachable,
            },
            .end => unreachable,
        }
    }
}

const CollatorToken = union(enum) {
    end,
    char: u8,
    number: []const u8,
};

fn nextCollatorToken(text: []const u8, index: *usize, options: CollatorOptions) CollatorToken {
    while (index.* < text.len and options.sensitivity_base and isCollatorIgnorable(text[index.*])) {
        index.* += 1;
    }
    if (index.* >= text.len) return .end;

    const start = index.*;
    const first = text[start];
    if (options.numeric and std.ascii.isDigit(first)) {
        while (index.* < text.len and std.ascii.isDigit(text[index.*])) {
            index.* += 1;
        }
        return .{ .number = text[start..index.*] };
    }

    index.* += 1;
    return .{ .char = normalizeCollatorChar(first, options) };
}

fn normalizeCollatorChar(value: u8, options: CollatorOptions) u8 {
    if (options.sensitivity_base) return std.ascii.toLower(value);
    return value;
}

fn isCollatorIgnorable(value: u8) bool {
    return !std.ascii.isAlphanumeric(value);
}

fn compareNumberSlices(left_raw: []const u8, right_raw: []const u8) i32 {
    const left = trimLeadingZeros(left_raw);
    const right = trimLeadingZeros(right_raw);

    if (left.len < right.len) return -1;
    if (left.len > right.len) return 1;

    return switch (std.mem.order(u8, left, right)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

fn trimLeadingZeros(value: []const u8) []const u8 {
    var start: usize = 0;
    while (start + 1 < value.len and value[start] == '0') : (start += 1) {}
    return value[start..];
}

fn jsDomParserCtor(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const obj = quickjs.Value.initObject(ctx);
    if (obj.isException()) return quickjs.Value.exception;
    setFunction(ctx, obj, "parseFromString", jsDomParserParseFromString, 1) catch return quickjs.Value.exception;
    return obj;
}

fn jsDomParserQuerySelectorAll(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const body = this_value.getPropertyStr(ctx, "body");
    defer body.deinit(ctx);
    if (!body.isObject()) return quickjs.Value.initArray(ctx);

    const query_selector_all = body.getPropertyStr(ctx, "querySelectorAll");
    defer query_selector_all.deinit(ctx);
    if (!query_selector_all.isFunction(ctx)) return quickjs.Value.initArray(ctx);

    const selector = if (args.len > 0)
        quickjs.Value.fromCVal(args[0]).dup(ctx)
    else
        quickjs.Value.initStringLen(ctx, "*");
    defer selector.deinit(ctx);

    var call_args = [_]quickjs.Value{selector};
    return query_selector_all.call(ctx, body, &call_args);
}

fn jsDomParserParseFromString(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toCStringLen(ctx) else null;
    defer if (input) |text| ctx.freeCString(text.ptr);
    const html = if (input) |text| text.ptr[0..text.len] else "";

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);

    if (!document.isException() and document.isObject()) {
        const create_element = document.getPropertyStr(ctx, "createElement");
        defer create_element.deinit(ctx);

        if (!create_element.isException() and create_element.isFunction(ctx)) {
            const body_tag = quickjs.Value.initStringLen(ctx, "body");
            defer body_tag.deinit(ctx);

            var create_args = [_]quickjs.Value{body_tag};
            const body = create_element.call(ctx, document, &create_args);
            defer body.deinit(ctx);

            if (!body.isException() and body.isObject()) {
                body.setPropertyStr(ctx, "innerHTML", quickjs.Value.initStringLen(ctx, html)) catch return quickjs.Value.exception;

                const parsed = quickjs.Value.initObject(ctx);
                if (parsed.isException()) return quickjs.Value.exception;
                parsed.setPropertyStr(ctx, "body", body.dup(ctx)) catch return quickjs.Value.exception;
                setFunction(ctx, parsed, "querySelectorAll", jsDomParserQuerySelectorAll, 1) catch return quickjs.Value.exception;

                const first_element_child = body.getPropertyStr(ctx, "firstElementChild");
                defer first_element_child.deinit(ctx);
                if (!first_element_child.isException() and !first_element_child.isUndefined() and !first_element_child.isNull()) {
                    parsed.setPropertyStr(ctx, "documentElement", first_element_child.dup(ctx)) catch return quickjs.Value.exception;
                }

                return parsed;
            }
        }
    }

    const parsed = quickjs.Value.initObject(ctx);
    if (parsed.isException()) return quickjs.Value.exception;
    const body = quickjs.Value.initObject(ctx);
    if (body.isException()) return quickjs.Value.exception;
    body.setPropertyStr(ctx, "innerHTML", quickjs.Value.initStringLen(ctx, html)) catch return quickjs.Value.exception;
    body.setPropertyStr(ctx, "textContent", quickjs.Value.initStringLen(ctx, html)) catch return quickjs.Value.exception;
    parsed.setPropertyStr(ctx, "body", body) catch return quickjs.Value.exception;
    if (domParserRootName(html)) |root_name| {
        const namespace = domParserDefaultNamespace(html) orelse "";
        if (!document.isException() and document.isObject()) {
            const create_element_ns = document.getPropertyStr(ctx, "createElementNS");
            defer create_element_ns.deinit(ctx);
            if (!create_element_ns.isException() and create_element_ns.isFunction(ctx)) {
                const namespace_value = if (namespace.len == 0) quickjs.Value.null else quickjs.Value.initStringLen(ctx, namespace);
                defer namespace_value.deinit(ctx);
                const name_value = quickjs.Value.initStringLen(ctx, root_name);
                defer name_value.deinit(ctx);
                const element = create_element_ns.call(ctx, document, &.{ namespace_value, name_value });
                defer element.deinit(ctx);
                if (!element.isException() and element.isObject()) {
                    element.setPropertyStr(ctx, "__zigPreserveElementCase", quickjs.Value.initBool(true)) catch return quickjs.Value.exception;
                    parsed.setPropertyStr(ctx, "documentElement", element.dup(ctx)) catch return quickjs.Value.exception;
                }
            }
        }
    }
    return parsed;
}

fn domParserRootName(source: []const u8) ?[]const u8 {
    const open = std.mem.indexOfScalar(u8, source, '<') orelse return null;
    var start = open + 1;
    if (start >= source.len or source[start] == '/' or source[start] == '!' or source[start] == '?') return null;
    while (start < source.len and std.ascii.isWhitespace(source[start])) : (start += 1) {}
    var end = start;
    while (end < source.len and !std.ascii.isWhitespace(source[end]) and source[end] != '>' and source[end] != '/') : (end += 1) {}
    if (end <= start) return null;
    return source[start..end];
}

fn domParserDefaultNamespace(source: []const u8) ?[]const u8 {
    const marker = "xmlns=\"";
    const start_marker = std.mem.indexOf(u8, source, marker) orelse return null;
    const start = start_marker + marker.len;
    const rest = source[start..];
    const end_offset = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..end_offset];
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

fn jsStorageKey(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const index = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toInt64(ctx) catch 0 else 0;
    const data = this_value.getPropertyStr(ctx, "__zigStorageData");
    defer data.deinit(ctx);
    if (data.isException() or !data.isObject()) return quickjs.Value.null;
    const keys_fn = getObjectKeys(ctx) catch return quickjs.Value.null;
    defer keys_fn.deinit(ctx);
    const keys = keys_fn.call(ctx, quickjs.Value.undefined, &.{data});
    defer keys.deinit(ctx);
    if (keys.isException() or index < 0 or index > std.math.maxInt(u32)) return quickjs.Value.null;
    const key = keys.getPropertyUint32(ctx, @intCast(index));
    if (key.isException() or key.isUndefined()) {
        key.deinit(ctx);
        return quickjs.Value.null;
    }
    return key;
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

fn jsDateToLocaleDateString(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const year = callDateInt(ctx, this_value, "getUTCFullYear") orelse return quickjs.Value.initStringLen(ctx, "Invalid Date");
    const month = callDateInt(ctx, this_value, "getUTCMonth") orelse return quickjs.Value.initStringLen(ctx, "Invalid Date");
    const day = callDateInt(ctx, this_value, "getUTCDate") orelse return quickjs.Value.initStringLen(ctx, "Invalid Date");

    const use_short_month = dateLocaleOptionEquals(ctx, args, "month", "short");
    const use_numeric_year = dateLocaleOptionEquals(ctx, args, "year", "numeric");
    const use_numeric_day = dateLocaleOptionEquals(ctx, args, "day", "numeric");

    const allocator = std.heap.c_allocator;
    const text = if (use_short_month and use_numeric_year and use_numeric_day)
        std.fmt.allocPrint(allocator, "{s} {d}, {d}", .{ short_months[@intCast(@max(0, @min(month, 11)))], day, year }) catch return quickjs.Value.exception
    else
        std.fmt.allocPrint(allocator, "{d}/{d}/{d}", .{ month + 1, day, year }) catch return quickjs.Value.exception;
    defer allocator.free(text);

    return quickjs.Value.initStringLen(ctx, text);
}

const short_months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

fn callDateInt(ctx: *quickjs.Context, date: quickjs.Value, comptime method_name: [:0]const u8) ?i32 {
    const method = date.getPropertyStr(ctx, method_name);
    defer method.deinit(ctx);
    if (method.isException() or !method.isFunction(ctx)) return null;
    const result = method.call(ctx, date, &.{});
    defer result.deinit(ctx);
    if (result.isException()) return null;
    return result.toInt32(ctx) catch null;
}

fn dateLocaleOptionEquals(ctx: *quickjs.Context, args: []const quickjs.c.JSValue, comptime name: [:0]const u8, expected: []const u8) bool {
    if (args.len < 2) return false;
    const options = quickjs.Value.fromCVal(args[1]);
    if (options.isException() or options.isUndefined() or options.isNull() or !options.isObject()) return false;
    const value = options.getPropertyStr(ctx, name);
    defer value.deinit(ctx);
    if (value.isException() or value.isUndefined() or value.isNull()) return false;
    const text = value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    return std.mem.eql(u8, text.ptr[0..text.len], expected);
}

fn setString(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, value: []const u8) PlatformError!void {
    object.setPropertyStr(ctx, name, quickjs.Value.initStringLen(ctx, value)) catch return error.JSError;
}

fn setFunction(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) PlatformError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

fn setNonEnumerableFunction(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) PlatformError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    _ = object.definePropertyValueStr(ctx, name, value, .{
        .configurable = true,
        .writable = true,
        .has_configurable = true,
        .has_writable = true,
        .has_enumerable = true,
        .has_value = true,
        .throw_flag = true,
    }) catch return error.JSError;
}

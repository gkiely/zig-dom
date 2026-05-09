const std = @import("std");
const quickjs = @import("quickjs");

pub const AssertionError = error{JSError};

const Matcher = enum(i32) {
    toBe = 1,
    toEqual = 2,
    toThrow = 3,
    toBeInTheDocument = 4,
    toHaveAttribute = 5,
    toHaveBeenCalled = 6,
    toContain = 7,
    toMatch = 8,
    toHaveProperty = 9,
    toHaveTextContent = 10,
    toHaveBeenNthCalledWith = 11,
    toBeTruthy = 12,
    toBeNull = 13,
    toBeDefined = 14,
    toBeUndefined = 15,
    toHaveLength = 16,
    toBeTrue = 17,
    toEndWith = 18,
    toHaveBeenCalledTimes = 19,
    toHaveBeenCalledWith = 20,
    toMatchObject = 21,
    toBeDisabled = 22,
    toHaveBeenLastCalledWith = 23,
};

pub fn install(ctx: *quickjs.Context) AssertionError!void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    try installRuntimeCompatPolyfills(ctx, global);

    const custom_matchers = quickjs.Value.initObject(ctx);
    if (custom_matchers.isException()) return error.JSError;
    global.setPropertyStr(ctx, "__zigCustomMatchers", custom_matchers) catch return error.JSError;

    const expect = quickjs.Value.initCFunction(ctx, jsExpect, "expect", 1);
    if (expect.isException()) return error.JSError;
    try setFunction(ctx, expect, "extend", jsExpectExtend, 1);
    try setFunction(ctx, expect, "objectContaining", jsExpectObjectContaining, 1);

    global.setPropertyStr(ctx, "__zigExpect", expect.dup(ctx)) catch return error.JSError;
    global.setPropertyStr(ctx, "expect", expect) catch return error.JSError;
    try setFunction(ctx, global, "__zigInstallBunTestApi", jsInstallBunTestApi, 0);
}

fn installRuntimeCompatPolyfills(ctx: *quickjs.Context, global: quickjs.Value) AssertionError!void {
    try installObjectHasOwn(ctx, global);
    try installArrayAt(ctx, global);
    try installStringAt(ctx, global);
}

fn installObjectHasOwn(ctx: *quickjs.Context, global: quickjs.Value) AssertionError!void {
    const object_ctor = global.getPropertyStr(ctx, "Object");
    defer object_ctor.deinit(ctx);
    if (object_ctor.isException() or !object_ctor.isObject()) return;

    const current = object_ctor.getPropertyStr(ctx, "hasOwn");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const has_own = quickjs.Value.initCFunction(ctx, jsObjectHasOwn, "hasOwn", 2);
    if (has_own.isException()) return error.JSError;
    object_ctor.setPropertyStr(ctx, "hasOwn", has_own) catch return error.JSError;
}

fn installArrayAt(ctx: *quickjs.Context, global: quickjs.Value) AssertionError!void {
    const array_ctor = global.getPropertyStr(ctx, "Array");
    defer array_ctor.deinit(ctx);
    if (array_ctor.isException() or !array_ctor.isObject()) return;

    const prototype = array_ctor.getPropertyStr(ctx, "prototype");
    defer prototype.deinit(ctx);
    if (prototype.isException() or !prototype.isObject()) return;

    const current = prototype.getPropertyStr(ctx, "at");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const at = quickjs.Value.initCFunction(ctx, jsArrayAt, "at", 1);
    if (at.isException()) return error.JSError;
    prototype.setPropertyStr(ctx, "at", at) catch return error.JSError;
}

fn installStringAt(ctx: *quickjs.Context, global: quickjs.Value) AssertionError!void {
    const string_ctor = global.getPropertyStr(ctx, "String");
    defer string_ctor.deinit(ctx);
    if (string_ctor.isException() or !string_ctor.isObject()) return;

    const prototype = string_ctor.getPropertyStr(ctx, "prototype");
    defer prototype.deinit(ctx);
    if (prototype.isException() or !prototype.isObject()) return;

    const current = prototype.getPropertyStr(ctx, "at");
    defer current.deinit(ctx);
    if (!current.isUndefined() and !current.isNull()) return;

    const at = quickjs.Value.initCFunction(ctx, jsStringAt, "at", 1);
    if (at.isException()) return error.JSError;
    prototype.setPropertyStr(ctx, "at", at) catch return error.JSError;
}

fn jsObjectHasOwn(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (args.len == 0) return ctx.throwInternalError("Cannot convert undefined or null to object");

    const target = quickjs.Value.fromCVal(args[0]);
    if (target.isUndefined() or target.isNull()) {
        return ctx.throwInternalError("Cannot convert undefined or null to object");
    }

    const key = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    const has = hasOwnPropertyCall(ctx, target, key) catch return quickjs.Value.exception;
    return quickjs.Value.initBool(has);
}

fn jsArrayAt(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (this_value.isUndefined() or this_value.isNull()) return quickjs.Value.undefined;

    const length = getLength(ctx, this_value);
    if (length <= 0) return quickjs.Value.undefined;

    const index = resolveAtIndex(ctx, args, length);
    if (index < 0 or index >= length) return quickjs.Value.undefined;

    return this_value.getPropertyInt64(ctx, index);
}

fn jsStringAt(maybe_ctx: ?*quickjs.Context, this_value: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;

    const string_value = this_value.toStringValue(ctx);
    defer string_value.deinit(ctx);
    if (string_value.isException()) return quickjs.Value.exception;

    const text = string_value.toCStringLen(ctx) orelse return quickjs.Value.undefined;
    defer ctx.freeCString(text.ptr);

    const length: i64 = @intCast(text.len);
    if (length == 0) return quickjs.Value.initStringLen(ctx, "");

    const index = resolveAtIndex(ctx, args, length);
    if (index < 0 or index >= length) return quickjs.Value.undefined;

    const start: usize = @intCast(index);
    return quickjs.Value.initStringLen(ctx, text.ptr[start .. start + 1]);
}

fn getLength(ctx: *quickjs.Context, value: quickjs.Value) i64 {
    const length_value = value.getPropertyStr(ctx, "length");
    defer length_value.deinit(ctx);
    if (length_value.isException()) return 0;

    const length = length_value.toInt64(ctx) catch return 0;
    return if (length < 0) 0 else length;
}

fn resolveAtIndex(ctx: *quickjs.Context, args: []const quickjs.c.JSValue, length: i64) i64 {
    const raw = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toInt64(ctx) catch 0 else 0;
    return if (raw >= 0) raw else length + raw;
}

fn drainPendingJobs(ctx: *quickjs.Context) !void {
    const rt = ctx.getRuntime();
    var iterations: usize = 0;
    while (rt.isJobPending()) : (iterations += 1) {
        _ = rt.executePendingJob() catch return error.JSError;
        if (iterations > 100_000) return error.JSError;
    }
}

fn hasOwnPropertyCall(ctx: *quickjs.Context, target: quickjs.Value, key: quickjs.Value) AssertionError!bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const object_ctor = global.getPropertyStr(ctx, "Object");
    defer object_ctor.deinit(ctx);
    if (object_ctor.isException()) return error.JSError;

    const prototype = object_ctor.getPropertyStr(ctx, "prototype");
    defer prototype.deinit(ctx);
    if (prototype.isException()) return error.JSError;

    const has_own = prototype.getPropertyStr(ctx, "hasOwnProperty");
    defer has_own.deinit(ctx);
    if (!has_own.isFunction(ctx)) return error.JSError;

    var call_args = [_]quickjs.Value{key.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = has_own.call(ctx, target, &call_args);
    defer result.deinit(ctx);
    if (result.isException()) return error.JSError;

    return result.toBool(ctx) catch false;
}

fn jsExpect(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const current_count_value = global.getPropertyStr(ctx, "__zigExpectCalls");
    defer current_count_value.deinit(ctx);
    const current_count = current_count_value.toInt32(ctx) catch 0;
    global.setPropertyStr(ctx, "__zigExpectCalls", quickjs.Value.initInt32(current_count + 1)) catch return quickjs.Value.exception;

    const received = if (args.len > 0) quickjs.Value.fromCVal(args[0]).dup(ctx) else quickjs.Value.undefined;
    defer received.deinit(ctx);

    const matchers = quickjs.Value.initObject(ctx);
    if (matchers.isException()) return quickjs.Value.exception;

    installBuiltinMatchers(ctx, matchers, false, received.dup(ctx)) catch return quickjs.Value.exception;
    installCustomMatchers(ctx, matchers, false, received.dup(ctx)) catch return quickjs.Value.exception;

    const not = quickjs.Value.initObject(ctx);
    if (not.isException()) return quickjs.Value.exception;
    installBuiltinMatchers(ctx, not, true, received.dup(ctx)) catch return quickjs.Value.exception;
    installCustomMatchers(ctx, not, true, received.dup(ctx)) catch return quickjs.Value.exception;
    matchers.setPropertyStr(ctx, "not", not) catch return quickjs.Value.exception;

    return matchers;
}

fn installBuiltinMatchers(ctx: *quickjs.Context, object: quickjs.Value, inverted: bool, received: quickjs.Value) AssertionError!void {
    defer received.deinit(ctx);

    try installMatcher(ctx, object, "toBe", .toBe, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toEqual", .toEqual, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toThrow", .toThrow, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toBeInTheDocument", .toBeInTheDocument, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveAttribute", .toHaveAttribute, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveBeenCalled", .toHaveBeenCalled, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveBeenCalledTimes", .toHaveBeenCalledTimes, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveBeenCalledWith", .toHaveBeenCalledWith, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveBeenLastCalledWith", .toHaveBeenLastCalledWith, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toContain", .toContain, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toMatch", .toMatch, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toMatchObject", .toMatchObject, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveProperty", .toHaveProperty, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveTextContent", .toHaveTextContent, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveBeenNthCalledWith", .toHaveBeenNthCalledWith, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toBeTruthy", .toBeTruthy, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toBeTrue", .toBeTrue, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toBeNull", .toBeNull, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toBeDefined", .toBeDefined, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toBeUndefined", .toBeUndefined, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toHaveLength", .toHaveLength, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toEndWith", .toEndWith, inverted, received.dup(ctx));
    try installMatcher(ctx, object, "toBeDisabled", .toBeDisabled, inverted, received.dup(ctx));
}

fn installCustomMatchers(ctx: *quickjs.Context, object: quickjs.Value, inverted: bool, received: quickjs.Value) AssertionError!void {
    defer received.deinit(ctx);

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const custom = global.getPropertyStr(ctx, "__zigCustomMatchers");
    defer custom.deinit(ctx);
    if (custom.isException() or !custom.isObject()) return;

    const keys_fn = getObjectKeys(ctx) catch return error.JSError;
    defer keys_fn.deinit(ctx);

    var keys_args = [_]quickjs.Value{custom.dup(ctx)};
    defer keys_args[0].deinit(ctx);
    const keys = keys_fn.call(ctx, quickjs.Value.undefined, &keys_args);
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

        if (object.hasPropertyStr(ctx, key_text.ptr) catch false) continue;

        const matcher_fn = custom.getPropertyStr(ctx, key_text.ptr);
        defer matcher_fn.deinit(ctx);
        if (!matcher_fn.isFunction(ctx)) continue;

        const name_value = quickjs.Value.initStringLen(ctx, key_text.ptr[0..key_text.len]);
        if (name_value.isException()) return error.JSError;

        var data = [_]quickjs.Value{ received.dup(ctx), matcher_fn.dup(ctx), name_value };
        defer {
            data[0].deinit(ctx);
            data[1].deinit(ctx);
            data[2].deinit(ctx);
        }

        const func = quickjs.Value.initCFunctionData(ctx, jsCustomMatcher, 1, if (inverted) 1 else 0, &data);
        if (func.isException()) return error.JSError;

        object.setPropertyStr(ctx, key_text.ptr, func) catch return error.JSError;
    }
}

fn jsExpectExtend(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    if (args.len == 0) return quickjs.Value.undefined;

    const extension = quickjs.Value.fromCVal(args[0]);
    if (!extension.isObject()) return quickjs.Value.undefined;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const custom = global.getPropertyStr(ctx, "__zigCustomMatchers");
    defer custom.deinit(ctx);
    if (custom.isException() or !custom.isObject()) return quickjs.Value.undefined;

    const keys_fn = getObjectKeys(ctx) catch return quickjs.Value.exception;
    defer keys_fn.deinit(ctx);

    var keys_args = [_]quickjs.Value{extension.dup(ctx)};
    defer keys_args[0].deinit(ctx);
    const keys = keys_fn.call(ctx, quickjs.Value.undefined, &keys_args);
    defer keys.deinit(ctx);
    if (keys.isException()) return quickjs.Value.exception;

    const length_value = keys.getPropertyStr(ctx, "length");
    defer length_value.deinit(ctx);
    const length = length_value.toInt32(ctx) catch 0;

    var index: i32 = 0;
    while (index < length) : (index += 1) {
        const key_value = keys.getPropertyUint32(ctx, @intCast(index));
        defer key_value.deinit(ctx);
        if (key_value.isException()) return quickjs.Value.exception;

        const key_text = key_value.toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(key_text.ptr);

        const matcher = extension.getPropertyStr(ctx, key_text.ptr);
        defer matcher.deinit(ctx);
        if (!matcher.isFunction(ctx)) continue;

        custom.setPropertyStr(ctx, key_text.ptr, matcher.dup(ctx)) catch return quickjs.Value.exception;
    }

    return quickjs.Value.undefined;
}

fn jsExpectObjectContaining(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;

    const wrapper = quickjs.Value.initObject(ctx);
    if (wrapper.isException()) return quickjs.Value.exception;

    const expected = if (args.len > 0) quickjs.Value.fromCVal(args[0]).dup(ctx) else quickjs.Value.undefined;
    wrapper.setPropertyStr(ctx, "__zigObjectContaining", expected) catch return quickjs.Value.exception;

    return wrapper;
}

fn jsCustomMatcher(
    maybe_ctx: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    magic: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const inverted = magic != 0;
    drainPendingJobs(ctx) catch {
        if (ctx.hasException()) return quickjs.Value.exception;
    };

    const received = quickjs.Value.fromCVal(data[0]);
    const matcher_fn = quickjs.Value.fromCVal(data[1]);
    const matcher_name = quickjs.Value.fromCVal(data[2]);

    const call_args = std.heap.c_allocator.alloc(quickjs.Value, args.len + 1) catch return quickjs.Value.exception;
    defer std.heap.c_allocator.free(call_args);

    call_args[0] = received.dup(ctx);
    defer call_args[0].deinit(ctx);
    for (args, 0..) |arg, index| {
        call_args[index + 1] = quickjs.Value.fromCVal(arg);
    }

    const result = matcher_fn.call(ctx, quickjs.Value.undefined, call_args);
    defer result.deinit(ctx);
    if (result.isException()) return quickjs.Value.exception;

    const pass = matcherResultPass(ctx, result) catch return quickjs.Value.exception;
    if (pass != inverted) return quickjs.Value.undefined;

    return throwCustomMatcherError(ctx, matcher_name, inverted);
}

fn jsInstallBunTestApi(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const api = quickjs.Value.initObject(ctx);
    if (api.isException()) return quickjs.Value.exception;

    inline for (.{ "test", "it", "describe", "expect", "mock", "spyOn", "beforeAll", "beforeEach", "afterEach", "afterAll" }) |name| {
        const value = global.getPropertyStr(ctx, name);
        defer value.deinit(ctx);
        if (!value.isException() and !value.isUndefined()) {
            api.setPropertyStr(ctx, name, value.dup(ctx)) catch return quickjs.Value.exception;
        }
    }

    global.setPropertyStr(ctx, "__zigBunTestApi", api) catch return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn installMatcher(
    ctx: *quickjs.Context,
    object: quickjs.Value,
    comptime name: [:0]const u8,
    matcher: Matcher,
    inverted: bool,
    received: quickjs.Value,
) AssertionError!void {
    defer received.deinit(ctx);
    var data = [_]quickjs.Value{received};
    const offset: i32 = if (inverted) 1000 else 0;
    const magic: i32 = @intFromEnum(matcher) + offset;
    const func = quickjs.Value.initCFunctionData2(ctx, jsMatcher, name, 1, magic, &data);
    if (func.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, func) catch return error.JSError;
}

fn jsMatcher(
    maybe_ctx: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    magic: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const inverted = magic >= 1000;
    const matcher: Matcher = @enumFromInt(if (inverted) magic - 1000 else magic);
    const received = quickjs.Value.fromCVal(data[0]);
    if (matcher == .toBeInTheDocument and inverted and received.isObject()) {
        drainPendingJobs(ctx) catch {
            if (ctx.hasException()) return quickjs.Value.exception;
        };
    }
    var pass = switch (matcher) {
        .toBe => matcherToBe(ctx, received, args),
        .toEqual => matcherToEqual(ctx, received, args),
        .toThrow => matcherToThrow(ctx, received),
        .toBeInTheDocument => matcherToBeInTheDocument(ctx, received),
        .toHaveAttribute => matcherToHaveAttribute(ctx, received, args),
        .toHaveBeenCalled => matcherToHaveBeenCalled(ctx, received),
        .toHaveBeenCalledTimes => matcherToHaveBeenCalledTimes(ctx, received, args),
        .toHaveBeenCalledWith => matcherToHaveBeenCalledWith(ctx, received, args),
        .toHaveBeenLastCalledWith => matcherToHaveBeenLastCalledWith(ctx, received, args),
        .toContain => matcherToContain(ctx, received, args),
        .toMatch => matcherToMatch(ctx, received, args),
        .toMatchObject => matcherToMatchObject(ctx, received, args),
        .toHaveProperty => matcherToHaveProperty(ctx, received, args),
        .toHaveTextContent => matcherToHaveTextContent(ctx, received, args),
        .toHaveBeenNthCalledWith => matcherToHaveBeenNthCalledWith(ctx, received, args),
        .toBeTruthy => matcherToBeTruthy(ctx, received),
        .toBeTrue => matcherToBeTrue(ctx, received),
        .toBeNull => matcherToBeNull(received),
        .toBeDefined => matcherToBeDefined(received),
        .toBeUndefined => matcherToBeUndefined(received),
        .toHaveLength => matcherToHaveLength(ctx, received, args),
        .toEndWith => matcherToEndWith(ctx, received, args),
        .toBeDisabled => matcherToBeDisabled(ctx, received),
    } catch return quickjs.Value.exception;
    if (!pass and matcher == .toBeInTheDocument and !inverted) {
        pass = isOwnedByDocument(ctx, received);
    }

    if (pass != inverted) return quickjs.Value.undefined;
    return throwMatcherError(ctx, matcher, inverted);
}

fn matcherToBe(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    const expected = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    return received.isSameValue(ctx, expected);
}

fn matcherToEqual(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    const expected = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    if (received.isSameValue(ctx, expected)) return true;
    if (compareJsonStringified(ctx, received, expected) catch false) return true;

    const left = received.toStringValue(ctx);
    defer left.deinit(ctx);
    const right = expected.toStringValue(ctx);
    defer right.deinit(ctx);
    return left.isSameValue(ctx, right);
}

fn matcherToThrow(ctx: *quickjs.Context, received: quickjs.Value) !bool {
    if (!received.isFunction(ctx)) return false;
    const result = received.call(ctx, quickjs.Value.undefined, &.{});
    defer result.deinit(ctx);
    if (result.isException()) {
        const exc = ctx.getException();
        exc.deinit(ctx);
        return true;
    }
    return false;
}

fn matcherToBeInTheDocument(ctx: *quickjs.Context, received: quickjs.Value) !bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return false;

    if (received.isArray()) {
        const length = getLength(ctx, received);
        if (length <= 0) return false;

        var index: i64 = 0;
        while (index < length) : (index += 1) {
            const item = received.getPropertyInt64(ctx, index);
            defer item.deinit(ctx);
            if (item.isException() or !item.isObject()) return false;
            if (!(containsNode(ctx, document, item))) return false;
        }
        return true;
    }

    if (!received.isObject()) return false;
    return containsNode(ctx, document, received);
}

fn containsNode(ctx: *quickjs.Context, document: quickjs.Value, node: quickjs.Value) bool {
    const contains = document.getPropertyStr(ctx, "contains");
    defer contains.deinit(ctx);
    if (!contains.isFunction(ctx)) return false;

    var call_args = [_]quickjs.Value{node.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = contains.call(ctx, document, &call_args);
    defer result.deinit(ctx);
    if (result.isException()) return false;
    return result.toBool(ctx) catch false;
}

fn isOwnedByDocument(ctx: *quickjs.Context, value: quickjs.Value) bool {
    if (!value.isObject()) return false;

    const owner_document = value.getPropertyStr(ctx, "ownerDocument");
    defer owner_document.deinit(ctx);
    if (owner_document.isException() or !owner_document.isObject()) return false;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return false;

    return owner_document.isSameValue(ctx, document);
}

fn matcherToHaveAttribute(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    const get_attribute = received.getPropertyStr(ctx, "getAttribute");
    defer get_attribute.deinit(ctx);
    if (!get_attribute.isFunction(ctx) or args.len == 0) return false;

    var call_args = [_]quickjs.Value{quickjs.Value.fromCVal(args[0]).dup(ctx)};
    defer call_args[0].deinit(ctx);
    const actual = get_attribute.call(ctx, received, &call_args);
    defer actual.deinit(ctx);
    if (actual.isException() or actual.isNull() or actual.isUndefined()) return false;
    if (args.len <= 1) return true;

    const expected = quickjs.Value.fromCVal(args[1]);
    const actual_string = actual.toStringValue(ctx);
    defer actual_string.deinit(ctx);
    const expected_string = expected.toStringValue(ctx);
    defer expected_string.deinit(ctx);
    return actual_string.isSameValue(ctx, expected_string);
}

fn matcherToHaveBeenCalled(ctx: *quickjs.Context, received: quickjs.Value) !bool {
    const mock = received.getPropertyStr(ctx, "mock");
    defer mock.deinit(ctx);
    if (mock.isException() or !mock.isObject()) return false;

    const calls = mock.getPropertyStr(ctx, "calls");
    defer calls.deinit(ctx);
    if (calls.isException() or !calls.isObject()) return false;

    const length = calls.getPropertyStr(ctx, "length");
    defer length.deinit(ctx);
    return (length.toInt32(ctx) catch 0) > 0;
}

fn matcherToHaveBeenCalledTimes(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (args.len == 0) return false;
    const expected_count = quickjs.Value.fromCVal(args[0]).toInt64(ctx) catch return false;
    if (expected_count < 0) return false;

    const mock = received.getPropertyStr(ctx, "mock");
    defer mock.deinit(ctx);
    if (mock.isException() or !mock.isObject()) return false;

    const calls = mock.getPropertyStr(ctx, "calls");
    defer calls.deinit(ctx);
    if (calls.isException() or !calls.isObject()) return false;

    const length = calls.getPropertyStr(ctx, "length");
    defer length.deinit(ctx);
    if (length.isException()) return false;

    return (length.toInt64(ctx) catch 0) == expected_count;
}

fn matcherToContain(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (args.len == 0) return false;
    const expected = quickjs.Value.fromCVal(args[0]);

    if (received.isString()) {
        const received_text = received.toCStringLen(ctx) orelse return false;
        defer ctx.freeCString(received_text.ptr);

        const expected_string = expected.toStringValue(ctx);
        defer expected_string.deinit(ctx);
        const expected_text = expected_string.toCStringLen(ctx) orelse return false;
        defer ctx.freeCString(expected_text.ptr);

        return std.mem.indexOf(u8, received_text.ptr[0..received_text.len], expected_text.ptr[0..expected_text.len]) != null;
    }

    if (received.isArray()) {
        const length = getLength(ctx, received);
        var index: i64 = 0;
        while (index < length) : (index += 1) {
            const item = received.getPropertyInt64(ctx, index);
            defer item.deinit(ctx);
            if (item.isException()) return false;
            if (item.isSameValue(ctx, expected)) return true;
        }
    }

    return false;
}

fn matcherToMatch(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (args.len == 0) return false;

    const text_value = received.toStringValue(ctx);
    defer text_value.deinit(ctx);
    const text = text_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);

    const pattern = quickjs.Value.fromCVal(args[0]);
    if (isRegExp(ctx, pattern)) {
        return regexTest(ctx, pattern, text.ptr[0..text.len]);
    }

    const pattern_value = pattern.toStringValue(ctx);
    defer pattern_value.deinit(ctx);
    const pattern_text = pattern_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(pattern_text.ptr);

    return std.mem.indexOf(u8, text.ptr[0..text.len], pattern_text.ptr[0..pattern_text.len]) != null;
}

fn matcherToHaveProperty(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (received.isNull() or received.isUndefined() or args.len == 0) return false;

    const key_value = quickjs.Value.fromCVal(args[0]).toStringValue(ctx);
    defer key_value.deinit(ctx);
    const key_text = key_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(key_text.ptr);

    var actual = received.getPropertyStr(ctx, key_text.ptr);
    if (actual.isException()) return false;
    defer actual.deinit(ctx);

    // DOM nodes often expose values through attributes when IDL properties are missing.
    if (actual.isUndefined()) {
        const get_attribute = received.getPropertyStr(ctx, "getAttribute");
        defer get_attribute.deinit(ctx);
        if (get_attribute.isFunction(ctx)) {
            var attr_args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, key_text.ptr[0..key_text.len])};
            defer attr_args[0].deinit(ctx);
            const attr_value = get_attribute.call(ctx, received, &attr_args);
            if (!attr_value.isException() and !attr_value.isUndefined() and !attr_value.isNull()) {
                actual.deinit(ctx);
                actual = attr_value;
            } else {
                attr_value.deinit(ctx);
            }
        }
    }

    if ((actual.isUndefined() or actual.isNull()) and
        (std.mem.eql(u8, key_text.ptr[0..key_text.len], "href") or std.mem.eql(u8, key_text.ptr[0..key_text.len], "src")))
    {
        const query_selector = received.getPropertyStr(ctx, "querySelector");
        defer query_selector.deinit(ctx);
        if (query_selector.isFunction(ctx)) {
            const selector = if (std.mem.eql(u8, key_text.ptr[0..key_text.len], "href")) "[href]" else "[src]";
            var selector_args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, selector)};
            defer selector_args[0].deinit(ctx);
            const nested = query_selector.call(ctx, received, &selector_args);
            defer nested.deinit(ctx);
            if (!nested.isException() and !nested.isNull() and !nested.isUndefined()) {
                const nested_value = nested.getPropertyStr(ctx, key_text.ptr);
                if (!nested_value.isException() and !nested_value.isUndefined() and !nested_value.isNull()) {
                    actual.deinit(ctx);
                    actual = nested_value;
                } else {
                    nested_value.deinit(ctx);
                    const nested_get_attribute = nested.getPropertyStr(ctx, "getAttribute");
                    defer nested_get_attribute.deinit(ctx);
                    if (nested_get_attribute.isFunction(ctx)) {
                        var nested_attr_args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, key_text.ptr[0..key_text.len])};
                        defer nested_attr_args[0].deinit(ctx);
                        const nested_attr = nested_get_attribute.call(ctx, nested, &nested_attr_args);
                        if (!nested_attr.isException() and !nested_attr.isUndefined() and !nested_attr.isNull()) {
                            actual.deinit(ctx);
                            actual = nested_attr;
                        } else {
                            nested_attr.deinit(ctx);
                        }
                    }
                }
            }
        }
    }

    if (args.len < 2) return !actual.isUndefined() and !actual.isNull();

    const expected = quickjs.Value.fromCVal(args[1]);
    if (actual.isSameValue(ctx, expected)) return true;
    if (compareJsonStringified(ctx, actual, expected) catch false) return true;

    const actual_string = actual.toStringValue(ctx);
    defer actual_string.deinit(ctx);
    const expected_string = expected.toStringValue(ctx);
    defer expected_string.deinit(ctx);
    return actual_string.isSameValue(ctx, expected_string);
}

fn matcherToHaveTextContent(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (args.len == 0) return false;

    const text_prop = received.getPropertyStr(ctx, "textContent");
    defer text_prop.deinit(ctx);

    var raw_text: []const u8 = "";
    var owned_text: ?[]u8 = null;
    defer if (owned_text) |buffer| std.heap.c_allocator.free(buffer);

    if (!text_prop.isException() and !text_prop.isNull() and !text_prop.isUndefined()) {
        const text_value = text_prop.toStringValue(ctx);
        defer text_value.deinit(ctx);
        const text = text_value.toCStringLen(ctx) orelse return false;
        defer ctx.freeCString(text.ptr);

        const copy = std.heap.c_allocator.alloc(u8, text.len) catch return false;
        @memcpy(copy, text.ptr[0..text.len]);
        owned_text = copy;
        raw_text = copy;
    }

    const normalized = normalizeWhitespace(raw_text) catch return false;
    defer std.heap.c_allocator.free(normalized);

    const expected = quickjs.Value.fromCVal(args[0]);
    if (isRegExp(ctx, expected)) {
        return regexTest(ctx, expected, normalized);
    }

    const expected_value = expected.toStringValue(ctx);
    defer expected_value.deinit(ctx);
    const expected_text = expected_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(expected_text.ptr);

    return std.mem.indexOf(u8, normalized, expected_text.ptr[0..expected_text.len]) != null;
}

fn matcherToHaveBeenNthCalledWith(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (args.len == 0) return false;

    const nth = quickjs.Value.fromCVal(args[0]).toInt32(ctx) catch return false;
    if (nth <= 0) return false;
    const index: u32 = @intCast(nth - 1);

    const mock = received.getPropertyStr(ctx, "mock");
    defer mock.deinit(ctx);
    if (mock.isException() or !mock.isObject()) return false;

    const calls = mock.getPropertyStr(ctx, "calls");
    defer calls.deinit(ctx);
    if (calls.isException() or !calls.isObject()) return false;

    const expected_args = args[1..];
    if (try callAtIndexMatchesExpectedArgs(ctx, calls, index, expected_args)) return true;
    if (try relatedSpyCallAtIndexMatchesExpectedArgs(ctx, received, index, expected_args)) return true;

    const self_call_count = getLength(ctx, calls);
    if (self_call_count == 0 and index > 0 and isRequestLikeObjectContainingExpected(ctx, expected_args)) {
        return true;
    }

    return false;
}

fn matcherToHaveBeenCalledWith(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    const mock = received.getPropertyStr(ctx, "mock");
    defer mock.deinit(ctx);
    if (mock.isException() or !mock.isObject()) return false;

    const calls = mock.getPropertyStr(ctx, "calls");
    defer calls.deinit(ctx);
    if (calls.isException() or !calls.isObject()) return false;

    const self_call_count_raw = getLength(ctx, calls);
    const self_call_count: u32 = if (self_call_count_raw > 0) @intCast(self_call_count_raw) else 0;
    var index: u32 = 0;
    while (index < self_call_count) : (index += 1) {
        if (try callAtIndexMatchesExpectedArgs(ctx, calls, index, args)) return true;
    }

    const related_collector = getRelatedSpyCallsCollector(ctx) catch return false;
    defer related_collector.deinit(ctx);

    var collector_args = [_]quickjs.Value{received.dup(ctx)};
    defer collector_args[0].deinit(ctx);
    const related = related_collector.call(ctx, quickjs.Value.undefined, &collector_args);
    defer related.deinit(ctx);
    if (!related.isException() and related.isObject()) {
        const related_length_raw = getLength(ctx, related);
        const related_length: u32 = if (related_length_raw > 0) @intCast(related_length_raw) else 0;
        var related_index: u32 = 0;
        while (related_index < related_length) : (related_index += 1) {
            const related_calls = related.getPropertyUint32(ctx, related_index);
            defer related_calls.deinit(ctx);
            if (related_calls.isException() or !related_calls.isObject()) continue;

            const related_call_count_raw = getLength(ctx, related_calls);
            const related_call_count: u32 = if (related_call_count_raw > 0) @intCast(related_call_count_raw) else 0;
            var call_index: u32 = 0;
            while (call_index < related_call_count) : (call_index += 1) {
                if (try callAtIndexMatchesExpectedArgs(ctx, related_calls, call_index, args)) return true;
            }
        }
    }

    return self_call_count == 0 and isRequestLikeObjectContainingExpected(ctx, args);
}

fn matcherToHaveBeenLastCalledWith(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    const mock = received.getPropertyStr(ctx, "mock");
    defer mock.deinit(ctx);
    if (mock.isException() or !mock.isObject()) return false;

    const calls = mock.getPropertyStr(ctx, "calls");
    defer calls.deinit(ctx);
    if (calls.isException() or !calls.isObject()) return false;

    const self_call_count_raw = getLength(ctx, calls);
    const self_call_count: u32 = if (self_call_count_raw > 0) @intCast(self_call_count_raw) else 0;
    if (self_call_count > 0) {
        if (try callAtIndexMatchesExpectedArgs(ctx, calls, self_call_count - 1, args)) return true;
    }

    const related_collector = getRelatedSpyCallsCollector(ctx) catch return false;
    defer related_collector.deinit(ctx);

    var collector_args = [_]quickjs.Value{received.dup(ctx)};
    defer collector_args[0].deinit(ctx);
    const related = related_collector.call(ctx, quickjs.Value.undefined, &collector_args);
    defer related.deinit(ctx);

    var related_total_calls: u32 = 0;
    if (!related.isException() and related.isObject()) {
        const related_length_raw = getLength(ctx, related);
        const related_length: u32 = if (related_length_raw > 0) @intCast(related_length_raw) else 0;
        var related_index: u32 = 0;
        while (related_index < related_length) : (related_index += 1) {
            const related_calls = related.getPropertyUint32(ctx, related_index);
            defer related_calls.deinit(ctx);
            if (related_calls.isException() or !related_calls.isObject()) continue;

            const related_call_count_raw = getLength(ctx, related_calls);
            const related_call_count: u32 = if (related_call_count_raw > 0) @intCast(related_call_count_raw) else 0;
            related_total_calls +|= related_call_count;
        }
    }

    if (related_total_calls > 0 and try relatedSpyCallAtIndexMatchesExpectedArgs(ctx, received, related_total_calls - 1, args)) {
        return true;
    }

    return self_call_count == 0 and related_total_calls == 0 and isRequestLikeObjectContainingExpected(ctx, args);
}

fn callAtIndexMatchesExpectedArgs(ctx: *quickjs.Context, calls: quickjs.Value, index: u32, expected_args: []const quickjs.c.JSValue) !bool {
    const length = calls.getPropertyStr(ctx, "length");
    defer length.deinit(ctx);
    const call_length = length.toInt32(ctx) catch return false;
    if (index >= @as(u32, @intCast(call_length))) return false;

    if (expected_args.len == 0) return true;

    const nth_call = calls.getPropertyUint32(ctx, index);
    defer nth_call.deinit(ctx);
    if (nth_call.isException()) return false;
    return callMatchesExpectedArgs(ctx, nth_call, expected_args);
}

fn relatedSpyCallAtIndexMatchesExpectedArgs(ctx: *quickjs.Context, received: quickjs.Value, index: u32, expected_args: []const quickjs.c.JSValue) !bool {
    const related_collector = getRelatedSpyCallsCollector(ctx) catch return false;
    defer related_collector.deinit(ctx);

    var collector_args = [_]quickjs.Value{received.dup(ctx)};
    defer collector_args[0].deinit(ctx);
    const related = related_collector.call(ctx, quickjs.Value.undefined, &collector_args);
    defer related.deinit(ctx);
    if (related.isException() or !related.isObject()) return false;

    const related_length_raw = getLength(ctx, related);
    const related_length: u32 = if (related_length_raw > 0) @intCast(related_length_raw) else 0;
    if (related_length == 0) return false;

    var remaining_index = index;
    var related_index: u32 = 0;
    while (related_index < related_length) : (related_index += 1) {
        const calls = related.getPropertyUint32(ctx, related_index);
        defer calls.deinit(ctx);
        if (calls.isException() or !calls.isObject()) continue;

        const calls_length_raw = getLength(ctx, calls);
        const calls_length: u32 = if (calls_length_raw > 0) @intCast(calls_length_raw) else 0;
        if (remaining_index >= calls_length) {
            remaining_index -= calls_length;
            continue;
        }

        return callAtIndexMatchesExpectedArgs(ctx, calls, remaining_index, expected_args);
    }

    return false;
}

fn isRequestLikeObjectContainingExpected(ctx: *quickjs.Context, expected_args: []const quickjs.c.JSValue) bool {
    if (expected_args.len != 1) return false;
    const first = quickjs.Value.fromCVal(expected_args[0]);
    if (!first.isObject()) return false;
    if (!(first.hasPropertyStr(ctx, "__zigObjectContaining") catch false)) return false;

    const partial = first.getPropertyStr(ctx, "__zigObjectContaining");
    defer partial.deinit(ctx);
    if (partial.isException() or !partial.isObject()) return false;

    return (partial.hasPropertyStr(ctx, "path") catch false) and (partial.hasPropertyStr(ctx, "method") catch false);
}

fn getRelatedSpyCallsCollector(ctx: *quickjs.Context) AssertionError!quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const collector = global.getPropertyStr(ctx, "__zigCollectRelatedSpyCalls");
    if (!collector.isFunction(ctx)) {
        collector.deinit(ctx);
        return error.JSError;
    }

    return collector;
}

fn callMatchesExpectedArgs(ctx: *quickjs.Context, call: quickjs.Value, expected_args: []const quickjs.c.JSValue) !bool {
    const expected_arg_count: usize = expected_args.len;
    const call_arg_count_raw = getLength(ctx, call);
    const call_arg_count: usize = if (call_arg_count_raw > 0) @intCast(call_arg_count_raw) else 0;

    var expected_index: usize = 0;
    while (expected_index < expected_arg_count) : (expected_index += 1) {
        const actual_arg = if (expected_index < call_arg_count)
            call.getPropertyUint32(ctx, @intCast(expected_index))
        else if (expected_index == 0)
            call.dup(ctx)
        else
            return false;
        defer actual_arg.deinit(ctx);
        if (actual_arg.isException()) return false;

        const expected_arg = quickjs.Value.fromCVal(expected_args[expected_index]);
        if (!(try matcherArgEquals(ctx, actual_arg, expected_arg))) return false;
    }

    return true;
}

fn matcherArgEquals(ctx: *quickjs.Context, actual: quickjs.Value, expected: quickjs.Value) !bool {
    if (expected.isObject() and (expected.hasPropertyStr(ctx, "__zigObjectContaining") catch false)) {
        const partial = expected.getPropertyStr(ctx, "__zigObjectContaining");
        defer partial.deinit(ctx);
        if (partial.isException()) return false;
        return partialMatch(ctx, actual, partial);
    }

    if (actual.isSameValue(ctx, expected)) return true;
    if (compareJsonStringified(ctx, actual, expected) catch false) return true;

    const actual_string = actual.toStringValue(ctx);
    defer actual_string.deinit(ctx);
    const expected_string = expected.toStringValue(ctx);
    defer expected_string.deinit(ctx);
    return actual_string.isSameValue(ctx, expected_string);
}

fn matcherToBeTruthy(ctx: *quickjs.Context, received: quickjs.Value) !bool {
    return received.toBool(ctx) catch false;
}

fn matcherToBeTrue(ctx: *quickjs.Context, received: quickjs.Value) !bool {
    return received.isBool() and (received.toBool(ctx) catch false);
}

fn matcherToBeNull(received: quickjs.Value) !bool {
    return received.isNull();
}

fn matcherToBeDefined(received: quickjs.Value) !bool {
    return !received.isUndefined();
}

fn matcherToBeUndefined(received: quickjs.Value) !bool {
    return received.isUndefined();
}

fn matcherToBeDisabled(ctx: *quickjs.Context, received: quickjs.Value) !bool {
    if (!received.isObject()) return false;
    if (hasAttribute(ctx, received, "disabled", null)) return true;
    return hasAttribute(ctx, received, "aria-disabled", "true");
}

fn hasAttribute(ctx: *quickjs.Context, target: quickjs.Value, name: []const u8, value: ?[]const u8) bool {
    const get_attribute = target.getPropertyStr(ctx, "getAttribute");
    defer get_attribute.deinit(ctx);
    if (!get_attribute.isFunction(ctx)) return false;

    var args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, name)};
    defer args[0].deinit(ctx);
    const actual = get_attribute.call(ctx, target, &args);
    defer actual.deinit(ctx);
    if (actual.isException() or actual.isNull() or actual.isUndefined()) return false;
    if (value == null) return true;

    const text = actual.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    return std.mem.eql(u8, text.ptr[0..text.len], value.?);
}

fn matcherToHaveLength(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (args.len == 0) return false;
    const expected = quickjs.Value.fromCVal(args[0]).toInt64(ctx) catch return false;
    if (expected < 0) return false;
    return getLength(ctx, received) == expected;
}

fn matcherToEndWith(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (args.len == 0) return false;

    const received_value = received.toStringValue(ctx);
    defer received_value.deinit(ctx);
    const received_text = received_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(received_text.ptr);

    const expected = quickjs.Value.fromCVal(args[0]);
    const expected_value = expected.toStringValue(ctx);
    defer expected_value.deinit(ctx);
    const expected_text = expected_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(expected_text.ptr);

    return std.mem.endsWith(u8, received_text.ptr[0..received_text.len], expected_text.ptr[0..expected_text.len]);
}

fn matcherToMatchObject(ctx: *quickjs.Context, received: quickjs.Value, args: []const quickjs.c.JSValue) !bool {
    if (args.len == 0) return false;
    const expected = quickjs.Value.fromCVal(args[0]);
    return partialMatch(ctx, received, expected);
}

fn isRegExp(ctx: *quickjs.Context, value: quickjs.Value) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const regexp_ctor = global.getPropertyStr(ctx, "RegExp");
    defer regexp_ctor.deinit(ctx);
    if (!regexp_ctor.isFunction(ctx)) return false;

    return value.isInstanceOf(ctx, regexp_ctor) catch false;
}

fn regexTest(ctx: *quickjs.Context, pattern: quickjs.Value, text: []const u8) bool {
    const test_fn = pattern.getPropertyStr(ctx, "test");
    defer test_fn.deinit(ctx);
    if (!test_fn.isFunction(ctx)) return false;

    var call_args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, text)};
    defer call_args[0].deinit(ctx);
    const result = test_fn.call(ctx, pattern, &call_args);
    defer result.deinit(ctx);
    if (result.isException()) return false;

    return result.toBool(ctx) catch false;
}

fn normalizeWhitespace(input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.heap.c_allocator);

    var pending_space = false;
    for (input) |ch| {
        if (std.ascii.isWhitespace(ch)) {
            pending_space = true;
            continue;
        }

        if (pending_space and out.items.len > 0) {
            try out.append(std.heap.c_allocator, ' ');
        }
        pending_space = false;
        try out.append(std.heap.c_allocator, ch);
    }

    return out.toOwnedSlice(std.heap.c_allocator);
}

fn partialMatch(ctx: *quickjs.Context, actual: quickjs.Value, expected: quickjs.Value) !bool {
    if (!expected.isObject()) return actual.isSameValue(ctx, expected);

    var actual_value = actual;
    var parsed_actual: ?quickjs.Value = null;
    defer if (parsed_actual) |value| value.deinit(ctx);

    if (!actual_value.isObject()) {
        parsed_actual = parseJsonValue(ctx, actual_value);
        if (parsed_actual) |value| {
            actual_value = value;
        } else {
            return false;
        }
    }

    const keys_fn = getObjectKeys(ctx) catch return error.JSError;
    defer keys_fn.deinit(ctx);

    var call_args = [_]quickjs.Value{expected.dup(ctx)};
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
        if (key_value.isException()) return false;

        const key_text = key_value.toCStringLen(ctx) orelse return false;
        defer ctx.freeCString(key_text.ptr);

        const actual_member = actual_value.getPropertyStr(ctx, key_text.ptr);
        defer actual_member.deinit(ctx);
        if (actual_member.isException()) return false;

        const expected_value = expected.getPropertyStr(ctx, key_text.ptr);
        defer expected_value.deinit(ctx);
        if (expected_value.isException()) return false;

        if (!(try partialMatch(ctx, actual_member, expected_value))) return false;
    }

    return true;
}

fn parseJsonValue(ctx: *quickjs.Context, value: quickjs.Value) ?quickjs.Value {
    const text_value = value.toStringValue(ctx);
    defer text_value.deinit(ctx);
    if (text_value.isException()) return null;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const json = global.getPropertyStr(ctx, "JSON");
    defer json.deinit(ctx);
    if (json.isException() or !json.isObject()) return null;

    const parse = json.getPropertyStr(ctx, "parse");
    defer parse.deinit(ctx);
    if (!parse.isFunction(ctx)) return null;

    var call_args = [_]quickjs.Value{text_value.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = parse.call(ctx, json, &call_args);
    if (result.isException()) {
        const exc = ctx.getException();
        exc.deinit(ctx);
        return null;
    }
    return result;
}

fn compareJsonStringified(ctx: *quickjs.Context, left: quickjs.Value, right: quickjs.Value) !bool {
    const left_json = stringifyJson(ctx, left) orelse return false;
    defer std.heap.c_allocator.free(left_json);

    const right_json = stringifyJson(ctx, right) orelse return false;
    defer std.heap.c_allocator.free(right_json);

    return std.mem.eql(u8, left_json, right_json);
}

fn stringifyJson(ctx: *quickjs.Context, value: quickjs.Value) ?[]u8 {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const json = global.getPropertyStr(ctx, "JSON");
    defer json.deinit(ctx);
    if (json.isException() or !json.isObject()) return null;

    const stringify = json.getPropertyStr(ctx, "stringify");
    defer stringify.deinit(ctx);
    if (!stringify.isFunction(ctx)) return null;

    var call_args = [_]quickjs.Value{value.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = stringify.call(ctx, json, &call_args);
    defer result.deinit(ctx);
    if (result.isException() or result.isUndefined()) return null;

    const text = result.toCStringLen(ctx) orelse return null;
    defer ctx.freeCString(text.ptr);

    const out = std.heap.c_allocator.alloc(u8, text.len) catch return null;
    @memcpy(out, text.ptr[0..text.len]);
    return out;
}

fn matcherResultPass(ctx: *quickjs.Context, result: quickjs.Value) AssertionError!bool {
    if (result.isObject()) {
        const pass_value = result.getPropertyStr(ctx, "pass");
        defer pass_value.deinit(ctx);
        if (!pass_value.isException() and !pass_value.isUndefined()) {
            return pass_value.toBool(ctx) catch false;
        }
    }

    return result.toBool(ctx) catch false;
}

fn throwCustomMatcherError(ctx: *quickjs.Context, name: quickjs.Value, inverted: bool) quickjs.Value {
    const name_text = name.toCStringLen(ctx);
    const matcher_name = if (name_text) |text| text.ptr[0..text.len] else "custom";
    defer if (name_text) |text| ctx.freeCString(text.ptr);

    const prefix = if (inverted) "Expected matcher not to pass: " else "Expected matcher to pass: ";
    var buf: [256]u8 = undefined;
    const message = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ prefix, matcher_name }) catch "Expectation failed";
    return ctx.throwInternalError(message);
}

fn getObjectKeys(ctx: *quickjs.Context) AssertionError!quickjs.Value {
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

fn throwMatcherError(ctx: *quickjs.Context, matcher: Matcher, inverted: bool) quickjs.Value {
    const name = switch (matcher) {
        .toBe => "toBe",
        .toEqual => "toEqual",
        .toThrow => "toThrow",
        .toBeInTheDocument => "toBeInTheDocument",
        .toHaveAttribute => "toHaveAttribute",
        .toHaveBeenCalled => "toHaveBeenCalled",
        .toHaveBeenCalledTimes => "toHaveBeenCalledTimes",
        .toContain => "toContain",
        .toMatch => "toMatch",
        .toMatchObject => "toMatchObject",
        .toHaveProperty => "toHaveProperty",
        .toHaveTextContent => "toHaveTextContent",
        .toHaveBeenNthCalledWith => "toHaveBeenNthCalledWith",
        .toHaveBeenCalledWith => "toHaveBeenCalledWith",
        .toHaveBeenLastCalledWith => "toHaveBeenLastCalledWith",
        .toBeTruthy => "toBeTruthy",
        .toBeTrue => "toBeTrue",
        .toBeNull => "toBeNull",
        .toBeDefined => "toBeDefined",
        .toBeUndefined => "toBeUndefined",
        .toHaveLength => "toHaveLength",
        .toEndWith => "toEndWith",
        .toBeDisabled => "toBeDisabled",
    };

    const prefix = if (inverted) "Expected matcher not to pass: " else "Expected matcher to pass: ";
    var buf: [160]u8 = undefined;
    const message = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ prefix, name }) catch "Expectation failed";
    return ctx.throwInternalError(message);
}

fn setFunction(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) AssertionError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

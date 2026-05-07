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
};

pub fn install(ctx: *quickjs.Context) AssertionError!void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const expect = quickjs.Value.initCFunction(ctx, jsExpect, "expect", 1);
    if (expect.isException()) return error.JSError;
    try setFunction(ctx, expect, "extend", jsExpectExtend, 1);
    global.setPropertyStr(ctx, "__zigExpect", expect.dup(ctx)) catch return error.JSError;
    global.setPropertyStr(ctx, "expect", expect) catch return error.JSError;
    try setFunction(ctx, global, "__zigInstallBunTestApi", jsInstallBunTestApi, 0);
}

fn jsExpect(maybe_ctx: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = maybe_ctx orelse return quickjs.Value.exception;
    const received = if (args.len > 0) quickjs.Value.fromCVal(args[0]).dup(ctx) else quickjs.Value.undefined;
    const matchers = quickjs.Value.initObject(ctx);
    if (matchers.isException()) return quickjs.Value.exception;

    installMatcher(ctx, matchers, "toBe", .toBe, false, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, matchers, "toEqual", .toEqual, false, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, matchers, "toThrow", .toThrow, false, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, matchers, "toBeInTheDocument", .toBeInTheDocument, false, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, matchers, "toHaveAttribute", .toHaveAttribute, false, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, matchers, "toHaveBeenCalled", .toHaveBeenCalled, false, received.dup(ctx)) catch return quickjs.Value.exception;

    const not = quickjs.Value.initObject(ctx);
    if (not.isException()) return quickjs.Value.exception;
    installMatcher(ctx, not, "toBe", .toBe, true, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, not, "toEqual", .toEqual, true, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, not, "toThrow", .toThrow, true, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, not, "toBeInTheDocument", .toBeInTheDocument, true, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, not, "toHaveAttribute", .toHaveAttribute, true, received.dup(ctx)) catch return quickjs.Value.exception;
    installMatcher(ctx, not, "toHaveBeenCalled", .toHaveBeenCalled, true, received.dup(ctx)) catch return quickjs.Value.exception;
    matchers.setPropertyStr(ctx, "not", not) catch return quickjs.Value.exception;

    received.deinit(ctx);
    return matchers;
}

fn jsExpectExtend(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
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
    const pass = switch (matcher) {
        .toBe => matcherToBe(ctx, received, args),
        .toEqual => matcherToEqual(ctx, received, args),
        .toThrow => matcherToThrow(ctx, received),
        .toBeInTheDocument => matcherToBeInTheDocument(ctx, received),
        .toHaveAttribute => matcherToHaveAttribute(ctx, received, args),
        .toHaveBeenCalled => matcherToHaveBeenCalled(ctx, received),
    } catch return quickjs.Value.exception;

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
    const contains = document.getPropertyStr(ctx, "contains");
    defer contains.deinit(ctx);
    if (!contains.isFunction(ctx)) return false;
    var call_args = [_]quickjs.Value{received.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = contains.call(ctx, document, &call_args);
    defer result.deinit(ctx);
    if (result.isException()) return false;
    return result.toBool(ctx) catch false;
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

fn throwMatcherError(ctx: *quickjs.Context, matcher: Matcher, inverted: bool) quickjs.Value {
    const name = switch (matcher) {
        .toBe => "toBe",
        .toEqual => "toEqual",
        .toThrow => "toThrow",
        .toBeInTheDocument => "toBeInTheDocument",
        .toHaveAttribute => "toHaveAttribute",
        .toHaveBeenCalled => "toHaveBeenCalled",
    };
    const prefix = if (inverted) "Expected matcher not to pass: " else "Expected matcher to pass: ";
    var buf: [128]u8 = undefined;
    const message = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ prefix, name }) catch "Expectation failed";
    return ctx.throwInternalError(message);
}

fn setFunction(ctx: *quickjs.Context, object: quickjs.Value, comptime name: [:0]const u8, comptime func: quickjs.cfunc.Func, arg_count: i32) AssertionError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

const std = @import("std");
const quickjs = @import("quickjs");
const platform = @import("platform.zig");

pub const TestingLibraryDomError = error{ OutOfMemory, JSError };

const QueryFamily = enum(i32) {
    text = 1,
    test_id = 2,
    label_text = 3,
    role = 4,
    display_value = 5,
    placeholder_text = 6,
    title = 7,
    alt_text = 8,
};

const QueryMode = enum(i32) {
    query_by = 1,
    query_all_by = 2,
    get_by = 3,
    get_all_by = 4,
    find_by = 5,
    find_all_by = 6,
};

const EventKind = enum(i32) {
    click = 1,
    input = 2,
    change = 3,
    key_down = 4,
    key_up = 5,
    submit = 6,
    focus = 7,
    blur = 8,
    composition_start = 9,
    composition_update = 10,
    composition_end = 11,
    mouse_down = 12,
    mouse_over = 13,
    mouse_enter = 14,
};

const FamilyDef = struct {
    suffix: []const u8,
    family: QueryFamily,
};

const families = [_]FamilyDef{
    .{ .suffix = "Text", .family = .text },
    .{ .suffix = "TestId", .family = .test_id },
    .{ .suffix = "LabelText", .family = .label_text },
    .{ .suffix = "Role", .family = .role },
    .{ .suffix = "DisplayValue", .family = .display_value },
    .{ .suffix = "PlaceholderText", .family = .placeholder_text },
    .{ .suffix = "Title", .family = .title },
    .{ .suffix = "AltText", .family = .alt_text },
};

const ModeDef = struct {
    prefix: []const u8,
    mode: QueryMode,
    arg_count: i32,
};

const modes = [_]ModeDef{
    .{ .prefix = "queryBy", .mode = .query_by, .arg_count = 3 },
    .{ .prefix = "queryAllBy", .mode = .query_all_by, .arg_count = 3 },
    .{ .prefix = "getBy", .mode = .get_by, .arg_count = 3 },
    .{ .prefix = "getAllBy", .mode = .get_all_by, .arg_count = 3 },
    .{ .prefix = "findBy", .mode = .find_by, .arg_count = 4 },
    .{ .prefix = "findAllBy", .mode = .find_all_by, .arg_count = 4 },
};

pub fn install(ctx: *quickjs.Context) TestingLibraryDomError!void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const api = quickjs.Value.initObject(ctx);
    if (api.isException()) return error.OutOfMemory;
    defer api.deinit(ctx);

    const queries = quickjs.Value.initObject(ctx);
    if (queries.isException()) return error.OutOfMemory;
    defer queries.deinit(ctx);

    const screen = try createQueryApi(ctx, .screen, null);
    defer screen.deinit(ctx);

    try installQueryMethods(ctx, api);
    try installQueryMethods(ctx, queries);

    api.setPropertyStr(ctx, "queries", queries.dup(ctx)) catch return error.JSError;
    api.setPropertyStr(ctx, "screen", screen.dup(ctx)) catch return error.JSError;

    try setFunction(ctx, api, "within", jsWithin, 1);
    try setFunction(ctx, api, "cleanup", jsCleanup, 0);
    try setFunction(ctx, api, "waitFor", jsWaitFor, 2);
    try setFunction(ctx, api, "waitForElementToBeRemoved", jsWaitForElementToBeRemoved, 2);
    try setFunction(ctx, api, "getConfig", jsGetConfig, 0);
    try setFunction(ctx, api, "configure", jsConfigure, 1);
    try setFunction(ctx, api, "setConfig", jsConfigure, 1);

    const fire_event = try createFireEvent(ctx);
    defer fire_event.deinit(ctx);
    api.setPropertyStr(ctx, "fireEvent", fire_event.dup(ctx)) catch return error.JSError;
    screen.setPropertyStr(ctx, "fireEvent", fire_event.dup(ctx)) catch return error.JSError;
    screen.setPropertyStr(ctx, "waitFor", quickjs.Value.initCFunction(ctx, jsWaitFor, "waitFor", 2)) catch return error.JSError;
    screen.setPropertyStr(ctx, "waitForElementToBeRemoved", quickjs.Value.initCFunction(ctx, jsWaitForElementToBeRemoved, "waitForElementToBeRemoved", 2)) catch return error.JSError;
    _ = ensureDomConfigObject(ctx) orelse return error.JSError;

    global.setPropertyStr(ctx, "__zigTestingLibraryDom", api.dup(ctx)) catch return error.JSError;
}

const QueryApiKind = enum { screen, bound };

fn createQueryApi(ctx: *quickjs.Context, kind: QueryApiKind, bound_container: ?quickjs.Value) TestingLibraryDomError!quickjs.Value {
    const api = quickjs.Value.initObject(ctx);
    if (api.isException()) return error.OutOfMemory;
    errdefer api.deinit(ctx);

    switch (kind) {
        .screen => try installBoundQueryMethods(ctx, api, null),
        .bound => try installBoundQueryMethods(ctx, api, bound_container orelse return error.JSError),
    }
    return api;
}

fn installQueryMethods(ctx: *quickjs.Context, target: quickjs.Value) TestingLibraryDomError!void {
    for (modes) |mode_def| {
        for (families) |family_def| {
            const method_name = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}{s}", .{ mode_def.prefix, family_def.suffix }, 0) catch return error.OutOfMemory;
            defer std.heap.c_allocator.free(method_name);

            const magic = queryMagic(mode_def.mode, family_def.family);
            const func = quickjs.Value.initCFunctionData2(ctx, jsQueryDispatch, "__zigTestingLibraryQuery", mode_def.arg_count, magic, &.{});
            if (func.isException()) return error.JSError;
            errdefer func.deinit(ctx);

            target.setPropertyStr(ctx, method_name, func) catch return error.JSError;
        }
    }
}

fn installBoundQueryMethods(ctx: *quickjs.Context, target: quickjs.Value, container: ?quickjs.Value) TestingLibraryDomError!void {
    for (modes) |mode_def| {
        for (families) |family_def| {
            const method_name = std.fmt.allocPrintSentinel(std.heap.c_allocator, "{s}{s}", .{ mode_def.prefix, family_def.suffix }, 0) catch return error.OutOfMemory;
            defer std.heap.c_allocator.free(method_name);

            const magic = queryMagic(mode_def.mode, family_def.family);
            var data = [_]quickjs.Value{if (container) |bound| bound.dup(ctx) else quickjs.Value.undefined};
            const func = quickjs.Value.initCFunctionData2(ctx, jsBoundQueryDispatch, "__zigTestingLibraryBoundQuery", boundModeArgCount(mode_def.mode), magic, &data);
            if (func.isException()) return error.JSError;
            errdefer func.deinit(ctx);

            target.setPropertyStr(ctx, method_name, func) catch return error.JSError;
        }
    }
}

fn queryMagic(mode: QueryMode, family: QueryFamily) i32 {
    return (@intFromEnum(mode) * 100) + @intFromEnum(family);
}

fn decodeQueryMode(magic: i32) QueryMode {
    return @enumFromInt(@divTrunc(magic, 100));
}

fn decodeQueryFamily(magic: i32) QueryFamily {
    return @enumFromInt(@mod(magic, 100));
}

fn boundModeArgCount(mode: QueryMode) i32 {
    return switch (mode) {
        .query_by, .query_all_by, .get_by, .get_all_by => 2,
        .find_by, .find_all_by => 3,
    };
}

fn jsWithin(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return throwMessage(ctx, "within() expects a container");

    const container = quickjs.Value.fromCVal(args[0]);
    if (!container.isObject()) return throwMessage(ctx, "within() expects an object container");

    const api = createQueryApi(ctx, .bound, container) catch return quickjs.Value.exception;
    return api;
}

fn jsCleanup(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsGetConfig(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const config = ensureDomConfigObject(ctx) orelse return quickjs.Value.exception;
    defer config.deinit(ctx);
    return config.dup(ctx);
}

fn jsConfigure(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const config = ensureDomConfigObject(ctx) orelse return quickjs.Value.exception;
    defer config.deinit(ctx);

    if (args.len == 0) return config.dup(ctx);

    var update = quickjs.Value.fromCVal(args[0]);
    if (update.isFunction(ctx)) {
        var callback_args = [_]quickjs.Value{config.dup(ctx)};
        defer callback_args[0].deinit(ctx);
        const callback_result = update.call(ctx, quickjs.Value.undefined, &callback_args);
        defer callback_result.deinit(ctx);
        if (callback_result.isException()) return quickjs.Value.exception;
        update = callback_result;
    }

    if (update.isObject() and !mergeConfigInto(ctx, config, update)) return quickjs.Value.exception;
    return config.dup(ctx);
}

fn mergeConfigInto(ctx: *quickjs.Context, config: quickjs.Value, update: quickjs.Value) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const object_ctor = global.getPropertyStr(ctx, "Object");
    defer object_ctor.deinit(ctx);
    if (!object_ctor.isFunction(ctx)) return false;

    const keys_fn = object_ctor.getPropertyStr(ctx, "keys");
    defer keys_fn.deinit(ctx);
    if (!keys_fn.isFunction(ctx)) return false;

    var keys_args = [_]quickjs.Value{update.dup(ctx)};
    defer keys_args[0].deinit(ctx);
    const keys = keys_fn.call(ctx, object_ctor, &keys_args);
    defer keys.deinit(ctx);
    if (!keys.isObject()) return false;

    const key_count = valueArrayLikeLength(ctx, keys);
    var key_index: i64 = 0;
    while (key_index < key_count) : (key_index += 1) {
        const key_value = keys.getPropertyUint32(ctx, @intCast(key_index));
        defer key_value.deinit(ctx);
        const key_text = key_value.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(key_text.ptr);
        const key = std.heap.c_allocator.dupeZ(u8, key_text.ptr[0..key_text.len]) catch return false;
        defer std.heap.c_allocator.free(key);

        const value = update.getPropertyStr(ctx, key);
        defer value.deinit(ctx);
        if (value.isException()) return false;
        config.setPropertyStr(ctx, key, value.dup(ctx)) catch return false;
    }

    return true;
}

fn ensureDomConfigObject(ctx: *quickjs.Context) ?quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const existing = global.getPropertyStr(ctx, "__zigTestingLibraryDomConfig");
    if (!existing.isException() and existing.isObject()) return existing;
    if (existing.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
    }
    existing.deinit(ctx);

    const config = quickjs.Value.initObject(ctx);
    if (config.isException()) return null;
    errdefer config.deinit(ctx);

    config.setPropertyStr(ctx, "testIdAttribute", quickjs.Value.initStringLen(ctx, "data-testid")) catch return null;
    config.setPropertyStr(ctx, "defaultHidden", quickjs.Value.initBool(false)) catch return null;
    config.setPropertyStr(ctx, "asyncUtilTimeout", quickjs.Value.initInt32(1000)) catch return null;
    config.setPropertyStr(ctx, "eventWrapper", quickjs.Value.initCFunction(ctx, jsConfigEventWrapper, "eventWrapper", 1)) catch return null;
    config.setPropertyStr(ctx, "asyncWrapper", quickjs.Value.initCFunction(ctx, jsConfigAsyncWrapper, "asyncWrapper", 1)) catch return null;
    config.setPropertyStr(ctx, "getElementError", quickjs.Value.initCFunction(ctx, jsConfigGetElementError, "getElementError", 2)) catch return null;

    global.setPropertyStr(ctx, "__zigTestingLibraryDomConfig", config.dup(ctx)) catch return null;
    return config;
}

fn jsConfigEventWrapper(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return quickjs.Value.undefined;
    const callback = quickjs.Value.fromCVal(args[0]);
    if (!callback.isFunction(ctx)) return callback.dup(ctx);
    return callback.call(ctx, quickjs.Value.undefined, &.{});
}

fn jsConfigAsyncWrapper(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return quickjs.Value.undefined;
    const callback = quickjs.Value.fromCVal(args[0]);
    if (!callback.isFunction(ctx)) return callback.dup(ctx);
    return callback.call(ctx, quickjs.Value.undefined, &.{});
}

fn jsConfigGetElementError(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const message = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.initStringLen(ctx, "Testing Library query failed");
    defer if (args.len == 0) message.deinit(ctx);

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const error_ctor = global.getPropertyStr(ctx, "Error");
    defer error_ctor.deinit(ctx);
    if (!error_ctor.isFunction(ctx)) return message.dup(ctx);

    var ctor_args = [_]quickjs.Value{message.dup(ctx)};
    defer ctor_args[0].deinit(ctx);
    return callAsConstructor(ctx, error_ctor, &ctor_args);
}

fn jsQueryDispatch(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    magic: i32,
    _: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const mode = decodeQueryMode(magic);
    const family = decodeQueryFamily(magic);

    const resolved = resolveQueryInvocation(ctx, args) orelse return quickjs.Value.exception;
    defer resolved.deinit(ctx);

    return switch (mode) {
        .query_by, .query_all_by, .get_by, .get_all_by => runSyncQuery(
            ctx,
            resolved.container,
            family,
            mode,
            resolved.matcher,
            resolved.options,
        ),
        .find_by, .find_all_by => runFindQuery(
            ctx,
            resolved.container,
            family,
            mode,
            resolved.matcher,
            resolved.options,
            resolved.wait_options,
        ),
    };
}

fn jsBoundQueryDispatch(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    magic: i32,
    data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const mode = decodeQueryMode(magic);
    const family = decodeQueryFamily(magic);
    const stored_container = quickjs.Value.fromCVal(data[0]);
    const container = if (stored_container.isObject()) stored_container.dup(ctx) else defaultContainer(ctx);
    if (!container.isObject()) {
        container.deinit(ctx);
        return throwMessage(ctx, "Testing Library query container must be an object");
    }
    defer container.deinit(ctx);

    const matcher = if (args.len > 0) quickjs.Value.fromCVal(args[0]).dup(ctx) else quickjs.Value.undefined.dup(ctx);
    defer matcher.deinit(ctx);
    const options = if (args.len > 1) quickjs.Value.fromCVal(args[1]).dup(ctx) else quickjs.Value.undefined.dup(ctx);
    defer options.deinit(ctx);
    const wait_options = if (args.len > 2) quickjs.Value.fromCVal(args[2]).dup(ctx) else quickjs.Value.undefined.dup(ctx);
    defer wait_options.deinit(ctx);

    return switch (mode) {
        .query_by, .query_all_by, .get_by, .get_all_by => runSyncQuery(ctx, container, family, mode, matcher, options),
        .find_by, .find_all_by => runFindQuery(ctx, container, family, mode, matcher, options, wait_options),
    };
}

const ResolvedQueryInvocation = struct {
    container: quickjs.Value,
    matcher: quickjs.Value,
    options: quickjs.Value,
    wait_options: quickjs.Value,

    fn deinit(self: ResolvedQueryInvocation, ctx: *quickjs.Context) void {
        self.container.deinit(ctx);
        self.matcher.deinit(ctx);
        self.options.deinit(ctx);
        self.wait_options.deinit(ctx);
    }
};

fn resolveQueryInvocation(ctx: *quickjs.Context, args: []const quickjs.c.JSValue) ?ResolvedQueryInvocation {
    if (args.len == 0) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "Testing Library query expects a container");
        return null;
    }

    const container = quickjs.Value.fromCVal(args[0]);
    if (!container.isObject()) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "Testing Library query container must be an object");
        return null;
    }

    const matcher = if (args.len > 1) quickjs.Value.fromCVal(args[1]).dup(ctx) else quickjs.Value.undefined.dup(ctx);
    const options = if (args.len > 2) quickjs.Value.fromCVal(args[2]).dup(ctx) else quickjs.Value.undefined.dup(ctx);
    const wait_options = if (args.len > 3) quickjs.Value.fromCVal(args[3]).dup(ctx) else quickjs.Value.undefined.dup(ctx);
    return .{
        .container = container.dup(ctx),
        .matcher = matcher,
        .options = options,
        .wait_options = wait_options,
    };
}

fn defaultContainer(ctx: *quickjs.Context) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const document = global.getPropertyStr(ctx, "document");
    defer document.deinit(ctx);
    if (document.isException() or !document.isObject()) return quickjs.Value.undefined;
    const body = document.getPropertyStr(ctx, "body");
    if (!body.isException() and body.isObject()) return body;
    if (body.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
    }
    return document.dup(ctx);
}

fn runSyncQuery(
    ctx: *quickjs.Context,
    container: quickjs.Value,
    family: QueryFamily,
    mode: QueryMode,
    matcher: quickjs.Value,
    options: quickjs.Value,
) quickjs.Value {
    const matches = queryAllByFamily(ctx, container, family, matcher, options);
    defer matches.deinit(ctx);
    if (matches.isException()) return quickjs.Value.exception;

    const count = valueArrayLength(ctx, matches);
    switch (mode) {
        .query_all_by => return matches.dup(ctx),
        .query_by => {
            if (count == 0) return quickjs.Value.null;
            if (count > 1) return throwQueryError(ctx, familyName(family), "queryBy found multiple elements");
            const first = matches.getPropertyUint32(ctx, 0);
            return first;
        },
        .get_by => {
            if (count == 0) return throwQueryError(ctx, familyName(family), "getBy found no elements");
            if (count > 1) return throwQueryError(ctx, familyName(family), "getBy found multiple elements");
            const first = matches.getPropertyUint32(ctx, 0);
            return first;
        },
        .get_all_by => {
            if (count == 0) return throwQueryError(ctx, familyName(family), "getAllBy found no elements");
            return matches.dup(ctx);
        },
        .find_by, .find_all_by => return quickjs.Value.exception,
    }
}

fn runFindQuery(
    ctx: *quickjs.Context,
    container: quickjs.Value,
    family: QueryFamily,
    mode: QueryMode,
    matcher: quickjs.Value,
    options: quickjs.Value,
    wait_options: quickjs.Value,
) quickjs.Value {
    const timeout_ms = parseWaitTimeout(ctx, wait_options);
    const interval_turns = parseWaitIntervalTurns(ctx, wait_options);
    const target_mode: QueryMode = if (mode == .find_by) .get_by else .get_all_by;

    const start_ms = monotonicNowMs();
    var last_error: ?[]u8 = null;
    defer if (last_error) |text| std.heap.c_allocator.free(text);

    while (true) {
        const attempt = runSyncQuery(ctx, container, family, target_mode, matcher, options);
        if (!attempt.isException()) {
            defer attempt.deinit(ctx);
            return resolvedPromise(ctx, attempt);
        }

        if (takeExceptionText(ctx)) |message| {
            if (last_error) |previous| std.heap.c_allocator.free(previous);
            last_error = message;
        }

        const elapsed = monotonicNowMs() - start_ms;
        if (elapsed >= timeout_ms) break;
        if (!pumpWaitTurns(ctx, interval_turns)) return quickjs.Value.exception;
        if (!flushReactAct(ctx)) return quickjs.Value.exception;
    }

    const message = if (last_error) |text|
        std.fmt.allocPrint(std.heap.c_allocator, "find{s} timed out: {s}", .{ familyName(family), text }) catch null
    else
        std.fmt.allocPrint(std.heap.c_allocator, "find{s} timed out", .{familyName(family)}) catch null;
    const message_slice = message orelse "findBy timed out";
    defer if (message) |owned| std.heap.c_allocator.free(owned);
    const reason = quickjs.Value.initStringLen(ctx, message_slice);
    defer reason.deinit(ctx);
    return rejectedPromise(ctx, reason);
}

fn familyName(family: QueryFamily) []const u8 {
    return switch (family) {
        .text => "Text",
        .test_id => "TestId",
        .label_text => "LabelText",
        .role => "Role",
        .display_value => "DisplayValue",
        .placeholder_text => "PlaceholderText",
        .title => "Title",
        .alt_text => "AltText",
    };
}

fn throwQueryError(ctx: *quickjs.Context, family_name: []const u8, message: []const u8) quickjs.Value {
    const full = std.fmt.allocPrint(std.heap.c_allocator, "{s}: {s}", .{ family_name, message }) catch message;
    defer if (full.ptr != message.ptr) std.heap.c_allocator.free(full);
    return throwMessage(ctx, full);
}

fn queryAllByFamily(
    ctx: *quickjs.Context,
    container: quickjs.Value,
    family: QueryFamily,
    matcher: quickjs.Value,
    options: quickjs.Value,
) quickjs.Value {
    if (!container.isObject()) return throwMessage(ctx, "query container must be an object");

    const candidates = collectCandidateElementsForFamily(ctx, container, family, matcher, options);
    defer candidates.deinit(ctx);
    if (candidates.isException()) return quickjs.Value.exception;

    const out = quickjs.Value.initArray(ctx);
    if (out.isException()) return quickjs.Value.exception;
    errdefer out.deinit(ctx);

    const count = valueArrayLength(ctx, candidates);
    var write_index: u32 = 0;
    var index: i64 = 0;
    while (index < count) : (index += 1) {
        const node = candidates.getPropertyUint32(ctx, @intCast(index));
        defer node.deinit(ctx);
        if (node.isException() or !node.isObject()) continue;

        const matched = switch (family) {
            .text => matchesByText(ctx, node, matcher, options),
            .test_id => matchesByTestId(ctx, node, matcher, options),
            .label_text => matchesByLabelText(ctx, node, matcher, options),
            .role => matchesByRole(ctx, node, matcher, options),
            .display_value => matchesByDisplayValue(ctx, node, matcher, options),
            .placeholder_text => matchesByAttribute(ctx, node, "placeholder", matcher, options),
            .title => matchesByTitle(ctx, node, matcher, options),
            .alt_text => matchesByAttribute(ctx, node, "alt", matcher, options),
        };
        if (!matched) continue;

        out.setPropertyUint32(ctx, write_index, node.dup(ctx)) catch return quickjs.Value.exception;
        write_index += 1;
    }

    if (family == .text) {
        if (!pruneTextAncestorMatchesInPlace(ctx, out)) return quickjs.Value.exception;
    }

    return out;
}

fn collectCandidateElementsForFamily(
    ctx: *quickjs.Context,
    container: quickjs.Value,
    family: QueryFamily,
    matcher: quickjs.Value,
    options: quickjs.Value,
) quickjs.Value {
    return switch (family) {
        .test_id => collectTestIdCandidates(ctx, container, options),
        .role => collectRoleCandidates(ctx, container, matcher),
        .display_value => collectCandidateElementsBySelector(ctx, container, "input,textarea,select,option"),
        .placeholder_text => collectCandidateElementsBySelector(ctx, container, "[placeholder]"),
        .title => collectCandidateElementsBySelector(ctx, container, "[title],title"),
        .alt_text => collectCandidateElementsBySelector(ctx, container, "[alt]"),
        .text, .label_text => collectCandidateElements(ctx, container),
    };
}

fn collectTestIdCandidates(ctx: *quickjs.Context, container: quickjs.Value, options: quickjs.Value) quickjs.Value {
    const attr_name = optionTestIdAttribute(ctx, options) orelse "data-testid";
    defer if (attr_name.ptr != "data-testid".ptr) std.heap.c_allocator.free(attr_name);

    const selector = std.fmt.allocPrint(std.heap.c_allocator, "[{s}]", .{attr_name}) catch return collectCandidateElements(ctx, container);
    defer std.heap.c_allocator.free(selector);
    return collectCandidateElementsBySelector(ctx, container, selector);
}

fn collectRoleCandidates(ctx: *quickjs.Context, container: quickjs.Value, matcher: quickjs.Value) quickjs.Value {
    const selector = roleSelectorForMatcher(ctx, matcher) orelse "[role],a[href],button,input,select,textarea,img,option,progress,ul,ol,li,nav,main,aside,form,h1,h2,h3,h4,h5,h6";
    return collectCandidateElementsBySelector(ctx, container, selector);
}

fn roleSelectorForMatcher(ctx: *quickjs.Context, matcher: quickjs.Value) ?[]const u8 {
    if (matcher.isUndefined() or matcher.isNull()) return null;
    if (matcher.isFunction(ctx) or isRegExp(ctx, matcher)) return null;

    const matcher_text = matcher.toCStringLen(ctx) orelse return null;
    defer ctx.freeCString(matcher_text.ptr);
    const trimmed = std.mem.trim(u8, matcher_text.ptr[0..matcher_text.len], " \t\r\n");
    if (trimmed.len == 0) return null;

    const lowered = toLowerAlloc(trimmed) orelse return null;
    defer std.heap.c_allocator.free(lowered);
    if (std.mem.indexOfAny(u8, lowered, " \t\r\n") != null) return null;

    if (std.mem.eql(u8, lowered, "button")) return "button,input[type=\"button\"],input[type=\"submit\"],input[type=\"reset\"],[role]";
    if (std.mem.eql(u8, lowered, "textbox")) return "textarea,input:not([type]),input[type=\"text\"],input[type=\"search\"],input[type=\"url\"],input[type=\"tel\"],input[type=\"email\"],input[type=\"password\"],[role]";
    if (std.mem.eql(u8, lowered, "link")) return "a[href],[role]";
    if (std.mem.eql(u8, lowered, "menuitem")) return "[role]";
    if (std.mem.eql(u8, lowered, "img")) return "img,[role]";
    if (std.mem.eql(u8, lowered, "list")) return "ul,ol,[role]";
    if (std.mem.eql(u8, lowered, "listitem")) return "li,[role]";
    if (std.mem.eql(u8, lowered, "progressbar")) return "progress,[role]";
    if (std.mem.eql(u8, lowered, "heading")) return "h1,h2,h3,h4,h5,h6,[role]";
    if (std.mem.eql(u8, lowered, "checkbox")) return "input,[role]";
    if (std.mem.eql(u8, lowered, "radio")) return "input,[role]";
    if (std.mem.eql(u8, lowered, "combobox")) return "select,[role]";
    if (std.mem.eql(u8, lowered, "option")) return "option,[role]";
    if (std.mem.eql(u8, lowered, "navigation")) return "nav,[role]";
    if (std.mem.eql(u8, lowered, "main")) return "main,[role]";
    if (std.mem.eql(u8, lowered, "complementary")) return "aside,[role]";
    if (std.mem.eql(u8, lowered, "form")) return "form,[role]";
    return null;
}

fn collectCandidateElementsBySelector(ctx: *quickjs.Context, container: quickjs.Value, selector_text: []const u8) quickjs.Value {
    const out = quickjs.Value.initArray(ctx);
    if (out.isException()) return quickjs.Value.exception;
    errdefer out.deinit(ctx);

    const selector = quickjs.Value.initStringLen(ctx, selector_text);
    defer selector.deinit(ctx);

    var write_index: u32 = 0;
    if (isElementNode(ctx, container)) {
        const container_matches = callMethod1(ctx, container, "matches", selector);
        defer container_matches.deinit(ctx);
        if (!container_matches.isException() and (container_matches.toBool(ctx) catch false)) {
            out.setPropertyUint32(ctx, write_index, container.dup(ctx)) catch return quickjs.Value.exception;
            write_index += 1;
        } else if (container_matches.isException()) {
            const exception = ctx.getException();
            exception.deinit(ctx);
        }
    }

    const all = callMethod1(ctx, container, "querySelectorAll", selector);
    defer all.deinit(ctx);
    if (all.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        return collectCandidateElements(ctx, container);
    }

    const length = valueArrayLikeLength(ctx, all);
    var index: i64 = 0;
    while (index < length) : (index += 1) {
        const value = all.getPropertyUint32(ctx, @intCast(index));
        defer value.deinit(ctx);
        if (value.isException() or !value.isObject()) continue;
        out.setPropertyUint32(ctx, write_index, value.dup(ctx)) catch return quickjs.Value.exception;
        write_index += 1;
    }

    return out;
}

fn collectCandidateElements(ctx: *quickjs.Context, container: quickjs.Value) quickjs.Value {
    const out = quickjs.Value.initArray(ctx);
    if (out.isException()) return quickjs.Value.exception;

    var write_index: u32 = 0;
    if (isElementNode(ctx, container)) {
        out.setPropertyUint32(ctx, write_index, container.dup(ctx)) catch return quickjs.Value.exception;
        write_index += 1;
    }

    const selector = quickjs.Value.initStringLen(ctx, "*");
    defer selector.deinit(ctx);
    const all = callMethod1(ctx, container, "querySelectorAll", selector);
    defer all.deinit(ctx);
    if (all.isException()) return out;

    const length = valueArrayLikeLength(ctx, all);
    var index: i64 = 0;
    while (index < length) : (index += 1) {
        const value = all.getPropertyUint32(ctx, @intCast(index));
        defer value.deinit(ctx);
        if (value.isException() or !value.isObject()) continue;
        out.setPropertyUint32(ctx, write_index, value.dup(ctx)) catch return quickjs.Value.exception;
        write_index += 1;
    }

    return out;
}

fn matchesByText(ctx: *quickjs.Context, element: quickjs.Value, matcher: quickjs.Value, options: quickjs.Value) bool {
    const selector_value = optionValue(ctx, options, "selector");
    defer selector_value.deinit(ctx);
    if (!selector_value.isUndefined() and !selector_value.isNull()) {
        if (!matchesSelectorOption(ctx, element, selector_value)) return false;
    }

    const text = nodeTextForMatchAlloc(ctx, element) orelse return false;
    defer std.heap.c_allocator.free(text);
    const exact = optionExact(ctx, options);
    var matched = matchAgainstValue(ctx, matcher, text, element, exact);
    if (!matched) {
        const accessible_text = accessibleTextFromNodeAlloc(ctx, element);
        defer if (accessible_text) |value| std.heap.c_allocator.free(value);
        if (accessible_text) |value| {
            matched = matchAgainstValue(ctx, matcher, value, element, exact);
        }
    }
    return matched;
}

fn pruneTextAncestorMatchesInPlace(ctx: *quickjs.Context, matches: quickjs.Value) bool {
    const count = valueArrayLength(ctx, matches);
    if (count <= 1) return true;

    const keep = std.heap.c_allocator.alloc(bool, @intCast(count)) catch return false;
    defer std.heap.c_allocator.free(keep);
    @memset(keep, true);

    var i: i64 = 0;
    while (i < count) : (i += 1) {
        const parent = matches.getPropertyUint32(ctx, @intCast(i));
        defer parent.deinit(ctx);
        if (!parent.isObject()) {
            keep[@intCast(i)] = false;
            continue;
        }

        var j: i64 = 0;
        while (j < count) : (j += 1) {
            if (i == j) continue;
            if (!keep[@intCast(i)]) break;

            const child = matches.getPropertyUint32(ctx, @intCast(j));
            defer child.deinit(ctx);
            if (!child.isObject()) continue;
            if (parent.isSameValue(ctx, child)) continue;

            const contains_fn = parent.getPropertyStr(ctx, "contains");
            defer contains_fn.deinit(ctx);
            if (!contains_fn.isFunction(ctx)) continue;

            var contains_args = [_]quickjs.Value{child.dup(ctx)};
            defer contains_args[0].deinit(ctx);
            const contains_result = contains_fn.call(ctx, parent, &contains_args);
            defer contains_result.deinit(ctx);
            if (contains_result.isException()) return false;
            if (contains_result.toBool(ctx) catch false) {
                keep[@intCast(i)] = false;
                break;
            }
        }
    }

    var write_index: u32 = 0;
    var read_index: i64 = 0;
    while (read_index < count) : (read_index += 1) {
        if (!keep[@intCast(read_index)]) continue;
        const value = matches.getPropertyUint32(ctx, @intCast(read_index));
        defer value.deinit(ctx);
        if (!value.isObject()) continue;
        matches.setPropertyUint32(ctx, write_index, value.dup(ctx)) catch return false;
        write_index += 1;
    }

    matches.setPropertyStr(ctx, "length", quickjs.Value.initInt32(@intCast(write_index))) catch return false;
    return true;
}

fn matchesByTestId(ctx: *quickjs.Context, element: quickjs.Value, matcher: quickjs.Value, options: quickjs.Value) bool {
    const attr_name = optionTestIdAttribute(ctx, options) orelse "data-testid";
    defer if (attr_name.ptr != "data-testid".ptr) std.heap.c_allocator.free(attr_name);
    const attr = elementAttributeAlloc(ctx, element, attr_name) orelse return false;
    defer std.heap.c_allocator.free(attr);
    return matchAgainstValue(ctx, matcher, attr, element, optionExact(ctx, options));
}

fn matchesByLabelText(ctx: *quickjs.Context, element: quickjs.Value, matcher: quickjs.Value, options: quickjs.Value) bool {
    if (!isElementNode(ctx, element)) return false;

    const selector_value = optionValue(ctx, options, "selector");
    defer selector_value.deinit(ctx);
    if (!selector_value.isUndefined() and !selector_value.isNull()) {
        if (!matchesSelectorOption(ctx, element, selector_value)) return false;
    }

    const exact = optionExact(ctx, options);

    const aria_label = elementAttributeAlloc(ctx, element, "aria-label");
    defer if (aria_label) |text| std.heap.c_allocator.free(text);
    if (aria_label) |text| {
        if (text.len > 0 and matchAgainstValue(ctx, matcher, text, element, exact)) return true;
    }

    const labelled_by = elementAttributeAlloc(ctx, element, "aria-labelledby");
    defer if (labelled_by) |text| std.heap.c_allocator.free(text);
    if (labelled_by) |raw| {
        if (matchAgainstValue(ctx, matcher, referencedLabelText(ctx, element, raw) orelse "", element, exact)) return true;
    }

    const labels = element.getPropertyStr(ctx, "labels");
    defer labels.deinit(ctx);
    if (!labels.isException() and labels.isObject()) {
        const label_count = valueArrayLikeLength(ctx, labels);
        var i: i64 = 0;
        while (i < label_count) : (i += 1) {
            const label = labels.getPropertyUint32(ctx, @intCast(i));
            defer label.deinit(ctx);
            if (!label.isObject()) continue;
            const text = nodeTextForMatchAlloc(ctx, label) orelse continue;
            defer std.heap.c_allocator.free(text);
            if (matchAgainstValue(ctx, matcher, text, element, exact)) return true;
        }
    }

    return false;
}

fn matchesByRole(ctx: *quickjs.Context, element: quickjs.Value, matcher: quickjs.Value, options: quickjs.Value) bool {
    if (!isElementNode(ctx, element)) return false;

    const include_hidden = optionBool(ctx, options, "hidden") orelse false;
    if (!include_hidden and isElementHidden(ctx, element)) return false;

    var heading_level: i64 = 0;
    if (!elementMatchesRole(ctx, element, matcher, &heading_level)) return false;

    const name_option = optionValue(ctx, options, "name");
    defer name_option.deinit(ctx);
    if (!name_option.isUndefined() and !name_option.isNull()) {
        const name = accessibleNameAlloc(ctx, element) orelse "";
        defer if (name.ptr != "".ptr) std.heap.c_allocator.free(name);
        if (!matchAgainstValue(ctx, name_option, name, element, optionExact(ctx, options))) return false;
    }

    if (!matchesRoleStateOption(ctx, element, options, "selected", "aria-selected")) return false;
    if (!matchesRoleStateOption(ctx, element, options, "checked", "aria-checked")) return false;
    if (!matchesRoleStateOption(ctx, element, options, "pressed", "aria-pressed")) return false;
    if (!matchesRoleStateOption(ctx, element, options, "expanded", "aria-expanded")) return false;
    if (!matchesRoleCurrentOption(ctx, element, options)) return false;

    const level_option = optionValue(ctx, options, "level");
    defer level_option.deinit(ctx);
    if (!level_option.isUndefined() and !level_option.isNull()) {
        const expected = level_option.toInt64(ctx) catch return false;
        if (heading_level == 0 or expected != heading_level) return false;
    }

    return true;
}

fn matchesByDisplayValue(ctx: *quickjs.Context, element: quickjs.Value, matcher: quickjs.Value, options: quickjs.Value) bool {
    if (!isElementNode(ctx, element)) return false;
    const value_prop = element.getPropertyStr(ctx, "value");
    defer value_prop.deinit(ctx);
    if (value_prop.isException() or value_prop.isUndefined() or value_prop.isNull()) return false;

    const text = value_prop.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    return matchAgainstValue(ctx, matcher, text.ptr[0..text.len], element, optionExact(ctx, options));
}

fn matchesByAttribute(ctx: *quickjs.Context, element: quickjs.Value, comptime attribute_name: []const u8, matcher: quickjs.Value, options: quickjs.Value) bool {
    if (!isElementNode(ctx, element)) return false;

    const selector_value = optionValue(ctx, options, "selector");
    defer selector_value.deinit(ctx);
    if (!selector_value.isUndefined() and !selector_value.isNull()) {
        if (!matchesSelectorOption(ctx, element, selector_value)) return false;
    }

    const attr = elementAttributeAlloc(ctx, element, attribute_name) orelse return false;
    defer std.heap.c_allocator.free(attr);
    return matchAgainstValue(ctx, matcher, attr, element, optionExact(ctx, options));
}

fn matchesByTitle(ctx: *quickjs.Context, element: quickjs.Value, matcher: quickjs.Value, options: quickjs.Value) bool {
    if (!isElementNode(ctx, element)) return false;

    const selector_value = optionValue(ctx, options, "selector");
    defer selector_value.deinit(ctx);
    if (!selector_value.isUndefined() and !selector_value.isNull()) {
        if (!matchesSelectorOption(ctx, element, selector_value)) return false;
    }

    const exact = optionExact(ctx, options);
    const title_attr = elementAttributeAlloc(ctx, element, "title");
    defer if (title_attr) |text| std.heap.c_allocator.free(text);
    if (title_attr) |text| {
        if (matchAgainstValue(ctx, matcher, text, element, exact)) return true;
    }

    const local_name = elementLocalNameAlloc(ctx, element) orelse return false;
    defer std.heap.c_allocator.free(local_name);
    if (!std.mem.eql(u8, local_name, "title")) return false;

    const text = nodeTextForMatchAlloc(ctx, element) orelse return false;
    defer std.heap.c_allocator.free(text);
    return matchAgainstValue(ctx, matcher, text, element, exact);
}

fn descendantAlsoMatchesText(ctx: *quickjs.Context, element: quickjs.Value, matcher: quickjs.Value, exact: bool) bool {
    const selector = quickjs.Value.initStringLen(ctx, "*");
    defer selector.deinit(ctx);
    const descendants = callMethod1(ctx, element, "querySelectorAll", selector);
    defer descendants.deinit(ctx);
    if (descendants.isException()) return false;

    const count = valueArrayLikeLength(ctx, descendants);
    var index: i64 = 0;
    while (index < count) : (index += 1) {
        const child = descendants.getPropertyUint32(ctx, @intCast(index));
        defer child.deinit(ctx);
        if (!child.isObject()) continue;

        const text = nodeTextForMatchAlloc(ctx, child) orelse continue;
        defer std.heap.c_allocator.free(text);
        if (matchAgainstValue(ctx, matcher, text, child, exact)) return true;
    }
    return false;
}

fn matchesSelectorOption(ctx: *quickjs.Context, element: quickjs.Value, selector: quickjs.Value) bool {
    const selector_text = selector.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(selector_text.ptr);
    const selector_value = quickjs.Value.initStringLen(ctx, selector_text.ptr[0..selector_text.len]);
    defer selector_value.deinit(ctx);
    const result = callMethod1(ctx, element, "matches", selector_value);
    defer result.deinit(ctx);
    if (result.isException()) return false;
    return result.toBool(ctx) catch false;
}

fn optionValue(ctx: *quickjs.Context, options: quickjs.Value, comptime name: [:0]const u8) quickjs.Value {
    if (!options.isObject()) return quickjs.Value.undefined;
    const value = options.getPropertyStr(ctx, name);
    if (value.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        return quickjs.Value.undefined;
    }
    return value;
}

fn optionExact(ctx: *quickjs.Context, options: quickjs.Value) bool {
    const exact = optionValue(ctx, options, "exact");
    defer exact.deinit(ctx);
    if (exact.isUndefined() or exact.isNull()) return true;
    return exact.toBool(ctx) catch true;
}

fn optionBool(ctx: *quickjs.Context, options: quickjs.Value, comptime name: [:0]const u8) ?bool {
    const value = optionValue(ctx, options, name);
    defer value.deinit(ctx);
    if (value.isUndefined() or value.isNull()) return null;
    return value.toBool(ctx) catch null;
}

fn optionTestIdAttribute(ctx: *quickjs.Context, options: quickjs.Value) ?[]u8 {
    const value = optionValue(ctx, options, "testIdAttribute");
    defer value.deinit(ctx);
    if (!value.isUndefined() and !value.isNull()) {
        const text = value.toCStringLen(ctx) orelse return null;
        defer ctx.freeCString(text.ptr);
        return std.heap.c_allocator.dupe(u8, text.ptr[0..text.len]) catch null;
    }

    const config = ensureDomConfigObject(ctx) orelse return null;
    defer config.deinit(ctx);
    const configured = optionValue(ctx, config, "testIdAttribute");
    defer configured.deinit(ctx);
    if (configured.isUndefined() or configured.isNull()) return null;
    const configured_text = configured.toCStringLen(ctx) orelse return null;
    defer ctx.freeCString(configured_text.ptr);
    return std.heap.c_allocator.dupe(u8, configured_text.ptr[0..configured_text.len]) catch null;
}

fn matchAgainstValue(ctx: *quickjs.Context, matcher: quickjs.Value, text: []const u8, element: quickjs.Value, exact: bool) bool {
    if (matcher.isUndefined() or matcher.isNull()) return false;
    const normalized_text = normalizeTextAlloc(text) orelse return false;
    defer std.heap.c_allocator.free(normalized_text);

    if (matcher.isFunction(ctx)) {
        var call_args = [_]quickjs.Value{
            quickjs.Value.initStringLen(ctx, normalized_text),
            element.dup(ctx),
        };
        defer call_args[0].deinit(ctx);
        defer call_args[1].deinit(ctx);
        const result = matcher.call(ctx, quickjs.Value.undefined, &call_args);
        defer result.deinit(ctx);
        if (result.isException()) {
            const exception = ctx.getException();
            exception.deinit(ctx);
            return false;
        }
        return result.toBool(ctx) catch false;
    }

    if (isRegExp(ctx, matcher)) {
        return regexTest(ctx, matcher, normalized_text);
    }

    const matcher_text = matcher.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(matcher_text.ptr);
    const expected = matcher_text.ptr[0..matcher_text.len];
    const normalized_expected = normalizeTextAlloc(expected) orelse return false;
    defer std.heap.c_allocator.free(normalized_expected);

    if (exact) {
        return std.mem.eql(u8, normalized_text, normalized_expected);
    }

    const text_lower = toLowerAlloc(normalized_text) orelse return false;
    defer std.heap.c_allocator.free(text_lower);
    const expected_lower = toLowerAlloc(normalized_expected) orelse return false;
    defer std.heap.c_allocator.free(expected_lower);
    return std.mem.indexOf(u8, text_lower, expected_lower) != null;
}

fn toLowerAlloc(input: []const u8) ?[]u8 {
    var out = std.heap.c_allocator.alloc(u8, input.len) catch return null;
    for (input, 0..) |ch, index| {
        out[index] = std.ascii.toLower(ch);
    }
    return out;
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

fn elementMatchesRole(ctx: *quickjs.Context, element: quickjs.Value, matcher: quickjs.Value, heading_level: *i64) bool {
    heading_level.* = 0;

    const explicit = elementAttributeAlloc(ctx, element, "role");
    defer if (explicit) |text| std.heap.c_allocator.free(text);
    if (explicit) |roles| {
        var parts = std.mem.tokenizeAny(u8, roles, " \t\r\n");
        while (parts.next()) |role_name| {
            if (matchAgainstValue(ctx, matcher, role_name, element, true)) {
                if (std.mem.eql(u8, role_name, "heading")) heading_level.* = headingLevelOf(ctx, element);
                return true;
            }
        }
    }

    const implicit = implicitRoleName(ctx, element, heading_level) orelse return false;
    return matchAgainstValue(ctx, matcher, implicit, element, true);
}

fn implicitRoleName(ctx: *quickjs.Context, element: quickjs.Value, heading_level: *i64) ?[]const u8 {
    const local_name = elementLocalNameAlloc(ctx, element) orelse return null;
    defer std.heap.c_allocator.free(local_name);

    if (std.mem.eql(u8, local_name, "a")) {
        const href = elementAttributeAlloc(ctx, element, "href");
        defer if (href) |value| std.heap.c_allocator.free(value);
        if (href != null and href.?.len > 0) return "link";
    }
    if (std.mem.eql(u8, local_name, "button")) return "button";
    if (std.mem.eql(u8, local_name, "img")) {
        const alt = elementAttributeAlloc(ctx, element, "alt");
        defer if (alt) |value| std.heap.c_allocator.free(value);
        if (alt != null and alt.?.len > 0) return "img";
    }
    if (std.mem.eql(u8, local_name, "textarea")) return "textbox";
    if (std.mem.eql(u8, local_name, "select")) return "combobox";
    if (std.mem.eql(u8, local_name, "progress")) return "progressbar";
    if (std.mem.eql(u8, local_name, "option")) return "option";
    if (std.mem.eql(u8, local_name, "nav")) return "navigation";
    if (std.mem.eql(u8, local_name, "main")) return "main";
    if (std.mem.eql(u8, local_name, "aside")) return "complementary";
    if (std.mem.eql(u8, local_name, "ul") or std.mem.eql(u8, local_name, "ol")) return "list";
    if (std.mem.eql(u8, local_name, "li")) return "listitem";
    if (std.mem.eql(u8, local_name, "input")) {
        const input_type = elementAttributeAlloc(ctx, element, "type");
        defer if (input_type) |text| std.heap.c_allocator.free(text);
        const ty = if (input_type) |raw|
            raw
        else
            "text";
        if (std.mem.eql(u8, ty, "checkbox")) return "checkbox";
        if (std.mem.eql(u8, ty, "radio")) return "radio";
        if (std.mem.eql(u8, ty, "button") or std.mem.eql(u8, ty, "submit") or std.mem.eql(u8, ty, "reset")) return "button";
        if (std.mem.eql(u8, ty, "range")) return "slider";
        if (std.mem.eql(u8, ty, "search") or std.mem.eql(u8, ty, "url") or std.mem.eql(u8, ty, "tel") or std.mem.eql(u8, ty, "email") or std.mem.eql(u8, ty, "password") or std.mem.eql(u8, ty, "text")) {
            const list_attr = elementAttributeAlloc(ctx, element, "list");
            defer if (list_attr) |value| std.heap.c_allocator.free(value);
            if (list_attr == null or list_attr.?.len == 0) return "textbox";
        }
    }
    if (std.mem.eql(u8, local_name, "form")) {
        const name = accessibleNameAlloc(ctx, element);
        defer if (name) |text| std.heap.c_allocator.free(text);
        if (name != null and name.?.len > 0) return "form";
    }
    if (local_name.len == 2 and local_name[0] == 'h' and std.ascii.isDigit(local_name[1])) {
        heading_level.* = @intCast(local_name[1] - '0');
        return "heading";
    }
    return null;
}

fn headingLevelOf(ctx: *quickjs.Context, element: quickjs.Value) i64 {
    const aria_level = elementAttributeAlloc(ctx, element, "aria-level");
    defer if (aria_level) |text| std.heap.c_allocator.free(text);
    if (aria_level) |value| {
        return std.fmt.parseInt(i64, value, 10) catch 0;
    }
    const local = elementLocalNameAlloc(ctx, element) orelse return 0;
    defer std.heap.c_allocator.free(local);
    if (local.len == 2 and local[0] == 'h' and std.ascii.isDigit(local[1])) {
        return @intCast(local[1] - '0');
    }
    return 0;
}

fn matchesRoleStateOption(ctx: *quickjs.Context, element: quickjs.Value, options: quickjs.Value, comptime option_name: [:0]const u8, comptime attribute_name: []const u8) bool {
    const expected = optionBool(ctx, options, option_name);
    if (expected == null) return true;

    const attr = elementAttributeAlloc(ctx, element, attribute_name);
    defer if (attr) |text| std.heap.c_allocator.free(text);
    if (attr) |text| {
        const value = std.ascii.eqlIgnoreCase(text, "true");
        return value == expected.?;
    }

    const prop = optionValue(ctx, element, option_name);
    defer prop.deinit(ctx);
    if (prop.isUndefined() or prop.isNull()) return !expected.?;
    const value = prop.toBool(ctx) catch false;
    return value == expected.?;
}

fn matchesRoleCurrentOption(ctx: *quickjs.Context, element: quickjs.Value, options: quickjs.Value) bool {
    const current_option = optionValue(ctx, options, "current");
    defer current_option.deinit(ctx);
    if (current_option.isUndefined() or current_option.isNull()) return true;

    const current_attr = elementAttributeAlloc(ctx, element, "aria-current");
    defer if (current_attr) |text| std.heap.c_allocator.free(text);

    if (current_option.isBool()) {
        const expected = current_option.toBool(ctx) catch false;
        if (expected) {
            if (current_attr == null) return false;
            return !std.ascii.eqlIgnoreCase(current_attr.?, "false");
        }
        return current_attr == null or std.ascii.eqlIgnoreCase(current_attr.?, "false");
    }

    if (current_attr == null) return false;
    const text = current_option.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    return std.ascii.eqlIgnoreCase(current_attr.?, text.ptr[0..text.len]);
}

fn accessibleNameAlloc(ctx: *quickjs.Context, element: quickjs.Value) ?[]u8 {
    const aria_label = elementAttributeAlloc(ctx, element, "aria-label");
    defer if (aria_label) |text| std.heap.c_allocator.free(text);
    if (aria_label) |text| {
        if (text.len > 0) return std.heap.c_allocator.dupe(u8, text) catch null;
    }

    const labelled_by = elementAttributeAlloc(ctx, element, "aria-labelledby");
    defer if (labelled_by) |text| std.heap.c_allocator.free(text);
    if (labelled_by) |raw| {
        if (referencedLabelText(ctx, element, raw)) |text| return text;
    }

    const labels = element.getPropertyStr(ctx, "labels");
    defer labels.deinit(ctx);
    if (!labels.isException() and labels.isObject()) {
        const count = valueArrayLikeLength(ctx, labels);
        if (count > 0) {
            var out: std.ArrayList(u8) = .empty;
            defer out.deinit(std.heap.c_allocator);

            var i: i64 = 0;
            while (i < count) : (i += 1) {
                const label = labels.getPropertyUint32(ctx, @intCast(i));
                defer label.deinit(ctx);
                if (!label.isObject()) continue;
                const text = accessibleTextFromNodeAlloc(ctx, label) orelse continue;
                defer std.heap.c_allocator.free(text);
                if (text.len == 0) continue;
                if (out.items.len > 0) out.append(std.heap.c_allocator, ' ') catch return null;
                out.appendSlice(std.heap.c_allocator, text) catch return null;
            }
            if (out.items.len > 0) return out.toOwnedSlice(std.heap.c_allocator) catch null;
        }
    }

    const alt = elementAttributeAlloc(ctx, element, "alt");
    defer if (alt) |text| std.heap.c_allocator.free(text);
    if (alt) |text| {
        if (text.len > 0) return std.heap.c_allocator.dupe(u8, text) catch null;
    }

    const text_content = accessibleTextFromNodeAlloc(ctx, element);
    defer if (text_content) |text| std.heap.c_allocator.free(text);
    if (text_content) |text| {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len > 0) return std.heap.c_allocator.dupe(u8, trimmed) catch null;
    }

    const title = elementAttributeAlloc(ctx, element, "title");
    defer if (title) |text| std.heap.c_allocator.free(text);
    if (title) |text| {
        if (text.len > 0) return std.heap.c_allocator.dupe(u8, text) catch null;
    }

    return null;
}

fn referencedLabelText(ctx: *quickjs.Context, element: quickjs.Value, ids_raw: []const u8) ?[]u8 {
    const owner_document = element.getPropertyStr(ctx, "ownerDocument");
    defer owner_document.deinit(ctx);
    if (!owner_document.isObject()) return null;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.heap.c_allocator);
    var parts = std.mem.tokenizeAny(u8, ids_raw, " \t\r\n");
    while (parts.next()) |id| {
        const id_value = quickjs.Value.initStringLen(ctx, id);
        defer id_value.deinit(ctx);
        const target = callMethod1(ctx, owner_document, "getElementById", id_value);
        defer target.deinit(ctx);
        if (!target.isObject()) continue;
        const text = accessibleTextFromNodeAlloc(ctx, target) orelse continue;
        defer std.heap.c_allocator.free(text);
        if (text.len == 0) continue;
        if (out.items.len > 0) out.append(std.heap.c_allocator, ' ') catch return null;
        out.appendSlice(std.heap.c_allocator, text) catch return null;
    }
    if (out.items.len == 0) return null;
    return out.toOwnedSlice(std.heap.c_allocator) catch null;
}

fn isElementHidden(ctx: *quickjs.Context, element: quickjs.Value) bool {
    var current = element.dup(ctx);
    defer current.deinit(ctx);

    while (current.isObject()) {
        if (elementHasAttribute(ctx, current, "hidden")) return true;
        const aria_hidden = elementAttributeAlloc(ctx, current, "aria-hidden");
        defer if (aria_hidden) |text| std.heap.c_allocator.free(text);
        if (aria_hidden) |text| {
            if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, text, " \t\r\n"), "true")) return true;
        }
        const style_attr = elementAttributeAlloc(ctx, current, "style");
        defer if (style_attr) |text| std.heap.c_allocator.free(text);
        if (style_attr) |text| {
            const lower = toLowerAlloc(text) orelse "";
            defer if (lower.ptr != "".ptr) std.heap.c_allocator.free(lower);
            if (std.mem.indexOf(u8, lower, "display:none") != null or
                std.mem.indexOf(u8, lower, "visibility:hidden") != null)
            {
                return true;
            }
        }

        const parent = current.getPropertyStr(ctx, "parentElement");
        defer parent.deinit(ctx);
        if (!parent.isObject()) break;
        current.deinit(ctx);
        current = parent.dup(ctx);
    }
    return false;
}

fn elementHasAttribute(ctx: *quickjs.Context, element: quickjs.Value, comptime name: []const u8) bool {
    const value = elementAttributeAlloc(ctx, element, name);
    defer if (value) |text| std.heap.c_allocator.free(text);
    return value != null;
}

fn elementAttributeAlloc(ctx: *quickjs.Context, element: quickjs.Value, attribute_name: []const u8) ?[]u8 {
    const name = quickjs.Value.initStringLen(ctx, attribute_name);
    defer name.deinit(ctx);
    const attr = callMethod1(ctx, element, "getAttribute", name);
    defer attr.deinit(ctx);
    if (attr.isException() or attr.isNull() or attr.isUndefined()) return null;
    const text = attr.toCStringLen(ctx) orelse return null;
    defer ctx.freeCString(text.ptr);
    return std.heap.c_allocator.dupe(u8, text.ptr[0..text.len]) catch null;
}

fn elementLocalNameAlloc(ctx: *quickjs.Context, element: quickjs.Value) ?[]u8 {
    const local = element.getPropertyStr(ctx, "localName");
    defer local.deinit(ctx);
    if (local.isException() or local.isUndefined() or local.isNull()) return null;
    const text = local.toCStringLen(ctx) orelse return null;
    defer ctx.freeCString(text.ptr);
    const out = std.heap.c_allocator.dupe(u8, text.ptr[0..text.len]) catch return null;
    for (out) |*ch| ch.* = std.ascii.toLower(ch.*);
    return out;
}

fn nodeTextContentAlloc(ctx: *quickjs.Context, node: quickjs.Value) ?[]u8 {
    const value = node.getPropertyStr(ctx, "textContent");
    defer value.deinit(ctx);
    if (value.isException() or value.isUndefined() or value.isNull()) return null;
    const text = value.toCStringLen(ctx) orelse return null;
    defer ctx.freeCString(text.ptr);
    return std.heap.c_allocator.dupe(u8, text.ptr[0..text.len]) catch null;
}

fn nodeTextForMatchAlloc(ctx: *quickjs.Context, node: quickjs.Value) ?[]u8 {
    const local_name = elementLocalNameAlloc(ctx, node);
    defer if (local_name) |name| std.heap.c_allocator.free(name);
    if (local_name) |name| {
        if (std.mem.eql(u8, name, "input")) {
            const input_type = elementAttributeAlloc(ctx, node, "type") orelse "text";
            defer if (input_type.ptr != "text".ptr) std.heap.c_allocator.free(input_type);
            const lowered_type = toLowerAlloc(input_type) orelse return null;
            defer std.heap.c_allocator.free(lowered_type);
            if (std.mem.eql(u8, lowered_type, "button") or std.mem.eql(u8, lowered_type, "submit") or std.mem.eql(u8, lowered_type, "reset")) {
                const value_prop = node.getPropertyStr(ctx, "value");
                defer value_prop.deinit(ctx);
                if (!value_prop.isException() and !value_prop.isNull() and !value_prop.isUndefined()) {
                    const value_text = value_prop.toCStringLen(ctx) orelse return std.heap.c_allocator.dupe(u8, "") catch null;
                    defer ctx.freeCString(value_text.ptr);
                    return std.heap.c_allocator.dupe(u8, value_text.ptr[0..value_text.len]) catch null;
                }
                return std.heap.c_allocator.dupe(u8, "") catch null;
            }
        }
    }
    const child_nodes = node.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (!child_nodes.isException() and child_nodes.isObject()) {
        const child_count = valueArrayLikeLength(ctx, child_nodes);
        if (child_count > 0) {
            var out: std.ArrayList(u8) = .empty;
            defer out.deinit(std.heap.c_allocator);

            var index: i64 = 0;
            while (index < child_count) : (index += 1) {
                const child = child_nodes.getPropertyUint32(ctx, @intCast(index));
                defer child.deinit(ctx);
                if (!child.isObject()) continue;

                const node_type = child.getPropertyStr(ctx, "nodeType");
                defer node_type.deinit(ctx);
                if (node_type.isException()) continue;
                if ((node_type.toInt64(ctx) catch 0) != 3) continue;

                const text = nodeTextContentAlloc(ctx, child) orelse continue;
                defer std.heap.c_allocator.free(text);
                out.appendSlice(std.heap.c_allocator, text) catch return null;
            }

            if (out.items.len > 0) return out.toOwnedSlice(std.heap.c_allocator) catch null;
        }
    }

    return nodeTextContentAlloc(ctx, node);
}

fn accessibleTextFromNodeAlloc(ctx: *quickjs.Context, node: quickjs.Value) ?[]u8 {
    if (!node.isObject()) return null;

    const node_type_value = node.getPropertyStr(ctx, "nodeType");
    defer node_type_value.deinit(ctx);
    if (node_type_value.isException()) return null;
    const node_type = node_type_value.toInt64(ctx) catch return null;

    if (node_type == 3) {
        return nodeTextContentAlloc(ctx, node);
    }
    if (node_type != 1) return null;
    if (elementHasAttribute(ctx, node, "hidden")) return null;

    const local_name = elementLocalNameAlloc(ctx, node);
    defer if (local_name) |name| std.heap.c_allocator.free(name);
    if (local_name) |name| {
        if (std.mem.eql(u8, name, "title")) {
            const parent = node.getPropertyStr(ctx, "parentElement");
            defer parent.deinit(ctx);
            if (!parent.isException() and parent.isObject()) {
                const parent_name = elementLocalNameAlloc(ctx, parent);
                defer if (parent_name) |value| std.heap.c_allocator.free(value);
                if (parent_name) |value| {
                    if (std.mem.eql(u8, value, "svg")) return null;
                }
            }
        }
    }

    const aria_hidden = elementAttributeAlloc(ctx, node, "aria-hidden");
    defer if (aria_hidden) |text| std.heap.c_allocator.free(text);
    if (aria_hidden) |text| {
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, text, " \t\r\n"), "true")) return null;
    }

    const child_nodes = node.getPropertyStr(ctx, "childNodes");
    defer child_nodes.deinit(ctx);
    if (!child_nodes.isException() and child_nodes.isObject()) {
        const child_count = valueArrayLikeLength(ctx, child_nodes);
        if (child_count > 0) {
            var out: std.ArrayList(u8) = .empty;
            defer out.deinit(std.heap.c_allocator);

            var child_index: i64 = 0;
            while (child_index < child_count) : (child_index += 1) {
                const child = child_nodes.getPropertyUint32(ctx, @intCast(child_index));
                defer child.deinit(ctx);
                if (!child.isObject()) continue;

                const child_text = accessibleTextFromNodeAlloc(ctx, child) orelse continue;
                defer std.heap.c_allocator.free(child_text);
                const trimmed = std.mem.trim(u8, child_text, " \t\r\n");
                if (trimmed.len == 0) continue;
                if (out.items.len > 0) {
                    const prev_char = out.items[out.items.len - 1];
                    const next_char = trimmed[0];
                    if (std.ascii.isAlphanumeric(prev_char) and
                        (std.ascii.isAlphanumeric(next_char) or next_char == '(' or next_char == '[' or next_char == '{'))
                    {
                        out.append(std.heap.c_allocator, ' ') catch return null;
                    }
                }
                out.appendSlice(std.heap.c_allocator, trimmed) catch return null;
            }

            if (out.items.len > 0) return out.toOwnedSlice(std.heap.c_allocator) catch null;
            return null;
        }
    }

    return nodeTextContentAlloc(ctx, node);
}

fn normalizeTextAlloc(text: []const u8) ?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.heap.c_allocator);

    var in_whitespace = true;
    for (text) |ch| {
        if (std.ascii.isWhitespace(ch)) {
            if (!in_whitespace) {
                out.append(std.heap.c_allocator, ' ') catch return null;
                in_whitespace = true;
            }
            continue;
        }
        out.append(std.heap.c_allocator, ch) catch return null;
        in_whitespace = false;
    }

    if (out.items.len > 0 and out.items[out.items.len - 1] == ' ') {
        _ = out.pop();
    }
    return out.toOwnedSlice(std.heap.c_allocator) catch null;
}

fn isElementNode(ctx: *quickjs.Context, node: quickjs.Value) bool {
    const node_type = node.getPropertyStr(ctx, "nodeType");
    defer node_type.deinit(ctx);
    if (node_type.isException()) return false;
    return (node_type.toInt64(ctx) catch 0) == 1;
}

fn valueArrayLength(ctx: *quickjs.Context, value: quickjs.Value) i64 {
    return valueArrayLikeLength(ctx, value);
}

fn valueArrayLikeLength(ctx: *quickjs.Context, value: quickjs.Value) i64 {
    const length_prop = value.getPropertyStr(ctx, "length");
    defer length_prop.deinit(ctx);
    if (length_prop.isException()) return 0;
    const length = length_prop.toInt64(ctx) catch return 0;
    return if (length < 0) 0 else length;
}

fn callMethod1(ctx: *quickjs.Context, target: quickjs.Value, comptime method_name: [:0]const u8, arg: quickjs.Value) quickjs.Value {
    const method = target.getPropertyStr(ctx, method_name);
    defer method.deinit(ctx);
    if (!method.isFunction(ctx)) return quickjs.Value.exception;
    var args = [_]quickjs.Value{arg.dup(ctx)};
    defer args[0].deinit(ctx);
    return method.call(ctx, target, &args);
}

fn callMethod0(ctx: *quickjs.Context, target: quickjs.Value, comptime method_name: [:0]const u8) quickjs.Value {
    const method = target.getPropertyStr(ctx, method_name);
    defer method.deinit(ctx);
    if (!method.isFunction(ctx)) return quickjs.Value.exception;
    return method.call(ctx, target, &.{});
}

fn parseWaitTimeout(ctx: *quickjs.Context, options: quickjs.Value) i64 {
    const timeout_value = optionValue(ctx, options, "timeout");
    defer timeout_value.deinit(ctx);
    if (timeout_value.isUndefined() or timeout_value.isNull()) return 10000;
    const timeout = timeout_value.toInt64(ctx) catch return 1000;
    if (timeout <= 0) return 1;
    return timeout;
}

fn parseWaitIntervalTurns(ctx: *quickjs.Context, options: quickjs.Value) i64 {
    const interval_value = optionValue(ctx, options, "interval");
    defer interval_value.deinit(ctx);
    if (interval_value.isUndefined() or interval_value.isNull()) return 1;
    const interval = interval_value.toInt64(ctx) catch return 1;
    if (interval <= 0) return 1;
    if (interval > 100) return 100;
    return interval;
}

fn pumpWaitTurns(ctx: *quickjs.Context, turns: i64) bool {
    const rt = ctx.getRuntime();
    var remaining = if (turns <= 0) @as(i64, 1) else turns;
    var guard: usize = 0;

    while (remaining > 0) : (remaining -= 1) {
        var progressed = false;
        while (rt.isJobPending()) : (guard += 1) {
            _ = rt.executePendingJob() catch return false;
            progressed = true;
            if (guard > 100_000) return false;
        }

        if (platform.hasPendingNativeTimers()) {
            const timer_result = platform.runNativeTimerTurn(ctx);
            defer timer_result.deinit(ctx);
            if (timer_result.isException()) return false;
            progressed = true;
            while (platform.hasDueNativeTimers()) {
                const due_timer_result = platform.runNativeTimerTurn(ctx);
                defer due_timer_result.deinit(ctx);
                if (due_timer_result.isException()) return false;
            }
        }
        if (!progressed) break;
    }

    while (rt.isJobPending()) : (guard += 1) {
        _ = rt.executePendingJob() catch return false;
        if (guard > 100_000) return false;
    }

    return true;
}

fn takeExceptionText(ctx: *quickjs.Context) ?[]u8 {
    const exception = ctx.getException();
    defer exception.deinit(ctx);

    const rendered = exception.toStringValue(ctx);
    defer rendered.deinit(ctx);
    if (rendered.isException()) return null;
    const text = rendered.toCStringLen(ctx) orelse return null;
    defer ctx.freeCString(text.ptr);
    return std.heap.c_allocator.dupe(u8, text.ptr[0..text.len]) catch null;
}

fn throwMessage(ctx: *quickjs.Context, text: []const u8) quickjs.Value {
    const value = quickjs.Value.initStringLen(ctx, text);
    return value.throw(ctx);
}

fn resolvedPromise(ctx: *quickjs.Context, value: quickjs.Value) quickjs.Value {
    var promise = quickjs.Value.initPromiseCapability(ctx);
    if (promise.value.isException()) {
        promise.resolve.deinit(ctx);
        promise.reject.deinit(ctx);
        return value.dup(ctx);
    }
    defer promise.deinit(ctx);

    var args = [_]quickjs.Value{value.dup(ctx)};
    defer args[0].deinit(ctx);
    const result = promise.resolve.call(ctx, quickjs.Value.undefined, &args);
    result.deinit(ctx);
    return promise.value.dup(ctx);
}

fn rejectedPromise(ctx: *quickjs.Context, reason: quickjs.Value) quickjs.Value {
    var promise = quickjs.Value.initPromiseCapability(ctx);
    if (promise.value.isException()) {
        promise.resolve.deinit(ctx);
        promise.reject.deinit(ctx);
        return reason.dup(ctx);
    }
    defer promise.deinit(ctx);

    var args = [_]quickjs.Value{reason.dup(ctx)};
    defer args[0].deinit(ctx);
    const result = promise.reject.call(ctx, quickjs.Value.undefined, &args);
    result.deinit(ctx);
    return promise.value.dup(ctx);
}

fn jsWaitFor(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return throwMessage(ctx, "waitFor expects a callback");

    const callback = quickjs.Value.fromCVal(args[0]);
    if (!callback.isFunction(ctx)) return throwMessage(ctx, "waitFor callback must be a function");

    const options = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    const timeout_ms = parseWaitTimeout(ctx, options);
    const interval_turns = parseWaitIntervalTurns(ctx, options);
    const start_ms = monotonicNowMs();

    var last_error: ?[]u8 = null;
    defer if (last_error) |text| std.heap.c_allocator.free(text);

    while (true) {
        const result = callback.call(ctx, quickjs.Value.undefined, &.{});
        if (!result.isException()) {
            defer result.deinit(ctx);
            return resolvedPromise(ctx, result);
        }
        result.deinit(ctx);

        if (takeExceptionText(ctx)) |message| {
            if (last_error) |previous| std.heap.c_allocator.free(previous);
            last_error = message;
        }

        const elapsed = monotonicNowMs() - start_ms;
        if (elapsed >= timeout_ms) break;
        if (!pumpWaitTurns(ctx, interval_turns)) return quickjs.Value.exception;
        if (!flushReactAct(ctx)) return quickjs.Value.exception;
    }

    const message = if (last_error) |text|
        std.fmt.allocPrint(std.heap.c_allocator, "waitFor timed out: {s}", .{text}) catch "waitFor timed out"
    else
        "waitFor timed out";
    defer if (message.ptr != "waitFor timed out".ptr) std.heap.c_allocator.free(message);
    const reason = quickjs.Value.initStringLen(ctx, message);
    defer reason.deinit(ctx);
    return rejectedPromise(ctx, reason);
}

fn jsWaitForElementToBeRemoved(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return throwMessage(ctx, "waitForElementToBeRemoved expects an element or callback");

    const target_or_callback = quickjs.Value.fromCVal(args[0]);
    const options = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    const timeout_ms = parseWaitTimeout(ctx, options);
    const interval_turns = parseWaitIntervalTurns(ctx, options);
    const start_ms = monotonicNowMs();

    while (true) {
        const target_value = if (target_or_callback.isFunction(ctx))
            target_or_callback.call(ctx, quickjs.Value.undefined, &.{})
        else
            target_or_callback.dup(ctx);
        defer target_value.deinit(ctx);

        if (target_value.isException()) {
            target_value.deinit(ctx);
            const reason = quickjs.Value.initStringLen(ctx, "waitForElementToBeRemoved callback threw");
            defer reason.deinit(ctx);
            return rejectedPromise(ctx, reason);
        }

        if (isRemovedValue(ctx, target_value)) {
            return resolvedPromise(ctx, quickjs.Value.undefined);
        }

        const elapsed = monotonicNowMs() - start_ms;
        if (elapsed >= timeout_ms) break;
        if (!pumpWaitTurns(ctx, interval_turns)) return quickjs.Value.exception;
    }

    const reason = quickjs.Value.initStringLen(ctx, "waitForElementToBeRemoved timed out");
    defer reason.deinit(ctx);
    return rejectedPromise(ctx, reason);
}

fn isRemovedValue(ctx: *quickjs.Context, value: quickjs.Value) bool {
    if (value.isUndefined() or value.isNull()) return true;

    if (value.isArray()) {
        const count = valueArrayLength(ctx, value);
        if (count == 0) return true;
        var index: i64 = 0;
        while (index < count) : (index += 1) {
            const item = value.getPropertyUint32(ctx, @intCast(index));
            defer item.deinit(ctx);
            if (!isRemovedValue(ctx, item)) return false;
        }
        return true;
    }

    if (!value.isObject()) return true;
    return !isConnectedToDocument(ctx, value);
}

fn monotonicNowMs() i64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return 0;
    const total_ms = (@as(i128, ts.sec) * std.time.ms_per_s) + @as(i128, @divTrunc(ts.nsec, std.time.ns_per_ms));
    return @intCast(total_ms);
}

fn isConnectedToDocument(ctx: *quickjs.Context, node: quickjs.Value) bool {
    const is_connected = node.getPropertyStr(ctx, "isConnected");
    defer is_connected.deinit(ctx);
    if (!is_connected.isException() and !is_connected.isUndefined()) {
        return is_connected.toBool(ctx) catch false;
    }
    if (is_connected.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
    }

    const owner_document = node.getPropertyStr(ctx, "ownerDocument");
    defer owner_document.deinit(ctx);
    if (!owner_document.isObject()) return false;

    const contains_fn = owner_document.getPropertyStr(ctx, "contains");
    defer contains_fn.deinit(ctx);
    if (!contains_fn.isFunction(ctx)) return false;
    var call_args = [_]quickjs.Value{node.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = contains_fn.call(ctx, owner_document, &call_args);
    defer result.deinit(ctx);
    if (result.isException()) return false;
    return result.toBool(ctx) catch false;
}

fn createFireEvent(ctx: *quickjs.Context) TestingLibraryDomError!quickjs.Value {
    const fire_event = quickjs.Value.initCFunction(ctx, jsFireEventCall, "fireEvent", 2);
    if (fire_event.isException()) return error.OutOfMemory;
    errdefer fire_event.deinit(ctx);

    try installFireEventMethod(ctx, fire_event, "click", .click);
    try installFireEventMethod(ctx, fire_event, "input", .input);
    try installFireEventMethod(ctx, fire_event, "change", .change);
    try installFireEventMethod(ctx, fire_event, "keyDown", .key_down);
    try installFireEventMethod(ctx, fire_event, "keyUp", .key_up);
    try installFireEventMethod(ctx, fire_event, "submit", .submit);
    try installFireEventMethod(ctx, fire_event, "focus", .focus);
    try installFireEventMethod(ctx, fire_event, "blur", .blur);
    try installFireEventMethod(ctx, fire_event, "compositionStart", .composition_start);
    try installFireEventMethod(ctx, fire_event, "compositionUpdate", .composition_update);
    try installFireEventMethod(ctx, fire_event, "compositionEnd", .composition_end);
    try installFireEventMethod(ctx, fire_event, "mouseDown", .mouse_down);
    try installFireEventMethod(ctx, fire_event, "mouseOver", .mouse_over);
    try installFireEventMethod(ctx, fire_event, "mouseEnter", .mouse_enter);

    return fire_event;
}

fn installFireEventMethod(ctx: *quickjs.Context, fire_event: quickjs.Value, method_name: []const u8, kind: EventKind) TestingLibraryDomError!void {
    const name_z = std.heap.c_allocator.dupeZ(u8, method_name) catch return error.OutOfMemory;
    defer std.heap.c_allocator.free(name_z);
    const method = quickjs.Value.initCFunctionData2(ctx, jsFireEventMethod, "__zigFireEventMethod", 2, @intFromEnum(kind), &.{});
    if (method.isException()) return error.JSError;
    errdefer method.deinit(ctx);
    fire_event.setPropertyStr(ctx, name_z, method) catch return error.JSError;
}

fn jsFireEventCall(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len < 2) return throwMessage(ctx, "fireEvent(node, event) expects two arguments");

    const node = quickjs.Value.fromCVal(args[0]);
    const event = quickjs.Value.fromCVal(args[1]);
    if (!node.isObject() or !event.isObject()) return throwMessage(ctx, "fireEvent(node, event) expects object arguments");

    return dispatchEventOnNode(ctx, node, event);
}

fn jsFireEventMethod(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    magic: i32,
    _: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return throwMessage(ctx, "fireEvent method expects a target node");

    const node = quickjs.Value.fromCVal(args[0]);
    if (!node.isObject()) return throwMessage(ctx, "fireEvent target must be an object");

    const init = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    const kind: EventKind = @enumFromInt(magic);

    if (kind == .click) {
        return invokeElementClick(ctx, node, init);
    }
    if (kind == .mouse_enter) {
        applyTargetInitIfNeeded(ctx, node, init);
        const mouse_over = createEventForKind(ctx, .mouse_over, init);
        defer mouse_over.deinit(ctx);
        if (mouse_over.isException()) return quickjs.Value.exception;
        const over_result = dispatchEventOnNodeWithTurns(ctx, node, mouse_over, 8);
        if (over_result.isException()) return quickjs.Value.exception;
        over_result.deinit(ctx);

        const mouse_enter = createEventForKind(ctx, .mouse_enter, init);
        defer mouse_enter.deinit(ctx);
        if (mouse_enter.isException()) return quickjs.Value.exception;
        return dispatchEventOnNodeWithTurns(ctx, node, mouse_enter, 8);
    }

    applyTargetInitIfNeeded(ctx, node, init);
    const event = createEventForKind(ctx, kind, init);
    defer event.deinit(ctx);
    if (event.isException()) return quickjs.Value.exception;
    const flush_turns: i64 = switch (kind) {
        .input, .change => 4,
        .key_down, .key_up => 6,
        .mouse_over, .mouse_enter => 8,
        else => 4,
    };
    return dispatchEventOnNodeWithTurns(ctx, node, event, flush_turns);
}

fn invokeElementClick(ctx: *quickjs.Context, node: quickjs.Value, init: quickjs.Value) quickjs.Value {
    var click_target = node.dup(ctx);
    defer click_target.deinit(ctx);

    if (isElementNode(ctx, click_target)) {
        const local_name = elementLocalNameAlloc(ctx, click_target);
        defer if (local_name) |name| std.heap.c_allocator.free(name);
        if (local_name) |name| {
            if (std.mem.eql(u8, name, "title")) {
                const parent = click_target.getPropertyStr(ctx, "parentElement");
                defer parent.deinit(ctx);
                if (!parent.isException() and parent.isObject()) {
                    click_target.deinit(ctx);
                    click_target = parent.dup(ctx);
                }
            }
        }
    }

    var candidate = click_target.dup(ctx);
    defer candidate.deinit(ctx);
    while (candidate.isObject()) {
        const candidate_click = candidate.getPropertyStr(ctx, "click");
        const has_click = candidate_click.isFunction(ctx);
        candidate_click.deinit(ctx);
        if (has_click) {
            click_target.deinit(ctx);
            click_target = candidate.dup(ctx);
            break;
        }
        const parent = candidate.getPropertyStr(ctx, "parentElement");
        defer parent.deinit(ctx);
        if (parent.isException() or !parent.isObject()) break;
        candidate.deinit(ctx);
        candidate = parent.dup(ctx);
    }

    if (isRadioInputControl(ctx, click_target)) {
        return invokeRadioInputClick(ctx, click_target);
    }
    setClickDelayFlag(ctx, true);
    defer setClickDelayFlag(ctx, false);

    const click_init = if (!init.isUndefined() and !init.isNull() and init.isObject())
        init
    else
        quickjs.Value.undefined;
    const click_event = createEventForKind(ctx, .click, click_init);
    defer click_event.deinit(ctx);
    if (click_event.isException()) return quickjs.Value.exception;

    const dispatched = dispatchEventOnNodeWithTurns(ctx, click_target, click_event, 3);
    if (dispatched.isException()) return quickjs.Value.exception;
    dispatched.deinit(ctx);
    return quickjs.Value.initBool(true);
}

fn invokeRadioInputClick(ctx: *quickjs.Context, node: quickjs.Value) quickjs.Value {
    const already_checked = boolProperty(ctx, node, "checked");
    if (already_checked) {
        return dispatchPreventedClick(ctx, node);
    } else {
        uncheckRadioGroupSiblings(ctx, node);
        setCheckedWithTracker(ctx, node, true);
    }

    const click_result = dispatchSyntheticEvent(ctx, node, .click);
    if (click_result.isException()) return quickjs.Value.exception;
    click_result.deinit(ctx);

    const input_result = dispatchSyntheticEvent(ctx, node, .input);
    if (input_result.isException()) return quickjs.Value.exception;
    input_result.deinit(ctx);

    const change_result = dispatchSyntheticEvent(ctx, node, .change);
    if (change_result.isException()) return quickjs.Value.exception;
    change_result.deinit(ctx);
    return quickjs.Value.initBool(true);
}

fn dispatchPreventedClick(ctx: *quickjs.Context, node: quickjs.Value) quickjs.Value {
    const click_event = createEventForKind(ctx, .click, quickjs.Value.undefined);
    defer click_event.deinit(ctx);
    if (click_event.isException()) return quickjs.Value.exception;

    const prevent_default = click_event.getPropertyStr(ctx, "preventDefault");
    defer prevent_default.deinit(ctx);
    if (prevent_default.isFunction(ctx)) {
        const prevent_result = prevent_default.call(ctx, click_event, &.{});
        prevent_result.deinit(ctx);
    }

    return dispatchEventOnNode(ctx, node, click_event);
}

fn dispatchSyntheticEvent(ctx: *quickjs.Context, node: quickjs.Value, kind: EventKind) quickjs.Value {
    const event = createEventForKind(ctx, kind, quickjs.Value.undefined);
    defer event.deinit(ctx);
    if (event.isException()) return quickjs.Value.exception;
    return dispatchEventOnNode(ctx, node, event);
}

fn uncheckRadioGroupSiblings(ctx: *quickjs.Context, node: quickjs.Value) void {
    const radio_name = controlNameAlloc(ctx, node) orelse return;
    defer std.heap.c_allocator.free(radio_name);
    if (radio_name.len == 0) return;

    const scope = radioScope(ctx, node);
    defer scope.deinit(ctx);
    if (!scope.isObject()) return;

    const selector = quickjs.Value.initStringLen(ctx, "input[type=\"radio\"]");
    defer selector.deinit(ctx);
    const radios = callMethod1(ctx, scope, "querySelectorAll", selector);
    defer radios.deinit(ctx);
    if (!radios.isObject()) return;

    const count = valueArrayLikeLength(ctx, radios);
    var index: i64 = 0;
    while (index < count) : (index += 1) {
        const candidate = radios.getPropertyUint32(ctx, @intCast(index));
        defer candidate.deinit(ctx);
        if (!candidate.isObject()) continue;
        if (candidate.isSameValue(ctx, node)) continue;

        const candidate_name = controlNameAlloc(ctx, candidate) orelse continue;
        defer std.heap.c_allocator.free(candidate_name);
        if (!std.mem.eql(u8, candidate_name, radio_name)) continue;
        setCheckedWithTracker(ctx, candidate, false);
    }
}

fn radioScope(ctx: *quickjs.Context, node: quickjs.Value) quickjs.Value {
    const form = node.getPropertyStr(ctx, "form");
    if (!form.isException() and form.isObject()) return form;
    if (form.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
    }
    form.deinit(ctx);

    const owner_document = node.getPropertyStr(ctx, "ownerDocument");
    if (owner_document.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        owner_document.deinit(ctx);
        return quickjs.Value.undefined;
    }
    return owner_document;
}

fn setCheckedWithTracker(ctx: *quickjs.Context, node: quickjs.Value, checked: bool) void {
    const previous = boolProperty(ctx, node, "checked");
    node.setPropertyStr(ctx, "checked", quickjs.Value.initBool(checked)) catch {};
    updateReactValueTracker(ctx, node, if (previous) "true" else "false");
}

fn resetFormForControl(ctx: *quickjs.Context, node: quickjs.Value) quickjs.Value {
    if (!isResetControl(ctx, node)) return quickjs.Value.undefined;
    const form = node.getPropertyStr(ctx, "form");
    if (!form.isException() and form.isObject()) return form;
    if (form.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
    }
    form.deinit(ctx);
    return quickjs.Value.undefined;
}

fn triggerFormReset(ctx: *quickjs.Context, form: quickjs.Value) void {
    const reset_fn = form.getPropertyStr(ctx, "reset");
    defer reset_fn.deinit(ctx);
    if (!reset_fn.isFunction(ctx)) return;
    const result = reset_fn.call(ctx, form, &.{});
    result.deinit(ctx);
}

fn isRadioInputControl(ctx: *quickjs.Context, node: quickjs.Value) bool {
    if (!elementLocalNameIs(ctx, node, "input")) return false;
    return controlTypeIs(ctx, node, "radio");
}

fn isResetControl(ctx: *quickjs.Context, node: quickjs.Value) bool {
    const local_name = elementLocalNameAlloc(ctx, node) orelse return false;
    defer std.heap.c_allocator.free(local_name);
    if (!std.mem.eql(u8, local_name, "input") and !std.mem.eql(u8, local_name, "button")) return false;
    return controlTypeIs(ctx, node, "reset");
}

fn elementLocalNameIs(ctx: *quickjs.Context, node: quickjs.Value, expected: []const u8) bool {
    const local_name = elementLocalNameAlloc(ctx, node) orelse return false;
    defer std.heap.c_allocator.free(local_name);
    return std.mem.eql(u8, local_name, expected);
}

fn controlTypeIs(ctx: *quickjs.Context, node: quickjs.Value, expected: []const u8) bool {
    const type_value = node.getPropertyStr(ctx, "type");
    defer type_value.deinit(ctx);
    if (type_value.isException() or type_value.isNull() or type_value.isUndefined()) return false;
    const text = type_value.toCStringLen(ctx) orelse return false;
    defer ctx.freeCString(text.ptr);
    return std.ascii.eqlIgnoreCase(text.ptr[0..text.len], expected);
}

fn boolProperty(ctx: *quickjs.Context, node: quickjs.Value, comptime name: [:0]const u8) bool {
    const value = node.getPropertyStr(ctx, name);
    defer value.deinit(ctx);
    if (value.isException()) return false;
    return value.toBool(ctx) catch false;
}

fn controlNameAlloc(ctx: *quickjs.Context, node: quickjs.Value) ?[]u8 {
    const name_value = node.getPropertyStr(ctx, "name");
    defer name_value.deinit(ctx);
    if (name_value.isException() or name_value.isNull() or name_value.isUndefined()) return null;
    const text = name_value.toCStringLen(ctx) orelse return null;
    defer ctx.freeCString(text.ptr);
    return std.heap.c_allocator.dupe(u8, text.ptr[0..text.len]) catch null;
}

fn applyTargetInitIfNeeded(ctx: *quickjs.Context, node: quickjs.Value, init: quickjs.Value) void {
    if (!init.isObject()) return;
    const target = init.getPropertyStr(ctx, "target");
    defer target.deinit(ctx);
    if (!target.isObject()) return;

    const value = target.getPropertyStr(ctx, "value");
    defer value.deinit(ctx);
    if (!value.isUndefined() and !value.isNull() and !value.isException()) {
        var previous_value: ?[]u8 = null;
        const current_value = node.getPropertyStr(ctx, "value");
        defer current_value.deinit(ctx);
        if (!current_value.isException() and !current_value.isUndefined() and !current_value.isNull()) {
            if (current_value.toCStringLen(ctx)) |text| {
                previous_value = std.heap.c_allocator.dupe(u8, text.ptr[0..text.len]) catch null;
                ctx.freeCString(text.ptr);
            }
        }
        defer if (previous_value) |text| std.heap.c_allocator.free(text);
        node.setPropertyStr(ctx, "value", value.dup(ctx)) catch {};
        if (previous_value) |text| updateReactValueTracker(ctx, node, text);
    }

    const checked = target.getPropertyStr(ctx, "checked");
    defer checked.deinit(ctx);
    if (!checked.isUndefined() and !checked.isNull() and !checked.isException()) {
        const previous_checked_value = node.getPropertyStr(ctx, "checked");
        defer previous_checked_value.deinit(ctx);
        const previous_checked = if (!previous_checked_value.isException()) (previous_checked_value.toBool(ctx) catch false) else false;
        node.setPropertyStr(ctx, "checked", checked.dup(ctx)) catch {};
        updateReactValueTracker(ctx, node, if (previous_checked) "true" else "false");
    }
}

fn updateReactValueTracker(ctx: *quickjs.Context, node: quickjs.Value, previous: []const u8) void {
    const tracker = node.getPropertyStr(ctx, "_valueTracker");
    defer tracker.deinit(ctx);
    if (!tracker.isObject()) return;
    const set_value = tracker.getPropertyStr(ctx, "setValue");
    defer set_value.deinit(ctx);
    if (!set_value.isFunction(ctx)) return;
    var args = [_]quickjs.Value{quickjs.Value.initStringLen(ctx, previous)};
    defer args[0].deinit(ctx);
    const result = set_value.call(ctx, tracker, &args);
    result.deinit(ctx);
}

fn createEventForKind(ctx: *quickjs.Context, kind: EventKind, init: quickjs.Value) quickjs.Value {
    const event_type = switch (kind) {
        .click => "click",
        .input => "input",
        .change => "change",
        .key_down => "keydown",
        .key_up => "keyup",
        .submit => "submit",
        .focus => "focus",
        .blur => "blur",
        .composition_start => "compositionstart",
        .composition_update => "compositionupdate",
        .composition_end => "compositionend",
        .mouse_down => "mousedown",
        .mouse_over => "mouseover",
        .mouse_enter => "mouseenter",
    };
    const ctor_name = switch (kind) {
        .click, .mouse_down, .mouse_over, .mouse_enter => "MouseEvent",
        .key_down, .key_up => "KeyboardEvent",
        .input => "InputEvent",
        .composition_start, .composition_update, .composition_end => "CompositionEvent",
        else => "Event",
    };
    const default_bubbles = switch (kind) {
        .focus, .blur, .mouse_enter => false,
        else => true,
    };
    const default_cancelable = switch (kind) {
        .input, .focus, .blur => false,
        else => true,
    };

    const event_init = normalizedEventInit(ctx, init, default_bubbles, default_cancelable);
    defer event_init.deinit(ctx);
    if (event_init.isException()) return quickjs.Value.exception;

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    var ctor = global.getPropertyStr(ctx, ctor_name);
    if (ctor.isException() or !ctor.isFunction(ctx)) {
        if (ctor.isException()) {
            const exception = ctx.getException();
            exception.deinit(ctx);
        }
        ctor.deinit(ctx);
        ctor = global.getPropertyStr(ctx, "Event");
    }
    defer ctor.deinit(ctx);
    if (!ctor.isFunction(ctx)) return quickjs.Value.exception;

    const type_arg = quickjs.Value.initStringLen(ctx, event_type);
    defer type_arg.deinit(ctx);
    var args = [_]quickjs.Value{ type_arg, event_init };
    return callAsConstructor(ctx, ctor, &args);
}

fn normalizedEventInit(ctx: *quickjs.Context, init: quickjs.Value, default_bubbles: bool, default_cancelable: bool) quickjs.Value {
    const out = if (init.isObject()) init.dup(ctx) else quickjs.Value.initObject(ctx);
    if (out.isException()) return quickjs.Value.exception;

    const bubbles = out.getPropertyStr(ctx, "bubbles");
    defer bubbles.deinit(ctx);
    if (bubbles.isUndefined() or bubbles.isNull()) {
        out.setPropertyStr(ctx, "bubbles", quickjs.Value.initBool(default_bubbles)) catch return quickjs.Value.exception;
    }

    const cancelable = out.getPropertyStr(ctx, "cancelable");
    defer cancelable.deinit(ctx);
    if (cancelable.isUndefined() or cancelable.isNull()) {
        out.setPropertyStr(ctx, "cancelable", quickjs.Value.initBool(default_cancelable)) catch return quickjs.Value.exception;
    }

    return out;
}

fn dispatchEventOnNode(ctx: *quickjs.Context, node: quickjs.Value, event: quickjs.Value) quickjs.Value {
    return dispatchEventOnNodeWithTurns(ctx, node, event, 4);
}

fn setClickDelayFlag(ctx: *quickjs.Context, enabled: bool) void {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    global.setPropertyStr(ctx, "__zigDuringClickEvent", quickjs.Value.initBool(enabled)) catch {};
}

fn dispatchEventOnNodeWithTurns(ctx: *quickjs.Context, node: quickjs.Value, event: quickjs.Value, flush_turns: i64) quickjs.Value {
    const dispatch = node.getPropertyStr(ctx, "dispatchEvent");
    defer dispatch.deinit(ctx);
    if (!dispatch.isFunction(ctx)) return throwMessage(ctx, "target does not support dispatchEvent");
    var call_args = [_]quickjs.Value{event.dup(ctx)};
    defer call_args[0].deinit(ctx);
    const result = dispatch.call(ctx, node, &call_args);
    if (result.isException()) return result;
    if (!flushReactAct(ctx)) {
        result.deinit(ctx);
        return quickjs.Value.exception;
    }
    if (flush_turns > 0) {
        if (!pumpWaitTurns(ctx, flush_turns)) {
            result.deinit(ctx);
            return quickjs.Value.exception;
        }
    }
    return result;
}

fn flushReactAct(ctx: *quickjs.Context) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const react_api = global.getPropertyStr(ctx, "__zigTestingLibraryReact");
    defer react_api.deinit(ctx);
    if (!react_api.isObject()) return true;

    const act = react_api.getPropertyStr(ctx, "act");
    defer act.deinit(ctx);
    if (!act.isFunction(ctx)) return true;

    const callback = quickjs.Value.initCFunction(ctx, jsActFlushNoop, "__zigActFlushNoop", 0);
    if (callback.isException()) return false;
    defer callback.deinit(ctx);

    var args = [_]quickjs.Value{callback.dup(ctx)};
    defer args[0].deinit(ctx);
    const result = act.call(ctx, quickjs.Value.undefined, &args);
    defer result.deinit(ctx);
    if (result.isException()) return false;

    const then_fn = result.getPropertyStr(ctx, "then");
    defer then_fn.deinit(ctx);
    if (then_fn.isFunction(ctx)) {
        if (!pumpWaitTurns(ctx, 1)) return false;
    }
    return true;
}

fn jsActFlushNoop(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn callAsConstructor(ctx: *quickjs.Context, ctor: quickjs.Value, args: []const quickjs.Value) quickjs.Value {
    if (args.len == 0) {
        return quickjs.Value.fromCVal(quickjs.c.JS_CallConstructor(ctx.cval(), ctor.cval(), 0, null));
    }

    const argv = std.heap.c_allocator.alloc(quickjs.c.JSValue, args.len) catch return quickjs.Value.exception;
    defer std.heap.c_allocator.free(argv);
    for (args, 0..) |arg, index| argv[index] = arg.cval();

    return quickjs.Value.fromCVal(
        quickjs.c.JS_CallConstructor(
            ctx.cval(),
            ctor.cval(),
            @intCast(args.len),
            @ptrCast(argv.ptr),
        ),
    );
}

fn setFunction(
    ctx: *quickjs.Context,
    object: quickjs.Value,
    comptime name: [:0]const u8,
    comptime func: quickjs.cfunc.Func,
    arg_count: i32,
) TestingLibraryDomError!void {
    const value = quickjs.Value.initCFunction(ctx, func, name, arg_count);
    if (value.isException()) return error.JSError;
    object.setPropertyStr(ctx, name, value) catch return error.JSError;
}

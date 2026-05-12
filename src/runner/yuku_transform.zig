const std = @import("std");
const parser = @import("yuku_parser");
const traversal = @import("traversal.zig");

const Allocator = std.mem.Allocator;

pub const Error = anyerror;

pub fn transformFile(allocator: Allocator, io: std.Io, input_path: []const u8, loader: []const u8) Error![]u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        input_path,
        allocator,
        .limited(64 * 1024 * 1024),
    );
    defer allocator.free(source);

    return transformSource(allocator, input_path, source, loader);
}

pub fn transformSource(allocator: Allocator, path: []const u8, source: []const u8, loader: []const u8) Error![]u8 {
    const lang = langForLoader(loader) orelse return error.UnsupportedTransformLoader;
    const source_for_parse = try rewriteSimpleTopLevelDynamicImports(allocator, source);
    defer allocator.free(source_for_parse);

    var tree = parser.parse(allocator, source_for_parse, .{
        .source_type = .module,
        .lang = lang,
    }) catch return error.TransformCommandFailed;
    defer tree.deinit();

    if (tree.hasErrors()) {
        return error.TransformCommandFailed;
    }

    const jsx_runtime: parser.codegen.JSXRuntime = if (std.mem.eql(u8, loader, "jsx") or std.mem.eql(u8, loader, "tsx"))
        .automatic
    else
        .preserve;

    var result = parser.codegen.strip(allocator, &tree, .{
        .format = .compact,
        .quotes = .double,
        .final_newline = true,
        .jsx_runtime = jsx_runtime,
    }) catch return error.TransformCommandFailed;
    defer result.deinit(allocator);

    const normalized = try replaceAll(allocator, result.code, "import.meta.env", "globalThis.__zigImportMetaEnv");
    defer allocator.free(normalized);

    const normalized_require = try replaceAll(allocator, normalized, "import.meta.require", "globalThis.__zigImportMetaRequire");
    defer allocator.free(normalized_require);

    const normalized_using = try replaceAll(allocator, normalized_require, "using ", "const ");
    defer allocator.free(normalized_using);

    // Large generated modules (for example from build onLoad hooks) can contain
    // thousands of JSX factory calls; key-lifting becomes disproportionately slow
    // there and offers little value for those synthetic outputs.
    const normalized_jsx_keys = if (normalized_using.len > 256 * 1024)
        try allocator.dupe(u8, normalized_using)
    else
        try liftAutomaticJsxKeys(allocator, normalized_using);
    defer allocator.free(normalized_jsx_keys);

    if (jsx_runtime == .automatic and
        (std.mem.indexOf(u8, normalized_jsx_keys, "__zigJsx(") != null or
        std.mem.indexOf(u8, normalized_jsx_keys, "__zigJsxs(") != null))
    {
        return insertAfterImportBlock(
            allocator,
            normalized_jsx_keys,
            "import {jsx as __zigJsx, jsxs as __zigJsxs, Fragment as __zigFragment} from \"react/jsx-runtime\";\n",
        );
    }

    if (jsx_runtime == .classic and std.mem.indexOf(u8, normalized_using, "React.createElement") != null) {
        const aliased = try replaceAll(allocator, normalized_using, "React.createElement", "__zigReactCreateElement");
        defer allocator.free(aliased);

        if (!hasClassicReactImport(source)) {
            return std.mem.concat(allocator, u8, &.{ "import React from \"react\";\nconst __zigReactCreateElement = React.createElement;\n", aliased });
        }

        return insertAfterImportBlock(allocator, aliased, "const __zigReactCreateElement = React.createElement;\n");
    }

    _ = path;
    return allocator.dupe(u8, normalized_jsx_keys);
}

fn liftAutomaticJsxKeys(allocator: Allocator, source: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, source, "__zigJsx(") == null and std.mem.indexOf(u8, source, "__zigJsxs(") == null) {
        return allocator.dupe(u8, source);
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    var emit_from: usize = 0;
    var changed = false;

    while (true) {
        const jsx_idx = std.mem.indexOfPos(u8, source, cursor, "__zigJsx(");
        const jsxs_idx = std.mem.indexOfPos(u8, source, cursor, "__zigJsxs(");
        if (jsx_idx == null and jsxs_idx == null) break;

        const call_start: usize, const name_len: usize = blk: {
            if (jsx_idx) |idx| {
                if (jsxs_idx) |idxs| {
                    if (idx <= idxs) break :blk .{ idx, "__zigJsx".len };
                    break :blk .{ idxs, "__zigJsxs".len };
                }
                break :blk .{ idx, "__zigJsx".len };
            }
            break :blk .{ jsxs_idx.?, "__zigJsxs".len };
        };
        const open_paren = call_start + name_len;
        const close_paren = traversal.findMatchingDelimiter(source, open_paren, '(', ')') orelse {
            cursor = call_start + 1;
            continue;
        };

        const rewritten = try rewriteAutomaticJsxCallWithLeadingKey(allocator, source[call_start .. close_paren + 1], name_len);
        if (rewritten) |replacement| {
            defer allocator.free(replacement);
            changed = true;
            try out.appendSlice(allocator, source[emit_from..call_start]);
            try out.appendSlice(allocator, replacement);
            emit_from = close_paren + 1;
            cursor = emit_from;
        } else {
            // Keep scanning inside this call so nested JSX nodes can be rewritten.
            cursor = call_start + 1;
        }
    }

    if (!changed) {
        return allocator.dupe(u8, source);
    }

    try out.appendSlice(allocator, source[emit_from..]);
    return out.toOwnedSlice(allocator);
}

fn rewriteAutomaticJsxCallWithLeadingKey(
    allocator: Allocator,
    call_source: []const u8,
    name_len: usize,
) !?[]u8 {
    if (call_source.len <= name_len + 2 or call_source[name_len] != '(' or call_source[call_source.len - 1] != ')') {
        return null;
    }

    const args = call_source[name_len + 1 .. call_source.len - 1];
    const first_comma = traversal.findTopLevelDelimiter(args, 0, ',') orelse return null;

    const props_start = traversal.skipAsciiSpaces(args, first_comma + 1);
    if (props_start >= args.len or args[props_start] != '{') return null;

    const props_end = traversal.findMatchingDelimiter(args, props_start, '{', '}') orelse return null;
    const after_props = traversal.skipAsciiSpaces(args, props_end + 1);
    if (after_props < args.len and args[after_props] == ',') return null;

    const obj_inner = args[props_start + 1 .. props_end];
    var key_value: ?[]const u8 = null;
    var rewritten_inner: std.ArrayList(u8) = .empty;
    defer rewritten_inner.deinit(allocator);

    var segment_start: usize = 0;
    var kept_count: usize = 0;
    while (segment_start <= obj_inner.len) {
        const comma_index = traversal.findTopLevelDelimiter(obj_inner, segment_start, ',');
        const segment_end = comma_index orelse obj_inner.len;
        const segment = std.mem.trim(u8, obj_inner[segment_start..segment_end], " \t\r\n");
        if (segment.len > 0) {
            const lifted = extractKeyPropertyValue(segment);
            if (key_value == null) {
                key_value = lifted;
            }
            if (key_value == null or lifted == null) {
                if (kept_count > 0) try rewritten_inner.append(allocator, ',');
                try rewritten_inner.appendSlice(allocator, segment);
                kept_count += 1;
            }
        }
        if (comma_index == null) break;
        segment_start = comma_index.? + 1;
    }
    const lifted_key = key_value orelse return null;

    var rewritten_props: std.ArrayList(u8) = .empty;
    defer rewritten_props.deinit(allocator);
    try rewritten_props.append(allocator, '{');
    if (rewritten_inner.items.len > 0) try rewritten_props.appendSlice(allocator, rewritten_inner.items);
    try rewritten_props.append(allocator, '}');

    var rewritten: std.ArrayList(u8) = .empty;
    errdefer rewritten.deinit(allocator);
    try rewritten.appendSlice(allocator, call_source[0 .. name_len + 1]);
    try rewritten.appendSlice(allocator, args[0..props_start]);
    try rewritten.appendSlice(allocator, rewritten_props.items);
    try rewritten.appendSlice(allocator, args[props_end + 1 ..]);
    try rewritten.append(allocator, ',');
    try rewritten.appendSlice(allocator, lifted_key);
    try rewritten.append(allocator, ')');
    const owned = try rewritten.toOwnedSlice(allocator);
    return owned;
}

fn extractKeyPropertyValue(segment: []const u8) ?[]const u8 {
    if (segment.len == 0) return null;
    if (std.mem.startsWith(u8, segment, "...")) return null;
    var cursor = traversal.skipAsciiSpaces(segment, 0);
    if (cursor >= segment.len) return null;

    if (segment[cursor] == '"') {
        if (!std.mem.startsWith(u8, segment[cursor..], "\"key\"")) return null;
        cursor += "\"key\"".len;
    } else if (std.mem.startsWith(u8, segment[cursor..], "key")) {
        if (cursor + "key".len < segment.len) {
            const next = segment[cursor + "key".len];
            if (std.ascii.isAlphanumeric(next) or next == '_' or next == '$') return null;
        }
        cursor += "key".len;
    } else {
        return null;
    }

    cursor = traversal.skipAsciiSpaces(segment, cursor);
    if (cursor >= segment.len or segment[cursor] != ':') return null;
    const value = std.mem.trim(u8, segment[cursor + 1 ..], " \t\r\n");
    if (value.len == 0) return null;
    return value;
}

fn insertAfterImportBlock(allocator: Allocator, source: []const u8, insertion: []const u8) ![]u8 {
    var cursor: usize = 0;
    var insert_at: usize = 0;
    while (nextImportStatement(source, cursor)) |range| {
        insert_at = range.end;
        cursor = range.end;
    }

    return std.mem.concat(allocator, u8, &.{ source[0..insert_at], insertion, source[insert_at..] });
}

const ImportRange = struct {
    start: usize,
    end: usize,
};

fn nextImportStatement(source: []const u8, start: usize) ?ImportRange {
    var cursor = start;
    while (cursor < source.len) {
        while (cursor < source.len and (source[cursor] == ' ' or source[cursor] == '\t' or source[cursor] == '\r' or source[cursor] == '\n')) cursor += 1;
        if (!std.mem.startsWith(u8, source[cursor..], "import")) return null;
        const after = cursor + "import".len;
        if (after < source.len and (std.ascii.isAlphanumeric(source[after]) or source[after] == '_' or source[after] == '$')) return null;

        var end = after;
        while (end < source.len and source[end] != '\n' and source[end] != ';') end += 1;
        if (end < source.len and source[end] == ';') end += 1;
        if (end < source.len and source[end] == '\n') end += 1;
        return .{ .start = cursor, .end = end };
    }
    return null;
}

fn langForLoader(loader: []const u8) ?parser.ast.Lang {
    if (std.mem.eql(u8, loader, "ts")) return .ts;
    if (std.mem.eql(u8, loader, "tsx")) return .tsx;
    if (std.mem.eql(u8, loader, "jsx")) return .jsx;
    if (std.mem.eql(u8, loader, "js")) return .js;
    return null;
}

fn hasClassicReactImport(source: []const u8) bool {
    return std.mem.indexOf(u8, source, "import React") != null or
        std.mem.indexOf(u8, source, "import * as React") != null;
}

fn rewriteSimpleTopLevelDynamicImports(allocator: Allocator, source: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, source, "await import(") == null) return allocator.dupe(u8, source);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (try rewriteDynamicImportLine(allocator, &out, line)) {
            try out.append(allocator, '\n');
            continue;
        }
        try out.appendSlice(allocator, line);
        try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

fn rewriteDynamicImportLine(allocator: Allocator, out: *std.ArrayList(u8), line: []const u8) !bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len != line.len) return false;
    if (!std.mem.startsWith(u8, trimmed, "const ")) return false;
    const eq_index = std.mem.indexOf(u8, trimmed, " = await import(") orelse return false;
    const binding = std.mem.trim(u8, trimmed["const ".len..eq_index], " \t");
    const after_import = trimmed[eq_index + " = await import(".len ..];
    if (after_import.len < 3) return false;
    const quote = after_import[0];
    if (quote != '\'' and quote != '"') return false;
    const rest = after_import[1..];
    const quote_end = std.mem.indexOfScalar(u8, rest, quote) orelse return false;
    const specifier = rest[0..quote_end];
    const after_specifier = std.mem.trim(u8, rest[quote_end + 1 ..], " \t");

    if (std.mem.startsWith(u8, binding, "{") and std.mem.endsWith(u8, binding, "}")) {
        if (!std.mem.startsWith(u8, after_specifier, ");")) return false;
        try out.print(allocator, "import {s} from \"{s}\";", .{ binding, specifier });
        return true;
    }

    if (std.mem.startsWith(u8, after_specifier, ");")) {
        try out.print(allocator, "import * as {s} from \"{s}\";", .{ binding, specifier });
        return true;
    }

    if (std.mem.startsWith(u8, after_specifier, ").then(") and
        std.mem.indexOf(u8, after_specifier, "=>") != null and
        std.mem.indexOf(u8, after_specifier, ".default") != null)
    {
        try out.print(allocator, "import {s} from \"{s}\";", .{ binding, specifier });
        return true;
    }

    return false;
}

fn replaceAll(allocator: Allocator, source: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, source);

    var count: usize = 0;
    var cursor: usize = 0;
    while (std.mem.indexOf(u8, source[cursor..], needle)) |relative| {
        count += 1;
        cursor += relative + needle.len;
    }

    if (count == 0) return allocator.dupe(u8, source);

    const new_len = source.len + count * (replacement.len - needle.len);
    var out = try allocator.alloc(u8, new_len);
    errdefer allocator.free(out);

    var read_cursor: usize = 0;
    var write_cursor: usize = 0;
    while (std.mem.indexOf(u8, source[read_cursor..], needle)) |relative| {
        const match_start = read_cursor + relative;
        @memcpy(out[write_cursor..][0 .. match_start - read_cursor], source[read_cursor..match_start]);
        write_cursor += match_start - read_cursor;
        @memcpy(out[write_cursor..][0..replacement.len], replacement);
        write_cursor += replacement.len;
        read_cursor = match_start + needle.len;
    }
    @memcpy(out[write_cursor..], source[read_cursor..]);

    return out;
}

test "yuku transform strips TypeScript" {
    const source =
        \\import type { Foo } from "./types";
        \\const value: string = "ok" as string;
        \\export default value;
    ;
    const out = try transformSource(std.testing.allocator, "sample.ts", source, "ts");
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "import type") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, ": string") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, " as string") == null);
}

test "yuku transform lowers JSX with automatic runtime" {
    const source =
        \\export const view = <button disabled className="x">Save</button>;
    ;
    const out = try transformSource(std.testing.allocator, "sample.tsx", source, "tsx");
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "__zigJsx(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "react/jsx-runtime") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<button") == null);
}

test "yuku transform automatic JSX children avoids sparse arrays" {
    const source =
        \\export const view = (
        \\  <div>
        \\    {true && <span>A</span>}
        \\    <span>B</span>
        \\  </div>
        \\);
    ;
    const out = try transformSource(std.testing.allocator, "sample.tsx", source, "tsx");
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, ", ,") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "[,") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, ",]") == null);
}

test "yuku transform automatic JSX props keeps spread syntax" {
    const source =
        \\const extra = { role: "button" };
        \\export const view = <button className="x" {...extra} disabled />;
    ;
    const out = try transformSource(std.testing.allocator, "sample.tsx", source, "tsx");
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "Object.assign(") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "...extra") != null);
}

test "yuku transform automatic JSX emits jsxs for multi-child nodes" {
    const source =
        \\export const view = <div><span>A</span><span>B</span></div>;
    ;
    const out = try transformSource(std.testing.allocator, "sample.tsx", source, "tsx");
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "__zigJsxs(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "jsxs as __zigJsxs") != null);
}

test "yuku transform automatic JSX lifts key out of props" {
    const source =
        \\const id = "file-id";
        \\export const view = <div key={id} role="treeitem">child</div>;
    ;
    const out = try transformSource(std.testing.allocator, "sample.tsx", source, "tsx");
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "\"key\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, ",id)") != null);
}

test "automatic JSX key rewrite handles template literals" {
    const call =
        \\__zigJsxs("div", {"key": file.id, "role": "treeitem", children: [__zigJsxs(Link, {"to": `/app/page/${wiki.id}/${file.id}${search}`})]})
    ;
    const rewritten = (try rewriteAutomaticJsxCallWithLeadingKey(std.testing.allocator, call, "__zigJsxs".len)).?;
    defer std.testing.allocator.free(rewritten);

    try std.testing.expect(std.mem.indexOf(u8, rewritten, "\"key\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, ",file.id)") != null);
}

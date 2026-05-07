const std = @import("std");
const parser = @import("yuku_parser");

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
        .classic
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

    if (jsx_runtime == .classic and
        std.mem.indexOf(u8, normalized_using, "React.createElement") != null and
        !hasClassicReactImport(source))
    {
        return std.mem.concat(allocator, u8, &.{ "import React from \"react\";\n", normalized_using });
    }

    _ = path;
    return allocator.dupe(u8, normalized_using);
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

test "yuku transform lowers JSX classic runtime" {
    const source =
        \\export const view = <button disabled className="x">Save</button>;
    ;
    const out = try transformSource(std.testing.allocator, "sample.tsx", source, "tsx");
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "React.createElement") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<button") == null);
}

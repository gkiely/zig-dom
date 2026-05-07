const std = @import("std");
const parser = @import("yuku_parser");

const Allocator = std.mem.Allocator;

pub const Error = anyerror;

pub const Entry = struct {
    input_path: []const u8,
    loader: []const u8,
    output_path: []const u8,
};

pub fn transformFile(allocator: Allocator, io: std.Io, entry: Entry) Error!void {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        entry.input_path,
        allocator,
        .limited(64 * 1024 * 1024),
    );
    defer allocator.free(source);

    const transformed = try transformSource(allocator, entry.input_path, source, entry.loader);
    defer allocator.free(transformed);

    var atomic_output = try std.Io.Dir.cwd().createFileAtomic(io, entry.output_path, .{
        .make_path = true,
        .replace = true,
    });
    defer atomic_output.deinit(io);
    try atomic_output.file.writeStreamingAll(io, transformed);
    try atomic_output.replace(io);
}

pub fn transformSource(allocator: Allocator, path: []const u8, source: []const u8, loader: []const u8) Error![]u8 {
    const lang = langForLoader(loader) orelse return error.UnsupportedTransformLoader;

    var tree = parser.parse(allocator, source, .{
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
        .format = .pretty,
        .quotes = .double,
        .final_newline = true,
        .jsx_runtime = jsx_runtime,
    }) catch return error.TransformCommandFailed;
    defer result.deinit(allocator);

    const normalized = try replaceAll(allocator, result.code, "import.meta.env", "globalThis.__zigImportMetaEnv");
    defer allocator.free(normalized);

    const normalized_require = try replaceAll(allocator, normalized, "import.meta.require", "globalThis.__zigImportMetaRequire");
    defer allocator.free(normalized_require);

    if (jsx_runtime == .classic and
        std.mem.indexOf(u8, normalized_require, "React.createElement") != null and
        !hasClassicReactImport(source))
    {
        return std.mem.concat(allocator, u8, &.{ "import React from \"react\";\n", normalized_require });
    }

    _ = path;
    return allocator.dupe(u8, normalized_require);
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

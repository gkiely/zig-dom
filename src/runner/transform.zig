const std = @import("std");

const Allocator = std.mem.Allocator;

pub const TransformError = error{
    TransformCommandFailed,
};

pub const PreparedPaths = struct {
    paths: []const []u8,
    transformed_count: usize,

    pub fn deinit(self: PreparedPaths, allocator: Allocator) void {
        for (self.paths) |path| {
            allocator.free(path);
        }
        allocator.free(self.paths);
    }
};

const TransformEntry = struct {
    input_path: []const u8,
    output_path: []const u8,
    loader: []const u8,
};

pub fn runUpfront(allocator: Allocator, io: std.Io, discovered_paths: []const []u8) !PreparedPaths {
    _ = io;

    var prepared_paths: std.ArrayList([]u8) = .empty;
    errdefer {
        for (prepared_paths.items) |path| {
            allocator.free(path);
        }
        prepared_paths.deinit(allocator);
    }

    for (discovered_paths) |path| {
        try prepared_paths.append(allocator, try allocator.dupe(u8, path));
    }

    return .{
        .paths = try prepared_paths.toOwnedSlice(allocator),
        .transformed_count = 0,
    };
}

pub fn buildModuleOutputPath(allocator: Allocator, path: []const u8) ![]u8 {
    const basename = std.fs.path.basename(path);
    const stem = std.fs.path.stem(basename);
    var sanitized: std.ArrayList(u8) = .empty;
    defer sanitized.deinit(allocator);

    for (stem) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '.' or char == '-' or char == '_') {
            try sanitized.append(allocator, char);
        } else {
            try sanitized.append(allocator, '_');
        }
    }

    const digest = std.hash.Wyhash.hash(0, path);
    return std.fmt.allocPrint(
        allocator,
        "./.zig-dom-cache/transformed/modules/{x}-{s}.cjs",
        .{ digest, sanitized.items },
    );
}

pub fn loaderForPath(path: []const u8) ?[]const u8 {
    if (std.mem.endsWith(u8, path, ".ts")) {
        return "ts";
    }

    if (std.mem.endsWith(u8, path, ".tsx")) {
        return "tsx";
    }

    if (std.mem.endsWith(u8, path, ".jsx")) {
        return "jsx";
    }

    if (std.mem.endsWith(u8, path, ".js")) {
        return "js";
    }

    return null;
}

pub fn transformModuleToPath(allocator: Allocator, io: std.Io, input_path: []const u8, output_path: []const u8) !void {
    const loader = loaderForPath(input_path) orelse return error.TransformCommandFailed;
    const exit_code = try runTransformProcess(allocator, io, &.{.{
        .input_path = input_path,
        .output_path = output_path,
        .loader = loader,
    }});
    if (exit_code != 0) {
        return error.TransformCommandFailed;
    }
}

fn runTransformProcess(allocator: Allocator, io: std.Io, entries: []const TransformEntry) !u8 {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);

    try args.appendSlice(allocator, &.{
        "bun",
        "run",
        "scripts/transform-tests.ts",
        "--cache-dir",
        ".zig-dom-cache/transformed",
    });

    for (entries) |entry| {
        try args.appendSlice(allocator, &.{ "--file", entry.input_path });
        try args.appendSlice(allocator, &.{ "--loader", entry.loader });
        try args.appendSlice(allocator, &.{ "--out", entry.output_path });
    }

    var child = std.process.spawn(io, .{
        .argv = args.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("Required command not found: {s}", .{args.items[0]});
            return 127;
        },
        else => return err,
    };

    const term = try child.wait(io);
    return switch (term) {
        .exited => |code| code,
        .signal => {
            std.log.err("Transform helper terminated by signal.", .{});
            return 1;
        },
        .stopped => {
            std.log.err("Transform helper stopped unexpectedly.", .{});
            return 1;
        },
        .unknown => {
            std.log.err("Transform helper ended unexpectedly.", .{});
            return 1;
        },
    };
}

test "loaderForPath matches transform extensions" {
    try std.testing.expectEqualStrings("ts", loaderForPath("foo.test.ts").?);
    try std.testing.expectEqualStrings("tsx", loaderForPath("foo.test.tsx").?);
    try std.testing.expectEqualStrings("jsx", loaderForPath("foo.test.jsx").?);
    try std.testing.expectEqualStrings("js", loaderForPath("foo.test.js").?);
}

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const TransformError = error{
    TransformCommandFailed,
    UnsupportedTransformLoader,
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

pub const PreparedTransforms = struct {
    outputs: []const []u8,
    transformed_count: usize,

    pub fn deinit(self: PreparedTransforms, allocator: Allocator) void {
        for (self.outputs) |path| {
            allocator.free(path);
        }
        allocator.free(self.outputs);
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

pub fn buildModuleOutputPath(allocator: Allocator, io: std.Io, path: []const u8) ![]u8 {
    const loader = loaderForPath(path) orelse return error.TransformCommandFailed;
    if (!needsTransform(path)) {
        return error.UnsupportedTransformLoader;
    }

    const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
    if (stat.kind != .file) {
        return error.TransformCommandFailed;
    }

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

    var hasher = std.hash.Wyhash.init(0);
    hasher.update(path);
    hasher.update(loader);
    hasher.update(transformOptionsSignature(loader));
    hasher.update(std.mem.asBytes(&stat.size));
    hasher.update(std.mem.asBytes(&stat.mtime.nanoseconds));
    const digest = hasher.final();

    return std.fmt.allocPrint(
        allocator,
        "./.zig-dom-cache/transformed/modules/{x}-{s}.js",
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

    if (std.mem.endsWith(u8, path, ".mjs")) {
        return "js";
    }

    if (std.mem.endsWith(u8, path, ".cjs")) {
        return "js";
    }

    if (std.mem.endsWith(u8, path, ".json")) {
        return "json";
    }

    return null;
}

pub fn needsTransform(path: []const u8) bool {
    const loader = loaderForPath(path) orelse return false;
    return !std.mem.eql(u8, loader, "js") and !std.mem.eql(u8, loader, "json");
}

pub fn prepareModuleTransforms(
    allocator: Allocator,
    io: std.Io,
    module_paths: []const []const u8,
) !PreparedTransforms {
    var outputs: std.ArrayList([]u8) = .empty;
    errdefer {
        for (outputs.items) |path| {
            allocator.free(path);
        }
        outputs.deinit(allocator);
    }

    var pending: std.ArrayList(TransformEntry) = .empty;
    defer pending.deinit(allocator);

    for (module_paths) |module_path| {
        if (!needsTransform(module_path)) {
            return error.UnsupportedTransformLoader;
        }

        const loader = loaderForPath(module_path) orelse return error.TransformCommandFailed;
        const output_path = try buildModuleOutputPath(allocator, io, module_path);
        errdefer allocator.free(output_path);

        try outputs.append(allocator, output_path);

        if (!outputExists(io, output_path)) {
            try pending.append(allocator, .{
                .input_path = module_path,
                .output_path = output_path,
                .loader = loader,
            });
        }
    }

    if (pending.items.len > 0) {
        const exit_code = try runTransformProcess(allocator, io, pending.items);
        if (exit_code != 0) {
            return error.TransformCommandFailed;
        }
    }

    return .{
        .outputs = try outputs.toOwnedSlice(allocator),
        .transformed_count = pending.items.len,
    };
}

fn outputExists(io: std.Io, path: []const u8) bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .file;
}

fn transformOptionsSignature(loader: []const u8) []const u8 {
    if (std.mem.eql(u8, loader, "tsx") or std.mem.eql(u8, loader, "jsx")) {
        return "jsx-classic-auto-react-import-v1";
    }

    return "esm-preserve-v2";
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

test "needsTransform skips javascript" {
    try std.testing.expect(needsTransform("foo.ts"));
    try std.testing.expect(needsTransform("foo.tsx"));
    try std.testing.expect(needsTransform("foo.jsx"));
    try std.testing.expect(!needsTransform("foo.js"));
}

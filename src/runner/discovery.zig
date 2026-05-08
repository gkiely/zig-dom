const std = @import("std");

const Allocator = std.mem.Allocator;

pub const DiscoveredTests = struct {
    paths: []const []u8,

    pub fn deinit(self: DiscoveredTests, allocator: Allocator) void {
        for (self.paths) |path| {
            allocator.free(path);
        }
        allocator.free(self.paths);
    }
};

pub fn discoverTests(allocator: Allocator, io: std.Io, patterns: []const []const u8) !DiscoveredTests {
    var dedup = std.StringHashMap(void).init(allocator);
    defer dedup.deinit();

    var results: std.ArrayList([]u8) = .empty;
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit(allocator);
    }

    for (patterns) |pattern| {
        if (pattern.len == 0) {
            continue;
        }

        try collectPattern(allocator, io, pattern, &dedup, &results);
    }

    std.mem.sort([]u8, results.items, {}, lessThanPath);
    return .{ .paths = try results.toOwnedSlice(allocator) };
}

fn collectPattern(
    allocator: Allocator,
    io: std.Io,
    pattern: []const u8,
    dedup: *std.StringHashMap(void),
    results: *std.ArrayList([]u8),
) !void {
    const cwd = std.Io.Dir.cwd();
    const stat = cwd.statFile(io, pattern, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };

    switch (stat.kind) {
        .directory => try collectDirectory(allocator, io, pattern, dedup, results),
        .file => {
            if (!isSupportedTestFile(pattern)) {
                return;
            }
            try appendIfMissing(allocator, pattern, dedup, results);
        },
        else => {},
    }
}

fn collectDirectory(
    allocator: Allocator,
    io: std.Io,
    dir_path: []const u8,
    dedup: *std.StringHashMap(void),
    results: *std.ArrayList([]u8),
) !void {
    const dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        if (!isSupportedTestFile(entry.path)) {
            continue;
        }

        const relative_path = if (std.mem.eql(u8, dir_path, "."))
            try allocator.dupe(u8, entry.path)
        else
            try std.fs.path.join(allocator, &.{ dir_path, entry.path });
        defer allocator.free(relative_path);

        try appendIfMissing(allocator, relative_path, dedup, results);
    }
}

fn appendIfMissing(
    allocator: Allocator,
    path: []const u8,
    dedup: *std.StringHashMap(void),
    results: *std.ArrayList([]u8),
) !void {
    if (dedup.contains(path)) {
        return;
    }

    const owned = try allocator.dupe(u8, path);
    errdefer allocator.free(owned);

    try dedup.put(owned, {});
    try results.append(allocator, owned);
}

fn isSupportedTestFile(path: []const u8) bool {
    const ext = std.fs.path.extension(path);
    if (!(std.mem.eql(u8, ext, ".js") or
        std.mem.eql(u8, ext, ".ts") or
        std.mem.eql(u8, ext, ".jsx") or
        std.mem.eql(u8, ext, ".tsx")))
    {
        return false;
    }

    const basename = std.fs.path.basename(path);
    return std.mem.indexOf(u8, basename, ".test.") != null;
}

fn lessThanPath(_: void, left: []u8, right: []u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

test "discoverTests deduplicates and sorts" {
    const allocator = std.testing.allocator;
    const discovered = try discoverTests(allocator, std.testing.io, &.{ "tests/runner", "tests/runner" });
    defer discovered.deinit(allocator);

    try std.testing.expect(discovered.paths.len > 0);

    for (discovered.paths[1..], 1..) |path, index| {
        try std.testing.expect(std.mem.order(u8, discovered.paths[index - 1], path) == .lt);
    }
}

test "isSupportedTestFile accepts expected patterns" {
    try std.testing.expect(isSupportedTestFile("foo/basic.test.js"));
    try std.testing.expect(isSupportedTestFile("foo/selectors.probe.test.ts"));
    try std.testing.expect(isSupportedTestFile("foo/selectors-probe.test.ts"));

    try std.testing.expect(!isSupportedTestFile("foo/basic.js"));
    try std.testing.expect(!isSupportedTestFile("foo/basic.spec.ts"));
    try std.testing.expect(!isSupportedTestFile("foo/_test_alpha.tsx"));
    try std.testing.expect(!isSupportedTestFile("foo/_spec_beta.jsx"));
    try std.testing.expect(!isSupportedTestFile("foo/basic.test.mjs"));
}

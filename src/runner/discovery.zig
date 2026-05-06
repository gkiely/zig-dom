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

pub fn discoverTests(allocator: Allocator, patterns: []const []const u8) !DiscoveredTests {
    var results: std.ArrayList([]u8) = .empty;
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit(allocator);
    }

    for (patterns) |pattern| {
        if (pattern.len == 0) {
            continue;
        }

        var already_added = false;
        for (results.items) |existing| {
            if (std.mem.eql(u8, existing, pattern)) {
                already_added = true;
                break;
            }
        }

        if (already_added) {
            continue;
        }

        try results.append(allocator, try allocator.dupe(u8, pattern));
    }

    std.mem.sort([]u8, results.items, {}, lessThanPath);
    return .{ .paths = try results.toOwnedSlice(allocator) };
}

fn lessThanPath(_: void, left: []u8, right: []u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

test "discoverTests deduplicates and sorts" {
    const allocator = std.testing.allocator;
    const discovered = try discoverTests(allocator, &.{ "tests/unit", "tests/integration", "tests/unit" });
    defer discovered.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), discovered.paths.len);
    try std.testing.expectEqualStrings("tests/integration", discovered.paths[0]);
    try std.testing.expectEqualStrings("tests/unit", discovered.paths[1]);
}

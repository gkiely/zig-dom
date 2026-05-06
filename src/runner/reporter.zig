const std = @import("std");

pub fn printDiscovered(count: usize) void {
    std.debug.print("Discovered {d} test file{s}.\n", .{ count, if (count == 1) "" else "s" });
}

pub fn printTransformed(count: usize) void {
    std.debug.print("Upfront transformed {d} file{s}.\n", .{ count, if (count == 1) "" else "s" });
}

pub fn printNoTests(patterns: []const []const u8) void {
    std.debug.print("No test files matched patterns:\n", .{});
    for (patterns) |pattern| {
        std.debug.print("  - {s}\n", .{pattern});
    }
}

pub fn printDryRun(paths: []const []u8) void {
    std.debug.print("Dry run (no execution):\n", .{});
    for (paths) |path| {
        std.debug.print("  - {s}\n", .{path});
    }
}

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

pub fn printFileResult(
    path: []const u8,
    passed: usize,
    failed: usize,
    skipped: usize,
    timed_out: usize,
    collection_errors: usize,
) void {
    std.debug.print(
        "{s}: pass={d} fail={d} skip={d} timeout={d} collection={d}\n",
        .{ path, passed, failed, skipped, timed_out, collection_errors },
    );
}

pub fn printFailureReport(path: []const u8, report: []const u8) void {
    std.debug.print("\nFailures in {s}:\n{s}\n", .{ path, report });
}

pub fn printCollectionReport(path: []const u8, report: []const u8) void {
    std.debug.print("\nCollection errors in {s}:\n{s}\n", .{ path, report });
}

pub fn printSummary(
    total_passed: usize,
    total_failed: usize,
    total_skipped: usize,
    total_timed_out: usize,
    total_collection_errors: usize,
) void {
    std.debug.print(
        "\nSummary: pass={d} fail={d} skip={d} timeout={d} collection={d}\n",
        .{ total_passed, total_failed, total_skipped, total_timed_out, total_collection_errors },
    );
}

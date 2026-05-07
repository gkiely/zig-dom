const std = @import("std");

const red = "\x1b[31m";
const bold_red = "\x1b[1;31m";
const yellow = "\x1b[33m";
const dim = "\x1b[2m";
const reset = "\x1b[0m";

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
    std.debug.print("\n{s}Failures in {s}:{s}\n", .{ bold_red, path, reset });
    printColoredReport(report);
    std.debug.print("\n", .{});
}

pub fn printCollectionReport(path: []const u8, report: []const u8) void {
    std.debug.print("\n{s}Collection errors in {s}:{s}\n", .{ bold_red, path, reset });
    printColoredReport(report);
    std.debug.print("\n", .{});
}

fn printColoredReport(report: []const u8) void {
    var lines = std.mem.splitScalar(u8, report, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) {
            std.debug.print("\n", .{});
        } else if (std.mem.startsWith(u8, line, "    at ")) {
            std.debug.print("{s}{s}{s}\n", .{ dim, line, reset });
        } else if (std.mem.indexOf(u8, line, "Expected") != null or
            std.mem.indexOf(u8, line, "Unable to find") != null or
            std.mem.indexOf(u8, line, "not a function") != null or
            std.mem.indexOf(u8, line, "is not defined") != null)
        {
            std.debug.print("{s}{s}{s}\n", .{ yellow, line, reset });
        } else if (!std.mem.startsWith(u8, line, " ") and !std.mem.startsWith(u8, line, "\t")) {
            std.debug.print("{s}{s}{s}\n", .{ red, line, reset });
        } else {
            std.debug.print("{s}\n", .{line});
        }
    }
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

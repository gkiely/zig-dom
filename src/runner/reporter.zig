const std = @import("std");

const green = "\x1b[32m";
const red = "\x1b[31m";
const bold = "\x1b[1m";
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

pub fn printBanner(version: []const u8, commit_sha: []const u8) void {
    std.debug.print("{s}zig-dom test{s} {s}v{s} ({s}){s}\n\n", .{ bold, reset, dim, version, commit_sha, reset });
}

pub fn printFileResult(
    path: []const u8,
    passed: usize,
    failed: usize,
    skipped: usize,
    timed_out: usize,
    collection_errors: usize,
    passed_report: ?[]const u8,
) void {
    std.debug.print("{s}:\n", .{path});
    if (passed_report) |report| {
        var lines = std.mem.splitScalar(u8, report, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const tab_index = std.mem.lastIndexOfScalar(u8, line, '\t');
            if (tab_index) |index| {
                std.debug.print("{s}✓{s} {s}{s}{s} {s}[{s}ms]{s}\n", .{ green, reset, bold, line[0..index], reset, dim, line[index + 1 ..], reset });
            } else {
                std.debug.print("{s}✓{s} {s}{s}{s}\n", .{ green, reset, bold, line, reset });
            }
        }
    }
    if (skipped > 0 or timed_out > 0 or collection_errors > 0) {
        std.debug.print("{s}skip={d} timeout={d} collection={d}{s}\n", .{ dim, skipped, timed_out, collection_errors, reset });
    }
    if (failed > 0 and passed == 0 and passed_report == null) {
        std.debug.print("{s}fail={d}{s}\n", .{ red, failed, reset });
    }
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
    total_expect_calls: usize,
    file_count: usize,
    elapsed_ms: f64,
) void {
    std.debug.print("\n {s}{d} pass{s}\n", .{ green, total_passed, reset });
    std.debug.print(" {s}{d} fail{s}\n", .{ if (total_failed == 0) dim else red, total_failed, reset });
    if (total_skipped > 0 or total_timed_out > 0 or total_collection_errors > 0) {
        std.debug.print(" {s}{d} skip, {d} timeout, {d} collection{s}\n", .{ dim, total_skipped, total_timed_out, total_collection_errors, reset });
    }
    std.debug.print(" {d} expect() calls\n", .{total_expect_calls});
    const test_word = if (total_passed + total_failed == 1) "test" else "tests";
    const file_word = if (file_count == 1) "file" else "files";
    std.debug.print("Ran {d} {s} across {d} {s}. {s}[{d:.2}ms]{s}\n", .{ total_passed + total_failed, test_word, file_count, file_word, dim, elapsed_ms, reset });
}

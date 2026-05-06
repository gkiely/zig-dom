const std = @import("std");

pub const ParseError = error{
    UnknownCommand,
};

const default_test_patterns = [_][]const u8{"tests"};

pub const TestCommand = struct {
    patterns: []const []const u8,
    dry_run: bool,
};

pub const ArgsCommand = struct {
    args: []const []const u8,
};

pub const ParsedCommand = union(enum) {
    help,
    test_cmd: TestCommand,
    wpt_cmd: ArgsCommand,
    wpt_sync,
    wpt_manifest_cmd: ArgsCommand,
};

pub fn parse(args: []const []const u8) ParseError!ParsedCommand {
    if (args.len == 0) {
        return .help;
    }

    const name = args[0];

    if (std.mem.eql(u8, name, "help") or std.mem.eql(u8, name, "--help") or std.mem.eql(u8, name, "-h")) {
        return .help;
    }

    if (std.mem.eql(u8, name, "test")) {
        var dry_run = false;
        var first_pattern: usize = 1;
        while (first_pattern < args.len) : (first_pattern += 1) {
            if (std.mem.eql(u8, args[first_pattern], "--dry-run")) {
                dry_run = true;
                continue;
            }
            break;
        }

        const patterns = if (first_pattern < args.len) args[first_pattern..] else default_test_patterns[0..];
        return .{ .test_cmd = .{ .patterns = patterns, .dry_run = dry_run } };
    }

    if (std.mem.eql(u8, name, "wpt")) {
        return .{ .wpt_cmd = .{ .args = args[1..] } };
    }

    if (std.mem.eql(u8, name, "wpt-sync")) {
        return .wpt_sync;
    }

    if (std.mem.eql(u8, name, "wpt-manifest")) {
        return .{ .wpt_manifest_cmd = .{ .args = args[1..] } };
    }

    return error.UnknownCommand;
}

pub fn printHelp() void {
    std.debug.print(
        \\zig-dom CLI (M1 skeleton)
        \\
        \\Usage:
        \\  zig build run -- help
        \\  zig build run -- test [--dry-run] [patterns...]
        \\  zig build run -- wpt [args...]
        \\  zig build run -- wpt-sync
        \\  zig build run -- wpt-manifest [args...]
        \\
        \\Examples:
        \\  zig build run -- test tests/runner/basic.test.js
        \\  zig build run -- wpt --manifest wpt/manifest/dom-core.json --expected wpt/expected/dom-core.json
        \\  zig build run -- wpt-sync
        \\  zig build run -- wpt-manifest --dir dom --out wpt/manifest/upstream-dom-smoke.json
        \\
        \\Notes:
        \\  - test currently delegates execution to Bun while Zig runtime work is in progress.
        \\  - wpt and wpt-manifest forward to existing scripts in scripts/.
        \\
        ,
        .{},
    );
}

test "parse returns help for empty args" {
    const command = try parse(&.{});
    try std.testing.expect(std.meta.activeTag(command) == .help);
}

test "parse test command with defaults" {
    const command = try parse(&.{"test"});
    try std.testing.expect(std.meta.activeTag(command) == .test_cmd);

    switch (command) {
        .test_cmd => |test_command| {
            try std.testing.expect(test_command.patterns.len == 1);
            try std.testing.expectEqualStrings("tests", test_command.patterns[0]);
            try std.testing.expect(!test_command.dry_run);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse wpt command" {
    const command = try parse(&.{ "wpt", "--manifest", "foo.json" });
    try std.testing.expect(std.meta.activeTag(command) == .wpt_cmd);
}
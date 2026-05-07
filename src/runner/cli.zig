const std = @import("std");

pub const ParseError = error{
    UnknownCommand,
};

pub const TestCommand = struct {
    args: []const []const u8,
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
        return .{ .test_cmd = .{ .args = args[1..] } };
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
                \\  zig build run -- test [--root <dir>] [--setup <file>]... [--dry-run] [patterns...]
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
            \\  - test executes through the embedded QuickJS-ng runtime and Zig runner harness.
            \\  - with --root, test auto-loads [test].preload from <root>/bunfig.toml when present.
            \\  - explicit --setup values are additive and run after bunfig preloads.
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
            try std.testing.expect(test_command.args.len == 0);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse test command keeps raw args" {
    const command = try parse(&.{ "test", "--setup", "setup.ts", "--dry-run", "tests/runner" });
    try std.testing.expect(std.meta.activeTag(command) == .test_cmd);

    switch (command) {
        .test_cmd => |test_command| {
            try std.testing.expect(test_command.args.len == 4);
            try std.testing.expectEqualStrings("--setup", test_command.args[0]);
            try std.testing.expectEqualStrings("setup.ts", test_command.args[1]);
            try std.testing.expectEqualStrings("--dry-run", test_command.args[2]);
            try std.testing.expectEqualStrings("tests/runner", test_command.args[3]);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse wpt command" {
    const command = try parse(&.{ "wpt", "--manifest", "foo.json" });
    try std.testing.expect(std.meta.activeTag(command) == .wpt_cmd);
}
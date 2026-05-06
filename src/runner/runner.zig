const std = @import("std");
const cli = @import("cli.zig");
const discovery = @import("discovery.zig");
const reporter = @import("reporter.zig");

const Allocator = std.mem.Allocator;

pub const RunnerError = error{
    MissingValueAfterOut,
};

pub fn run(allocator: Allocator, io: std.Io, command: cli.ParsedCommand) !u8 {
    switch (command) {
        .help => {
            cli.printHelp();
            return 0;
        },
        .test_cmd => |test_command| {
            return runTestCommand(allocator, io, test_command);
        },
        .wpt_sync => {
            return runSimpleScript(allocator, io, "scripts/sync-wpt.ts", &.{});
        },
        .wpt_cmd => |args_command| {
            return runSimpleScript(allocator, io, "scripts/run-wpt-subset.ts", args_command.args);
        },
        .wpt_manifest_cmd => |args_command| {
            return runWptManifestCommand(allocator, io, args_command.args);
        },
    }
}

fn runTestCommand(allocator: Allocator, io: std.Io, command: cli.TestCommand) !u8 {
    const discovered = try discovery.discoverTests(allocator, command.patterns);
    defer discovered.deinit(allocator);

    if (discovered.paths.len == 0) {
        reporter.printNoTests(command.patterns);
        return 1;
    }

    reporter.printDiscovered(discovered.paths.len);
    if (command.dry_run) {
        reporter.printDryRun(discovered.paths);
        return 0;
    }

    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);

    try args.appendSlice(allocator, &.{ "bun", "test" });
    for (discovered.paths) |path| {
        try args.append(allocator, path);
    }

    return runProcess(io, args.items);
}

fn runSimpleScript(allocator: Allocator, io: std.Io, script_path: []const u8, extra_args: []const []const u8) !u8 {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);

    try args.appendSlice(allocator, &.{ "bun", "run", script_path });
    try args.appendSlice(allocator, extra_args);

    return runProcess(io, args.items);
}

fn runWptManifestCommand(allocator: Allocator, io: std.Io, raw_args: []const []const u8) !u8 {
    var mapped_args: std.ArrayList([]const u8) = .empty;
    defer mapped_args.deinit(allocator);

    var index: usize = 0;
    while (index < raw_args.len) {
        const current = raw_args[index];
        if (std.mem.eql(u8, current, "--out")) {
            if (index + 1 >= raw_args.len) {
                return error.MissingValueAfterOut;
            }

            try mapped_args.append(allocator, "--out-manifest");
            try mapped_args.append(allocator, raw_args[index + 1]);
            index += 2;
            continue;
        }

        try mapped_args.append(allocator, current);
        index += 1;
    }

    return runSimpleScript(allocator, io, "scripts/generate-wpt-manifest.ts", mapped_args.items);
}

fn runProcess(io: std.Io, argv: []const []const u8) !u8 {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("Required command not found: {s}", .{argv[0]});
            return 127;
        },
        else => return err,
    };

    const term = try child.wait(io);
    return switch (term) {
        .exited => |code| code,
        .signal => {
            std.log.err("Child process terminated by signal.", .{});
            return 1;
        },
        .stopped => {
            std.log.err("Child process stopped unexpectedly.", .{});
            return 1;
        },
        .unknown => {
            std.log.err("Child process ended unexpectedly.", .{});
            return 1;
        },
    };
}

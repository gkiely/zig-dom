const std = @import("std");
const cli = @import("cli.zig");
const discovery = @import("discovery.zig");
const execution = @import("execution.zig");
const reporter = @import("reporter.zig");
const transform = @import("transform.zig");

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
    const discovered = try discovery.discoverTests(allocator, io, command.patterns);
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

    const prepared = try transform.runUpfront(allocator, io, discovered.paths);
    defer prepared.deinit(allocator);

    if (prepared.transformed_count > 0) {
        reporter.printTransformed(prepared.transformed_count);
    }

    var summary = try execution.runFiles(allocator, io, prepared.paths);
    defer summary.deinit(allocator);

    for (summary.files) |file_result| {
        reporter.printFileResult(
            file_result.path,
            file_result.passed,
            file_result.failed,
            file_result.skipped,
            file_result.timed_out,
            file_result.collection_errors,
        );

        if (file_result.collection_report) |collection_report| {
            reporter.printCollectionReport(file_result.path, collection_report);
        }

        if (file_result.failure_report) |failure_report| {
            reporter.printFailureReport(file_result.path, failure_report);
        }
    }

    reporter.printSummary(
        summary.total_passed,
        summary.total_failed,
        summary.total_skipped,
        summary.total_timed_out,
        summary.total_collection_errors,
    );

    return if (summary.hasFailures()) 1 else 0;
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

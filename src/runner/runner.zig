const std = @import("std");
const cli = @import("cli.zig");
const discovery = @import("discovery.zig");
const execution = @import("execution.zig");
const reporter = @import("reporter.zig");
const transform = @import("transform.zig");

const Allocator = std.mem.Allocator;
const default_test_patterns = [_][]const u8{"tests"};

pub const RunnerError = error{
    MissingValueAfterOut,
    MissingValueAfterSetup,
};

const ParsedTestArgs = struct {
    dry_run: bool,
    patterns: []const []const u8,
    setup_files: []const []const u8,

    fn deinit(self: ParsedTestArgs, allocator: Allocator) void {
        allocator.free(self.patterns);
        allocator.free(self.setup_files);
    }
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
    const parsed = try parseTestArgs(allocator, command.args);
    defer parsed.deinit(allocator);

    const discovered = try discovery.discoverTests(allocator, io, parsed.patterns);
    defer discovered.deinit(allocator);

    if (discovered.paths.len == 0) {
        reporter.printNoTests(parsed.patterns);
        return 1;
    }

    reporter.printDiscovered(discovered.paths.len);
    if (parsed.dry_run) {
        reporter.printDryRun(discovered.paths);
        return 0;
    }

    const prepared = try transform.runUpfront(allocator, io, discovered.paths);
    defer prepared.deinit(allocator);

    if (prepared.transformed_count > 0) {
        reporter.printTransformed(prepared.transformed_count);
    }

    var summary = try execution.runFiles(allocator, io, prepared.paths, parsed.setup_files);
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

fn parseTestArgs(allocator: Allocator, raw_args: []const []const u8) !ParsedTestArgs {
    var patterns: std.ArrayList([]const u8) = .empty;
    errdefer patterns.deinit(allocator);

    var setup_files: std.ArrayList([]const u8) = .empty;
    errdefer setup_files.deinit(allocator);

    var dry_run = false;
    var index: usize = 0;
    while (index < raw_args.len) {
        const current = raw_args[index];

        if (std.mem.eql(u8, current, "--dry-run")) {
            dry_run = true;
            index += 1;
            continue;
        }

        if (std.mem.eql(u8, current, "--setup")) {
            if (index + 1 >= raw_args.len) {
                return error.MissingValueAfterSetup;
            }

            try setup_files.append(allocator, raw_args[index + 1]);
            index += 2;
            continue;
        }

        try patterns.append(allocator, current);
        index += 1;
    }

    if (patterns.items.len == 0) {
        try patterns.appendSlice(allocator, default_test_patterns[0..]);
    }

    const owned_patterns = try patterns.toOwnedSlice(allocator);
    errdefer allocator.free(owned_patterns);

    const owned_setup_files = try setup_files.toOwnedSlice(allocator);

    return .{
        .dry_run = dry_run,
        .patterns = owned_patterns,
        .setup_files = owned_setup_files,
    };
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

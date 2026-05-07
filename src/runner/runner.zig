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
    MissingValueAfterRoot,
};

const ParsedTestArgs = struct {
    dry_run: bool,
    patterns: []const []const u8,
    setup_files: []const []const u8,
    root_dir: []const u8,
    has_root: bool,

    fn deinit(self: ParsedTestArgs, allocator: Allocator) void {
        allocator.free(self.patterns);
        allocator.free(self.setup_files);
        allocator.free(self.root_dir);
    }
};

const max_bunfig_bytes = 2 * 1024 * 1024;

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

    const resolved_patterns = try resolveTestPatterns(allocator, io, parsed.root_dir, parsed.patterns);
    defer freeOwnedStringSlice(allocator, resolved_patterns);

    const resolved_setup_files = try resolveSetupFiles(allocator, io, parsed.root_dir, parsed.setup_files, parsed.has_root);
    defer freeOwnedStringSlice(allocator, resolved_setup_files);

    const discovered = try discovery.discoverTests(allocator, io, resolved_patterns);
    defer discovered.deinit(allocator);

    if (discovered.paths.len == 0) {
        reporter.printNoTests(resolved_patterns);
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

    var summary = try execution.runFiles(allocator, io, prepared.paths, resolved_setup_files);
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
    var root_dir: []const u8 = ".";
    var has_root = false;
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

        if (std.mem.eql(u8, current, "--root")) {
            if (index + 1 >= raw_args.len) {
                return error.MissingValueAfterRoot;
            }

            root_dir = raw_args[index + 1];
            has_root = true;
            index += 2;
            continue;
        }

        try patterns.append(allocator, current);
        index += 1;
    }

    const owned_patterns = try patterns.toOwnedSlice(allocator);
    errdefer allocator.free(owned_patterns);

    const owned_setup_files = try setup_files.toOwnedSlice(allocator);
    errdefer allocator.free(owned_setup_files);

    const owned_root_dir = try allocator.dupe(u8, root_dir);

    return .{
        .dry_run = dry_run,
        .patterns = owned_patterns,
        .setup_files = owned_setup_files,
        .root_dir = owned_root_dir,
        .has_root = has_root,
    };
}

fn resolveTestPatterns(
    allocator: Allocator,
    io: std.Io,
    root_dir: []const u8,
    patterns: []const []const u8,
) ![]const []u8 {
    var resolved: std.ArrayList([]u8) = .empty;
    errdefer {
        for (resolved.items) |item| {
            allocator.free(item);
        }
        resolved.deinit(allocator);
    }

    if (patterns.len == 0) {
        const default_pattern = try resolvePathAgainstRoot(allocator, io, root_dir, default_test_patterns[0], false);
        try resolved.append(allocator, default_pattern);
        return resolved.toOwnedSlice(allocator);
    }

    for (patterns) |pattern| {
        const resolved_pattern = try resolvePathAgainstRoot(allocator, io, root_dir, pattern, true);
        try resolved.append(allocator, resolved_pattern);
    }

    return resolved.toOwnedSlice(allocator);
}

fn resolveSetupFiles(
    allocator: Allocator,
    io: std.Io,
    root_dir: []const u8,
    explicit_setup_files: []const []const u8,
    include_bunfig_preloads: bool,
) ![]const []u8 {
    var resolved: std.ArrayList([]u8) = .empty;
    errdefer {
        for (resolved.items) |item| {
            allocator.free(item);
        }
        resolved.deinit(allocator);
    }

    if (include_bunfig_preloads) {
        const bunfig_preloads = try discoverBunfigPreloads(allocator, io, root_dir);
        defer freeOwnedStringSlice(allocator, bunfig_preloads);

        for (bunfig_preloads) |preload| {
            try resolved.append(allocator, try allocator.dupe(u8, preload));
        }
    }

    for (explicit_setup_files) |setup_file| {
        const resolved_setup = try resolvePathAgainstRoot(allocator, io, root_dir, setup_file, true);
        try resolved.append(allocator, resolved_setup);
    }

    return resolved.toOwnedSlice(allocator);
}

fn discoverBunfigPreloads(allocator: Allocator, io: std.Io, root_dir: []const u8) ![]const []u8 {
    const bunfig_path = try joinRootPath(allocator, root_dir, "bunfig.toml");
    defer allocator.free(bunfig_path);

    const stat = std.Io.Dir.cwd().statFile(io, bunfig_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc([]u8, 0),
        else => return err,
    };
    if (stat.kind != .file) {
        return allocator.alloc([]u8, 0);
    }

    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        bunfig_path,
        allocator,
        .limited(max_bunfig_bytes),
    );
    defer allocator.free(source);

    const raw_entries = try parseBunfigPreloadEntries(allocator, source);
    defer freeOwnedStringSlice(allocator, raw_entries);

    var resolved: std.ArrayList([]u8) = .empty;
    errdefer {
        for (resolved.items) |item| {
            allocator.free(item);
        }
        resolved.deinit(allocator);
    }

    for (raw_entries) |entry| {
        try resolved.append(allocator, try joinRootPath(allocator, root_dir, entry));
    }

    return resolved.toOwnedSlice(allocator);
}

fn parseBunfigPreloadEntries(allocator: Allocator, source: []const u8) ![]const []u8 {
    const section = findTomlSection(source, "test") orelse return allocator.alloc([]u8, 0);
    const preload_value = findTomlKeyValue(section, "preload") orelse return allocator.alloc([]u8, 0);

    const trimmed = std.mem.trim(u8, preload_value, " \t\r\n");
    if (trimmed.len == 0) {
        return allocator.alloc([]u8, 0);
    }

    if (trimmed[0] == '"') {
        const parsed = try parseTomlString(allocator, trimmed, 0);
        errdefer allocator.free(parsed.value);

        var single: std.ArrayList([]u8) = .empty;
        errdefer single.deinit(allocator);
        try single.append(allocator, parsed.value);
        return single.toOwnedSlice(allocator);
    }

    if (trimmed[0] != '[') {
        return allocator.alloc([]u8, 0);
    }

    var values: std.ArrayList([]u8) = .empty;
    errdefer {
        for (values.items) |value| {
            allocator.free(value);
        }
        values.deinit(allocator);
    }

    var index: usize = 1;
    while (index < trimmed.len) {
        skipTomlValueTrivia(trimmed, &index);
        if (index >= trimmed.len) {
            break;
        }

        if (trimmed[index] == ']') {
            break;
        }

        if (trimmed[index] == ',') {
            index += 1;
            continue;
        }

        if (trimmed[index] != '"') {
            index += 1;
            continue;
        }

        const parsed = try parseTomlString(allocator, trimmed, index);
        index = parsed.next_index;
        try values.append(allocator, parsed.value);
    }

    return values.toOwnedSlice(allocator);
}

const ParsedTomlString = struct {
    value: []u8,
    next_index: usize,
};

fn parseTomlString(allocator: Allocator, source: []const u8, start_index: usize) !ParsedTomlString {
    if (start_index >= source.len or source[start_index] != '"') {
        return error.InvalidTomlString;
    }

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var index = start_index + 1;
    while (index < source.len) {
        const ch = source[index];
        if (ch == '"') {
            return .{
                .value = try output.toOwnedSlice(allocator),
                .next_index = index + 1,
            };
        }

        if (ch == '\\') {
            if (index + 1 >= source.len) {
                return error.InvalidTomlString;
            }

            const escaped = source[index + 1];
            const decoded = switch (escaped) {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => escaped,
            };
            try output.append(allocator, decoded);
            index += 2;
            continue;
        }

        try output.append(allocator, ch);
        index += 1;
    }

    return error.InvalidTomlString;
}

fn skipTomlValueTrivia(source: []const u8, index: *usize) void {
    while (index.* < source.len) {
        const ch = source[index.*];
        if (std.ascii.isWhitespace(ch) or ch == ',') {
            index.* += 1;
            continue;
        }

        if (ch == '#') {
            while (index.* < source.len and source[index.*] != '\n') {
                index.* += 1;
            }
            continue;
        }

        break;
    }
}

fn findTomlSection(source: []const u8, section_name: []const u8) ?[]const u8 {
    var index: usize = 0;
    var in_target = false;
    var section_start: usize = 0;

    while (index < source.len) {
        const line_start = index;
        while (index < source.len and source[index] != '\n') {
            index += 1;
        }
        const line_end = index;
        if (index < source.len) {
            index += 1;
        }

        const line = std.mem.trim(u8, source[line_start..line_end], " \t\r");
        if (line.len == 0 or line[0] == '#') {
            continue;
        }

        if (line[0] == '[' and line[line.len - 1] == ']') {
            if (in_target) {
                return source[section_start..line_start];
            }

            const name = std.mem.trim(u8, line[1 .. line.len - 1], " \t\r");
            if (std.mem.eql(u8, name, section_name)) {
                in_target = true;
                section_start = if (index <= source.len) index else line_end;
            }
        }
    }

    if (in_target) {
        return source[section_start..source.len];
    }

    return null;
}

fn findTomlKeyValue(section: []const u8, key: []const u8) ?[]const u8 {
    var index: usize = 0;
    while (index < section.len) {
        const line_start = index;
        while (index < section.len and section[index] != '\n') {
            index += 1;
        }
        const line_end = index;
        if (index < section.len) {
            index += 1;
        }

        const line = std.mem.trim(u8, section[line_start..line_end], " \t\r");
        if (line.len == 0 or line[0] == '#') {
            continue;
        }

        const eq_index = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const line_key = std.mem.trim(u8, line[0..eq_index], " \t\r");
        if (!std.mem.eql(u8, line_key, key)) {
            continue;
        }

        var value_end = line_end;
        const initial_value = std.mem.trim(u8, line[eq_index + 1 ..], " \t\r");
        if (initial_value.len > 0 and initial_value[0] == '[' and std.mem.indexOfScalar(u8, initial_value, ']') == null) {
            var depth: usize = 1;
            var seek = index;
            while (seek < section.len and depth > 0) {
                const ch = section[seek];
                if (ch == '"') {
                    seek += 1;
                    while (seek < section.len) {
                        if (section[seek] == '\\') {
                            seek += 2;
                            continue;
                        }
                        if (section[seek] == '"') {
                            seek += 1;
                            break;
                        }
                        seek += 1;
                    }
                    continue;
                }

                if (ch == '[') {
                    depth += 1;
                } else if (ch == ']') {
                    depth -= 1;
                }
                seek += 1;
            }

            value_end = seek;
        }

        return section[line_start + eq_index + 1 .. value_end];
    }

    return null;
}

fn resolvePathAgainstRoot(
    allocator: Allocator,
    io: std.Io,
    root_dir: []const u8,
    path: []const u8,
    prefer_existing_path: bool,
) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        return allocator.dupe(u8, path);
    }

    if (prefer_existing_path and pathExists(io, path)) {
        return allocator.dupe(u8, path);
    }

    return joinRootPath(allocator, root_dir, path);
}

fn joinRootPath(allocator: Allocator, root_dir: []const u8, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        return allocator.dupe(u8, path);
    }

    if (std.mem.eql(u8, root_dir, ".") or root_dir.len == 0) {
        return allocator.dupe(u8, path);
    }

    return std.fs.path.resolve(allocator, &.{ root_dir, path });
}

fn pathExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

fn freeOwnedStringSlice(allocator: Allocator, values: []const []u8) void {
    for (values) |value| {
        allocator.free(value);
    }
    allocator.free(values);
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

test "parseTestArgs supports --root and --setup" {
    const allocator = std.testing.allocator;

    const parsed = try parseTestArgs(allocator, &.{ "--root", "../app", "--setup", "setup.ts", "tests/runner" });
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.patterns.len == 1);
    try std.testing.expect(std.mem.eql(u8, parsed.patterns[0], "tests/runner"));
    try std.testing.expect(parsed.setup_files.len == 1);
    try std.testing.expect(std.mem.eql(u8, parsed.setup_files[0], "setup.ts"));
    try std.testing.expect(std.mem.eql(u8, parsed.root_dir, "../app"));
    try std.testing.expect(parsed.has_root);
}

test "parseBunfigPreloadEntries reads test preload arrays" {
    const allocator = std.testing.allocator;
    const source =
        \\[test]
        \\preload = ["./setup-a.ts", "./setup-b.ts"]
        \\ 
        \\[install]
        \\cache = true
    ;

    const preloads = try parseBunfigPreloadEntries(allocator, source);
    defer freeOwnedStringSlice(allocator, preloads);

    try std.testing.expect(preloads.len == 2);
    try std.testing.expect(std.mem.eql(u8, preloads[0], "./setup-a.ts"));
    try std.testing.expect(std.mem.eql(u8, preloads[1], "./setup-b.ts"));
}

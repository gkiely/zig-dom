const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const build_info = buildInfoOptions(b);
    const quickjs_dep = b.dependency("quickjs_ng", .{
        .target = target,
        .optimize = optimize,
    });
    const quickjs_module = quickjs_dep.module("quickjs");
    const quickjs_lib = quickjs_dep.artifact("quickjs-ng");
    const yuku_util_module = b.createModule(.{
        .root_source_file = b.path("vendor/yuku/src/util/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const yuku_parser_module = b.createModule(.{
        .root_source_file = b.path("vendor/yuku/src/parser/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    yuku_parser_module.addImport("util", yuku_util_module);

    const module = b.createModule(.{
        .root_source_file = b.path("src/dom/dom.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zig_dom",
        .root_module = module,
    });

    b.installArtifact(lib);

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_module.addImport("quickjs", quickjs_module);
    exe_module.addImport("yuku_parser", yuku_parser_module);
    exe_module.addOptions("build_info", build_info);

    const exe = b.addExecutable(.{
        .name = "zig-dom",
        .root_module = exe_module,
    });
    exe.root_module.linkLibrary(quickjs_lib);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run zig-dom CLI");
    run_step.dependOn(&run_cmd.step);

    const main_tests_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    main_tests_module.addImport("quickjs", quickjs_module);
    main_tests_module.addImport("yuku_parser", yuku_parser_module);
    main_tests_module.addOptions("build_info", build_info);

    const main_tests = b.addTest(.{
        .root_module = main_tests_module,
    });
    main_tests.root_module.linkLibrary(quickjs_lib);

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run zig-dom Zig unit tests");
    test_step.dependOn(&run_main_tests.step);

    const native_step = b.step("native", "Build zig-dom shared library");
    native_step.dependOn(&lib.step);
}

fn buildInfoOptions(b: *std.Build) *std.Build.Step.Options {
    const options = b.addOptions();
    options.addOption([]const u8, "version", packageVersion(b));
    options.addOption([]const u8, "commit_sha", commitSha(b));
    return options;
}

fn packageVersion(b: *std.Build) []const u8 {
    const source = std.Io.Dir.cwd().readFileAlloc(b.graph.io, "package.json", b.allocator, .limited(512 * 1024)) catch |err| {
        std.process.fatal("failed to read package.json: {s}", .{@errorName(err)});
    };
    defer b.allocator.free(source);

    var parsed = std.json.parseFromSlice(std.json.Value, b.allocator, source, .{}) catch |err| {
        std.process.fatal("failed to parse package.json: {s}", .{@errorName(err)});
    };
    defer parsed.deinit();

    const version_value = parsed.value.object.get("version") orelse {
        std.process.fatal("package.json is missing version", .{});
    };
    return switch (version_value) {
        .string => |version| b.dupe(version),
        else => std.process.fatal("package.json version must be a string", .{}),
    };
}

fn commitSha(b: *std.Build) []const u8 {
    const raw = b.run(&.{ "git", "rev-parse", "--short", "HEAD" });
    return b.dupe(std.mem.trim(u8, raw, " \n\r\t"));
}

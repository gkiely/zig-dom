const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const quickjs_dep = b.dependency("quickjs_ng", .{
        .target = target,
        .optimize = optimize,
    });
    const quickjs_module = quickjs_dep.module("quickjs");
    const quickjs_lib = quickjs_dep.artifact("quickjs-ng");

    const module = b.createModule(.{
        .root_source_file = b.path("src/zig_dom.zig"),
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

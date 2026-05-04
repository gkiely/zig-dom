const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const native_step = b.step("native", "Build zig-dom shared library");
    native_step.dependOn(&lib.step);
}

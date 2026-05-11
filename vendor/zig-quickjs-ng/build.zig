const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // C headers
    const c = translateC(b, target, optimize);
    const c_mod = c.addModule("quickjs_c");

    // Library
    const lib = try library(b, target, optimize);
    b.installArtifact(lib);

    // Zig module
    const mod = b.addModule("quickjs", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{
            .name = "quickjs_c",
            .module = c_mod,
        }},
    });

    // Tests
    const tests = b.addTest(.{
        .root_module = mod,
        // Compiler crash without this.
        .use_llvm = true,
    });
    tests.root_module.linkLibrary(lib);
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}

pub fn translateC(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.TranslateC {
    const upstream = b.dependency("quickjs", .{});

    const translate = b.addTranslateC(.{
        .root_source_file = upstream.path("quickjs.h"),
        .target = target,
        .optimize = optimize,
    });

    translate.addIncludePath(upstream.path(""));
    return translate;
}

pub fn library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Step.Compile {
    const upstream = b.dependency("quickjs", .{});
    const quickjs_patched = patchedQuickjsSource(b, upstream);

    const lib = b.addLibrary(.{
        .name = "quickjs-ng",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    lib.root_module.link_libc = true;

    lib.root_module.addIncludePath(upstream.path(""));
    lib.installHeader(
        upstream.path("quickjs.h"),
        "quickjs.h",
    );

    var flags: std.ArrayList([]const u8) = .empty;
    try flags.appendSlice(b.allocator, &.{
        "-D_GNU_SOURCE",
        "-DNDEBUG",
        "-funsigned-char",
        "-fno-sanitize=undefined",
        "-fno-sanitize-trap=undefined",
        "-fvisibility=hidden",
    });
    lib.root_module.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "dtoa.c",
            "libregexp.c",
            "libunicode.c",
        },
        .flags = flags.items,
    });
    lib.root_module.addCSourceFile(.{
        .file = quickjs_patched,
        .flags = flags.items,
    });

    return lib;
}

fn patchedQuickjsSource(b: *std.Build, upstream: *std.Build.Dependency) std.Build.LazyPath {
    const patch_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\python3 - "$1" "$2" <<'PY'
        \\import pathlib
        \\import sys
        \\
        \\source_path = pathlib.Path(sys.argv[1])
        \\output_path = pathlib.Path(sys.argv[2])
        \\src = source_path.read_text()
        \\
        \\if "#define JS_PROP_INITIAL_SIZE 2" not in src:
        \\    raise SystemExit("quickjs patch failed: JS_PROP_INITIAL_SIZE marker not found")
        \\src = src.replace("#define JS_PROP_INITIAL_SIZE 2", "#define JS_PROP_INITIAL_SIZE 8", 1)
        \\
        \\apply_line = "    tab = build_arg_list(ctx, &len, array_arg);"
        \\if apply_line not in src:
        \\    raise SystemExit("quickjs patch failed: js_function_apply call marker not found")
        \\src = src.replace(
        \\    apply_line,
        \\    """    /* Fast path for packed array/arguments values: avoid build_arg_list()
        \\       heap allocation/copy in common Function.apply() calls. */
        \\    if (JS_VALUE_GET_TAG(array_arg) == JS_TAG_OBJECT &&
        \\        ((JS_VALUE_GET_OBJ(array_arg)->class_id == JS_CLASS_ARRAY ||
        \\          JS_VALUE_GET_OBJ(array_arg)->class_id == JS_CLASS_ARGUMENTS) &&
        \\         JS_VALUE_GET_OBJ(array_arg)->fast_array)) {
        \\        len = JS_VALUE_GET_OBJ(array_arg)->u.array.count;
        \\        if (magic & 1) {
        \\            return JS_CallConstructor2(ctx, this_val, this_arg, len,
        \\                                       vc(JS_VALUE_GET_OBJ(array_arg)->u.array.u.values));
        \\        } else {
        \\            return JS_Call(ctx, this_val, this_arg, len,
        \\                           vc(JS_VALUE_GET_OBJ(array_arg)->u.array.u.values));
        \\        }
        \\    }
        \\    tab = build_arg_list(ctx, &len, array_arg);""",
        \\    1,
        \\)
        \\
        \\output_path.write_text(src)
        \\PY
        ,
        "quickjs-patches",
    });
    patch_cmd.addFileArg(upstream.path("quickjs.c"));
    return patch_cmd.addOutputFileArg("quickjs_patched.c");
}

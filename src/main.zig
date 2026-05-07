const std = @import("std");
const cli = @import("runner/cli.zig");
const runner = @import("runner/runner.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const arena = init.arena.allocator();
    const raw_argv = try init.minimal.args.toSlice(arena);
    const argv = try arena.alloc([]const u8, raw_argv.len);
    for (raw_argv, 0..) |arg, index| {
        argv[index] = arg;
    }

    const command = cli.parse(argv[1..]) catch |err| {
        switch (err) {
            error.UnknownCommand => {
                if (argv.len > 1) {
                    std.debug.print("Unknown command: {s}\n\n", .{argv[1]});
                }
            },
        }

        cli.printHelp();
        std.process.exit(2);
    };

    const exit_code = runner.run(allocator, init.io, command) catch |err| {
        std.debug.print("Runner failed: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

test {
    _ = @import("runner/cli.zig");
    _ = @import("runner/discovery.zig");
    _ = @import("runner/runner.zig");
    _ = @import("runtime.zig");
    _ = @import("quickjs_ng.zig");
}

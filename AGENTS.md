Be brief.

Code with zig, do not inline JS, do not add inline JavaScript shims or generated JS source strings. Prefer native Zig implementations exposed through QuickJS bindings. DOM behavior should live in Zig-backed helpers like `jsRangeToString`, not in injected JavaScript patches.

Do not add library specific code to fix issues, update our implementation.

Use `-Doptimize=Debug` when fixing broken individual tests, it rebuilds faster. Use` -Doptimize=ReleaseFast` for perf testing or when you need to run multiple tests, it runs tests faster.

Use `gtimeout` for timeout handling in scripts.

Don't do bytecode caching to disk, avoid any type of cache to disk.

If you made a change that's not viable and the build worked before you made the change, you don't need to rebuild, just revert and proceed.

## Failed perf experiments: see failed-experiments.md

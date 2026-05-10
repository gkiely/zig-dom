Be brief.

Do not add inline JavaScript shims or generated JS source strings as compatibility fixes. The built-in module shims in `src/runner/execution.zig` are legacy exceptions, not a pattern to extend.

Prefer native Zig implementations exposed through QuickJS bindings. DOM behavior should live in Zig-backed helpers like `jsRangeToString`, not in injected JavaScript patches.

Do not add library specific code to fix issues, update our implementation.

Use `-Doptimize=Debug` when fixing broken individual tests, it rebuilds faster. Use` -Doptimize=ReleaseFast` for perf testing or when you need to run multiple tests, it runs tests faster.

Use `gtimeout` for timeout handling in scripts.

Don't do bytecode caching to disk, avoid any type of cache to disk.

If you made a change that's not viable and the build worked before you made the change, you don't need to rebuild, just revert and proceed.

## Things that had no meaningful affect on perf:
- Making the interval scaling smaller (causes breakage)
- QuickJS Compile flags like `-flto` and `-O3`
- .backtrace_barrier = true
- Production React is not viable here: both Bun and zig-dom fail the test file under NODE_ENV=production
- zero-timeout job shortcut
- GC-after-test

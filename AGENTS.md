Be brief.

Do not add inline JavaScript shims or generated JS source strings as compatibility fixes. The built-in module shims in `src/runner/execution.zig` are legacy exceptions, not a pattern to extend.

Prefer native Zig implementations exposed through QuickJS bindings. DOM behavior should live in Zig-backed helpers like `jsRangeToString`, not in injected JavaScript patches.

Do not add library specific code to fix issues, update our implementation.

Use `-Doptimize=Debug` when fixing broken tests, it rebuilds faster. Use` -Doptimize=ReleaseFast` for perf testing.

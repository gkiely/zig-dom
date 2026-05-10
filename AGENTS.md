Be brief.

Do not add inline JavaScript shims or generated JS source strings as compatibility fixes. The built-in module shims in `src/runner/execution.zig` are legacy exceptions, not a pattern to extend.

Prefer native Zig implementations exposed through QuickJS bindings. DOM behavior should live in Zig-backed helpers like `jsRangeToString`, not in injected JavaScript patches.

Do not add library specific code to fix issues, update our implementation.

Use `-Doptimize=Debug` when fixing broken individual tests, it rebuilds faster. Use` -Doptimize=ReleaseFast` for perf testing or when you need to run multiple tests, it runs tests faster.

Use `gtimeout` for timeout handling in scripts.

Don't do bytecode caching to disk, avoid any type of cache to disk.

If you made a change that's not viable and the build worked before you made the change, you don't need to rebuild, just revert and proceed.

## Failed experiments (had no meaningful affect on perf)
- Making the interval scaling smaller (causes breakage)
- QuickJS Compile flags like `-flto` and `-O3`
- .backtrace_barrier = true
- Production React is not viable here: both Bun and zig-dom fail the test file under NODE_ENV=production
- zero-timeout job shortcut
- GC-after-test
- changing `.format = .compact` to `.format = .pretty` (worse)
- queueMicrotask batching reduced pending job count but made Tree slower.
- Package-resolution caching reduced some source-cache lookups but made Tree module profile slower.
- Targeted `not.toBeInTheDocument()` timer draining cut one matcher hotspot but did not improve full Tree time.
- Raising QuickJS GC thresholds and enabling `ZIG_DOM_FAST_ALLOC` did not materially improve Tree time.
- Sharing built-in `expect` matchers through prototypes made Tree slower.
- Removing assertions from the repeated Tree menu open/close body did not materially improve the zig-dom/Bun gap.
- Running Tree with `NODE_ENV=production` is not viable: Bun's JSX dev transform expects `jsxDEV`, and zig-dom fails through React test-utils `act`.
- Adding an explicit `-O3` C flag to quickjs-ng did not improve Tree time.
- A temporary Bun-built Tree bundle was not runnable in zig-dom: ESM output placed external `bun:test` imports after emitted code, and CJS output failed on top-level await.
- A temporary esbuild Tree bundle was not runnable in zig-dom because the bundled module was about 19 MB and hit the current source-size limit before collection.
- Raising the source-size limit and hoisting the generated `bun:test` import still did not make the temporary esbuild Tree bundle runnable in zig-dom.
- Bypassing React Testing Library's eventWrapper/act made Tree faster but invalid: 37 Tree tests failed in both zig-dom and Bun.
- Forcing only `react-dom/client` to the production bundle was invalid: React dev/prod internals mismatched and Tree failed 66 tests in both zig-dom and Bun.
- Collapsing default re-export wrapper modules reduced Tree's module count slightly but made measured Tree time slower.
- Suppressing per-test pass-line output did not materially improve Tree time.
- Applying unused `export const` pruning to ordinary ESM `.js` modules broke Tree collection by pruning exports still needed through unseen access patterns.
- Modulo-based single-file test sharding was fast but invalid for Tree because it changed intra-file order enough to fail an order-sensitive test.

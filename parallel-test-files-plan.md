# Parallel Test Files Plan

## Goal

Run test files in parallel while keeping the current isolation boundary: one QuickJS runtime/context per test file.

## Scope

Parallelize files only. Do not run individual `test(...)` cases concurrently inside one file.

## Phase 1: CLI

Add:

```sh
zig-dom test --jobs <n>
```

Initial default should stay `1` to preserve current behavior. Parallel execution can be opt-in first:

```sh
zig-dom test --jobs 4 tests/runner
```

After parallel mode is stable, change the default to:

```text
min(cpu_count, discovered_file_count, 4)
```

Do not default straight to all cores at first. Each file run creates a QuickJS runtime/context, module loader, DOM state, and import graph work, so full core saturation may lose time to allocator contention, filesystem pressure, memory pressure, or shared native state.

Keep explicit overrides:

```sh
zig-dom test --jobs 1
zig-dom test --jobs 8
```

## Phase 2: Buffered Reporting

Workers must not write directly to shared stdout.

Change execution so each file run captures:

- file header
- passed test lines
- profile output
- failure/collection reports
- elapsed time
- `FileResult`

The main thread prints captured output in original discovery order.

## Phase 3: Worker Pool

Keep discovery and upfront transforms sequential.

Then dispatch prepared file paths through a bounded worker pool:

```text
prepared.paths -> workers -> indexed FileResult[] -> ordered reporting
```

Each job runs:

```text
execution.runSingleFile(...)
```

## Phase 4: Global State Audit

Parallel runtimes expose process-global mutable state. Audit and fix:

- `active_cjs_loader_state`
- host runner `active_runner`
- host mocks `active_mocks`
- platform timer globals
- native DOM global registries/counters
- any shared module-loader state

Prefer runtime-owned or thread-local state. Use locks only where ownership cannot be moved cleanly.

## Phase 5: Verification

First prove the new path is equivalent:

```sh
zig build test run -Doptimize=Debug --summary none -- test --jobs 1 tests/runner
```

Then test parallelism:

```sh
zig build test run -Doptimize=Debug --summary none -- test --jobs 2 tests/runner
```

Benchmark likely defaults before changing from `--jobs 1`:

```sh
zig build test run -Doptimize=Debug --summary none -- test --jobs 1 tests/runner
zig build test run -Doptimize=Debug --summary none -- test --jobs 2 tests/runner
zig build test run -Doptimize=Debug --summary none -- test --jobs 4 tests/runner
zig build test run -Doptimize=Debug --summary none -- test --jobs 8 tests/runner
```

If scaling is clean, use the capped automatic default. If `8` is meaningfully better on common machines, raise the cap from `4` to `8`.

Then run the normal gate:

```sh
bun run verify:fast
```

## Fallback

If in-process parallelism is blocked by shared global state, use process-level parallelism:

```text
parent runner -> spawn child zig-dom test <file> processes -> merge results
```

This is heavier, but gives hard isolation because every file gets a separate process.

## Recommendation

Implement in-process file-level parallelism first. Keep `--jobs 1` as the default until `--jobs 2+` is stable across the runner suite. After benchmarking, default to `min(cpu_count, discovered_file_count, 4)` unless the data supports a higher cap.

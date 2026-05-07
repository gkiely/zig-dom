# Plan: Zig Test Runner With A Built-In Zig DOM

## Goal

Rewrite `zig-dom` into a standalone test runner written in Zig with a built-in DOM also written in Zig.

The target product is not another DOM shim loaded by `bun test`. It is a CLI that can run JavaScript DOM tests itself:

```sh
zig build run -- test tests/**/*.test.js
zig build run -- wpt --manifest wpt/manifest/dom-core.json
```

The first version should run `.js`, `.ts`, `.jsx`, and `.tsx` tests plus a useful subset of DOM and WPT `testharness.js` tests. React Testing Library, coverage, snapshots, and full Jest compatibility are later milestones.

## Compatibility Todo (2026-05-06)

- Passing files:
  - `../youneedawiki/plugins/replaceLogs.test.ts`
  - `../youneedawiki/src/elements/PoweredBy/PoweredBy.test.tsx`
- Current first blocker:
  - `../youneedawiki/src/elements/Buttons/ViewInDrive.test.tsx` fails during collection with `module resolution failed`.
- Missing API / capability currently blocking next gate:
  - Bare external package resolution/shimming for ESM imports from `node_modules` (example: `@r2wc/react-to-web-component`, then likely additional package imports in the same dependency chain).
- Local fixture added for related runner support:
  - Setup/preload fixtures proving setup execution order and setup module loading path:
    - `tests/runner/setup-preload.test.ts`
    - `tests/runner/fixtures/setup/install-globals.ts`
    - `tests/runner/fixtures/setup/extend-expect.ts`
    - `tests/runner/fixtures/setup/shared.ts`

## Current Repo Facts

- The current package is a Bun-only JS wrapper over a Zig native library.
- Zig currently owns a basic DOM tree and handles in `src/zig_dom.zig`.
- JS currently owns the public `Window`, `Document`, `Node`, `Element`, event, collection, and compatibility classes under `js/wrappers`.
- WPT support already exists through TypeScript scripts:
  - `scripts/sync-wpt.ts`
  - `scripts/generate-wpt-manifest.ts`
  - `scripts/run-wpt-subset.ts`
  - `wpt/manifest/*.json`
  - `wpt/expected/*.json`
- The existing WPT runner injects lightweight `test`, `promise_test`, `async_test`, assertions, and DOM globals around `Window`.
- Keep the existing WPT manifests and expected-failure JSON format unless there is a clear reason to change them.

## Bun Test Runner Notes To Copy

Sources read:

- `https://github.com/oven-sh/bun/blob/main/src/cli/test_command.zig`
- `https://github.com/oven-sh/bun/blob/main/src/test_runner/bun_test.zig`
- `https://github.com/oven-sh/bun/blob/main/src/test_runner/Execution.zig`
- `https://github.com/oven-sh/bun/blob/main/src/test_runner/ScopeFunctions.zig`

Useful Bun architecture:

- CLI discovery and reporting live outside the core runner.
- Each file gets an active `BunTest` state object.
- Test registration is a collection phase. `describe`, `test`, and hooks append entries into a scope tree.
- Execution is a separate phase. Bun converts the collected scope tree into ordered execution groups and sequences.
- Hooks are normal execution entries, not special one-off calls.
- Results are represented as explicit enums: pending, pass, skip, todo, fail, timeout, assertion-count failure, etc.
- Sync callbacks, returned promises, and `done` callbacks all funnel into the same completion path.
- Timeouts are tracked per execution entry.
- Unhandled errors are classified as collection errors, handled test errors, or errors between tests.
- File isolation swaps the global object between files when enabled.
- Preload hooks are stored separately and reset when the isolated global is swapped.
- The reporter consumes normalized lifecycle events and writes terminal/JUnit output separately from execution.

Do not copy Bun's whole Jest compatibility surface. Copy the phase model and data ownership.

## Runtime Decision

A Zig test runner still needs a JavaScript engine.

Use `mitchellh/zig-quickjs-ng` for the MVP runtime:

- Repo: `https://github.com/mitchellh/zig-quickjs-ng`
- It provides Zig build integration and bindings for QuickJS-ng.
- It currently has no GitHub releases or tags. Pin a specific commit in `build.zig.zon`; do not track `main`.
- Verified upstream `HEAD` during planning: `eb1d44ce43fd64f8403c1a94fad242ebae04d1fb`.
- Its current `build.zig.zon` declares `minimum_zig_version = "0.14.0"`. This repo currently declares and runs Zig `0.16.0`, so the metadata does not obviously conflict, but the first implementation step must verify it with a real build.
- Treat it as the first backend, not the architecture. Keep the runtime boundary abstract so JavaScriptCore can be evaluated later if performance or compatibility requires it.

Add:

```text
src/runtime/
  runtime.zig        # engine-neutral interface
  quickjs_ng.zig     # adapter over mitchellh/zig-quickjs-ng
  value.zig          # JS value handles and conversions
```

The runtime API should support:

- Create/destroy VM.
- Create/destroy per-file global context.
- Evaluate module/script source with filename.
- Call JS functions.
- Resolve/reject promises or drain jobs.
- Install native classes/functions.
- Store opaque native pointers on JS objects.
- Capture exceptions and stack traces.

## Target Architecture

```text
src/
  main.zig
  runner/
    cli.zig
    discovery.zig
    transform.zig
    runner.zig
    collection.zig
    scope.zig
    order.zig
    execution.zig
    hooks.zig
    reporter.zig
    junit.zig
    expectations.zig
  runtime/
    runtime.zig
    quickjs_ng.zig
    value.zig
  dom/
    window.zig
    document.zig
    node.zig
    element.zig
    text.zig
    comment.zig
    fragment.zig
    document_type.zig
    attributes.zig
    collections.zig
    event_target.zig
    event.zig
    mutation.zig
    range.zig
    selector.zig
    parser.zig
    serializer.zig
    bindings.zig
  wpt/
    manifest.zig
    harness.zig
    html_loader.zig
    expectations.zig
```

The DOM should no longer require TypeScript wrappers for core behavior. JS-visible DOM constructors should be native classes installed by `dom/bindings.zig`.

## TypeScript And JSX Transform

Support these test file extensions from the start:

- `.test.js`, `.spec.js`, `_test_*.js`, `_spec_*.js`
- `.test.ts`, `.spec.ts`, `_test_*.ts`, `_spec_*.ts`
- `.test.jsx`, `.spec.jsx`, `_test_*.jsx`, `_spec_*.jsx`
- `.test.tsx`, `.spec.tsx`, `_test_*.tsx`, `_spec_*.tsx`

Use Bun only as a transform tool, not as the runtime:

- At the start of a test run, discover all test files.
- Split files into plain JavaScript and transform-needed files.
- For normal runs, upfront batch transform all `.ts`, `.tsx`, and `.jsx` files before collection or execution.
- If any transform fails, fail the run before executing tests.
- Prefer one Bun helper process per test run over one Bun process per file.
- The helper should use `Bun.Transpiler.transformSync()` for per-file transforms first.
- Cache transformed output by source path, loader, Bun version, transform options, and content hash or mtime+size.
- Execute only the resulting JavaScript in QuickJS-ng.

Initial transform scope:

- Strip TypeScript syntax.
- Convert JSX/TSX to plain JavaScript using the repo `tsconfig`/JSX settings where possible.
- Preserve filenames in runtime error reporting.
- Write transformed artifacts to a cache directory such as `.zig-dom-cache/transformed/`, or keep them in memory if the runner has a clean internal source-map story.

Do not use Bun for:

- Test scheduling.
- DOM globals.
- Assertions.
- Runtime execution.

Do not add lazy/on-demand transforms for the initial runner. Lazy transforms can be considered later for watch mode or very large suites, but they must still use the same cache and a persistent/batched Bun helper.

Use `Bun.build()` later only if import resolution/bundling becomes necessary. Start with per-file transforms so the runner keeps ownership of module loading and test collection.

## Runner Model

Implement the same core states as Bun:

```text
FileRunner.phase = collection | execution | done
```

Collection owns:

- Root describe scope.
- Active describe scope.
- Tests.
- `beforeAll`, `beforeEach`, `afterEach`, `afterAll`.
- `only`, `skip`, `todo`, `failing`.
- Optional line numbers.

Execution owns:

- Ordered groups.
- Sequences.
- Active entry.
- Timeout deadline.
- Result.
- Assertion counts.
- Retry/repeat counters later.

MVP APIs:

- `test(name, fn, options?)`
- `it(name, fn, options?)`
- `describe(name, fn)`
- `beforeAll(fn)`
- `beforeEach(fn)`
- `afterEach(fn)`
- `afterAll(fn)`
- `test.skip`
- `test.only`
- `describe.skip`
- `expect(value).toBe(value)`
- `expect(value).toEqual(value)` for primitives/arrays/plain objects
- `expect(value).toThrow()`

WPT APIs are separate and should not require Jest `expect`:

- `test(fn, name)`
- `promise_test(fn, name)`
- `async_test(fn?, name?)`
- `assert_true`
- `assert_false`
- `assert_equals`
- `assert_not_equals`
- `assert_throws_dom`
- `assert_array_equals`
- `assert_own_property`
- `assert_idl_attribute`

## DOM MVP

Implement enough DOM in Zig to run local smoke tests and the first WPT slice:

- `Window`
- `Document`
- `DocumentFragment`
- `DocumentType`
- `Node`
- `Element`
- `HTMLElement`
- `Text`
- `Comment`
- `EventTarget`
- `Event`
- `CustomEvent`
- `NodeList`
- `HTMLCollection`
- Attributes
- Tree mutation
- `textContent`
- `innerHTML` and `outerHTML` through the existing parser/serializer path
- `querySelector` and `querySelectorAll` with the current selector subset
- `document.createElement`
- `document.createTextNode`
- `document.createComment`
- `document.implementation.createDocumentType`

Preserve handle safety from the current Zig library, but remove the FFI-shaped API once native JS bindings exist.

## WPT Integration

Use `https://github.com/web-platform-tests/wpt` as the compliance source.

Keep WPT out of the repo by default. Continue syncing to `.wpt-cache/web-platform-tests`.

Required commands:

```sh
zig build test
zig build run -- test tests/smoke
zig build run -- wpt --manifest wpt/manifest/dom-core.json --expected wpt/expected/dom-core.json
zig build run -- wpt-sync
zig build run -- wpt-manifest --dir dom --out wpt/manifest/upstream-dom-smoke.json
```

WPT runner behavior:

- Load HTML fixtures.
- Parse static `<html>`, `<head>`, `<body>`, attributes, and doctype into the Zig DOM.
- Install WPT harness globals in the JS context.
- Evaluate `testharness.js` tests and referenced scripts.
- Support variants such as `?foo`.
- Record subtest results, not just file-level results.
- Compare results to expected-failure JSON.
- Fail only on unexpected failures and unexpected passes.
- Every expected failure must include `file`, `subtest`, `reason`, and `owner`.

Initial WPT scope:

1. Local tiny tests under `wpt/runner/tests`.
2. `wpt/manifest/dom-core.json`.
3. `selectors`.
4. `events`.
5. `parser-fragments`.
6. `forms`.
7. `custom-elements-shadow` only after custom elements and shadow DOM have real Zig ownership.

Skip for MVP:

- Reftests.
- WebDriver/testdriver tests.
- Layout/CSS visual assertions.
- Navigation/browsing-context isolation beyond simple iframes.
- Network fetching beyond local fixture loading.

## Downstream Compatibility Target

The native DOM pass is not complete just because local DOM smoke tests pass. The practical downstream target is running `../youneedawiki` DOM tests with this runner.

Add downstream compatibility in layers:

1. React 18 render smoke using `react` and `react-dom/client`.
2. Testing Library smoke using `@testing-library/react`.
3. Browser global shim pass for common app-test assumptions:
   - `HTMLElement`
   - `HTMLInputElement`
   - `SVGElement`
   - `DOMRect`
   - `getBoundingClientRect`
   - `getClientRects`
   - `getComputedStyle`
   - `matchMedia`
   - `ResizeObserver` stub if needed
   - `MutationObserver`
4. Form and event behavior required by React controlled inputs:
   - `input`
   - `change`
   - `click`
   - `focus`
   - `blur`
   - `value`
   - `checked`
   - `disabled`
5. Runner compatibility for app test setup:
   - setup/preload files
   - transformed TS/TSX imports
   - test globals
   - `expect` extensions or a documented subset

Do not edit `../youneedawiki` tests unless explicitly approved. Fix this runner and native DOM first.

Target command shape:

```sh
zig build run -- test ../youneedawiki/src/**/*.test.{ts,tsx}
```

If glob expansion is not implemented yet, support equivalent explicit file paths or a `--root ../youneedawiki` plus discovery mode.

## Milestones

### M1: Standalone CLI Skeleton

- Add `src/main.zig`.
- Parse commands: `test`, `wpt`, `wpt-sync`, `wpt-manifest`.
- Add file discovery for `.test.{js,ts,jsx,tsx}`, `.spec.{js,ts,jsx,tsx}`, `_test_*.{js,ts,jsx,tsx}`, and `_spec_*.{js,ts,jsx,tsx}`.
- Add TAP-like or Bun-like terminal summary.
- No DOM required yet.

Done when:

- `zig build run -- test tests/runner/basic.test.js` collects and runs sync tests.

### M2: Embedded JS Runtime

- Add `mitchellh/zig-quickjs-ng` to `build.zig.zon`, pinned to commit `eb1d44ce43fd64f8403c1a94fad242ebae04d1fb` unless a newer commit is deliberately selected and verified.
- Link its `quickjs-ng` artifact in `build.zig`.
- Add the `quickjs` Zig module import only to the runtime adapter.
- Add `src/runtime/quickjs_ng.zig` as the only module that imports `quickjs`.
- If `src/runtime/quickjs.zig` already exists from earlier agent work, rename or replace it with `quickjs_ng.zig` before wiring the dependency.
- Immediately run `zig build test` after adding the dependency and link step. Do not build runner behavior on top of the dependency until this passes.
- Evaluate JS files.
- Install `test`, `describe`, hooks, and basic `expect`.
- Drain promise jobs.
- Capture thrown errors and stack traces.

Done when:

- Sync tests, promise tests, and thrown failures report correctly.

### M3: Batched Bun Transform For TS/JSX

- Add `src/runner/transform.zig`.
- Add a Bun helper script or inline helper entrypoint that accepts a batch of files and loaders.
- Upfront transform every `.ts`, `.tsx`, and `.jsx` test file once at the start of the run, before test collection or execution.
- Report transform errors and stop before running any tests.
- Leave `.js` files unmodified.
- Cache transform outputs by input content and transform options.
- Feed transformed JavaScript into the QuickJS-ng runtime with original filenames preserved for errors.

Done when:

- `.test.ts`, `.test.jsx`, and `.test.tsx` runner smoke tests execute through QuickJS-ng.
- The transform stage invokes Bun once per run, not once per file.

### M4: Bun-Style Collection And Execution

- Implement scope tree.
- Implement order generation.
- Implement before/after hooks.
- Implement skip/only.
- Implement timeout handling.
- Split collection errors from test failures.

Done when:

- Nested describe/hook order matches Bun/Jest behavior for the local runner tests.

### M5: Native DOM Bindings

- Move `Window`, `Document`, `Node`, `Element`, `Text`, `Comment`, collections, and events into Zig-native JS bindings.
- Install DOM globals into each test file context.
- Reset DOM per file.
- Implement the broad native DOM pass in ordered slices:
  - core tree operations
  - collections
  - text/comment/character data
  - attributes and element basics
  - document creation APIs
  - parsing and serialization
  - selectors
  - events
  - forms and common HTML elements
  - window/document environment
  - MutationObserver and Range
  - custom elements and shadow DOM last

Done when:

- Local DOM tests pass without importing `js/wrappers`.

### M6: React, Testing Library, And YouNeedAWiki Compatibility

- Add native DOM smoke tests for React 18 rendering.
- Add native DOM smoke tests for `@testing-library/react`.
- Add browser-global shims needed by app tests: `SVGElement`, `DOMRect`, layout rect methods, `getComputedStyle`, `matchMedia`, and observer stubs where needed.
- Add runner support for setup/preload files if app tests require it.
- Add a downstream compatibility command or documented invocation for `../youneedawiki`.
- Run a tiny copied or explicitly selected subset first, then expand toward the real `../youneedawiki` DOM test command.

Done when:

- React smoke passes under this runner.
- Testing Library smoke passes under this runner.
- A named small subset of `../youneedawiki` DOM tests passes without modifying `../youneedawiki` tests.

### M7: WPT Harness In Zig

- Port the current TypeScript WPT harness into `src/wpt`.
- Keep the existing manifest and expected-failure JSON shape.
- Run local tiny WPT tests first.

Done when:

- `zig build run -- wpt --manifest wpt/manifest/dom-core.json --expected wpt/expected/dom-core.json` produces pass/fail/expected-fail/unexpected-pass counts.

### M8: Upstream WPT Smoke

- Port or replace `scripts/sync-wpt.ts` and `scripts/generate-wpt-manifest.ts`.
- Run a max-200 upstream DOM smoke manifest.
- Add expected failures with reasons.

Done when:

- Upstream DOM smoke has zero unexpected failures.

### M9: Deprecate Bun FFI Package Shape

- Decide whether `js/` remains as compatibility exports or moves to a separate package.
- Remove FFI-only APIs that are no longer used by the runner.
- Update README around the runner-first product.

Done when:

- The default development path is `zig build run -- test`, not `bun test`.

## Verification Contract

Keep feedback loops small:

```sh
zig build test
zig build run -- test tests/runner
zig build run -- test tests/dom
zig build run -- test tests/runner/native-dom-*.test.js
zig build run -- wpt --manifest wpt/manifest/dom-core.json --expected wpt/expected/dom-core.json
```

Downstream gates once M6 starts:

```sh
zig build run -- test tests/runner/react-*.test.{js,ts,tsx}
zig build run -- test tests/runner/testing-library-*.test.{js,ts,tsx}
zig build run -- test ../youneedawiki/<selected-dom-test-files>
```

Use the existing Bun package tests only as regression checks during migration:

```sh
bun run verify:fast
bun run verify:wpt:tiny
```

Do not make upstream WPT sync part of the fast path.

## Risks

- A test runner written in Zig still needs a JS engine. Do not start by writing an interpreter.
- QuickJS-ng may diverge from browser JavaScript behavior. Keep `runtime/runtime.zig` abstract.
- `mitchellh/zig-quickjs-ng` has no releases; pinned commits are required for reproducible builds.
- `mitchellh/zig-quickjs-ng` documents support for released Zig versions only. Re-check compatibility whenever this repo upgrades Zig.
- Bun transforms add a process/toolchain dependency. Batch transform once per run and cache outputs; do not spawn Bun per test file.
- Bun's transpiler does not typecheck. Treat TS support as syntax stripping/transformation only.
- WPT can drown the project. Keep curated manifests and expected failures.
- `../youneedawiki` compatibility will likely fail on browser globals, React event semantics, Testing Library visibility/role behavior, setup files, and TS/TSX module loading before it fails on pure DOM tree APIs.
- DOM bindings can become one-call-per-property overhead if modeled like FFI. Native JS classes should own opaque Zig pointers directly.
- Full Jest compatibility is not the MVP. Bun's runner design is useful because of its collection/execution split, not because every Jest feature must be cloned.

## Agent Start Here

1. Add the CLI skeleton and one runner smoke test.
2. Add `mitchellh/zig-quickjs-ng` embedding behind `src/runtime/runtime.zig`, pinned and verified with `zig build test`.
3. Add the batched Bun transform stage for `.ts`, `.tsx`, and `.jsx`.
4. Implement collection/execution with no DOM.
5. Port the current Zig DOM into native JS bindings.
6. Add React, Testing Library, and `../youneedawiki` compatibility gates.
7. Port the current WPT TypeScript harness into Zig.
8. Only then expand WPT coverage.

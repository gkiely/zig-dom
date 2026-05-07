# Agent Handoff Plan

## Goal

Broaden `zig-dom` runner support against real downstream usage and WPT while preserving the current fast iteration loop.

Primary tracks in order:

1. Keep runner performance stable, especially `Edit.test.tsx`.
2. Broaden `../youneedawiki` component support without editing downstream tests.
3. Add fast WPT iteration tooling.
4. Expand WPT coverage with expected-failure accounting.

Prefer generic fixes in the runner, native DOM, module loader, setup/plugin handling, mocks, and platform globals. Do not add package-specific hacks unless explicitly approved.

## Current Baseline

Known passing downstream files:

- `../youneedawiki/plugins/replaceLogs.test.ts`
- `../youneedawiki/src/elements/Buttons/Edit.test.tsx`
- `../youneedawiki/src/elements/PoweredBy/PoweredBy.test.tsx`
- `../youneedawiki/src/elements/Title/Title.test.tsx`
- `../youneedawiki/src/elements/Icon/Icon.test.tsx`
- `../youneedawiki/src/components/LastModified/LastModified.test.tsx`

Core local runner/DOM suites:

- `tests/runner/basic.test.js`
- `tests/runner/native-dom-*.test.js`
- `tests/runner/mock-spy.test.ts`
- `tests/runner/plugin-onload.test.ts`
- `tests/runner/testing-library-role.test.js`

WPT manifests already present:

- `wpt/manifest/dom-core.json`
- `wpt/manifest/events.json`
- `wpt/manifest/forms.json`
- `wpt/manifest/selectors.json`
- `wpt/manifest/parser-fragments.json`
- `wpt/manifest/custom-elements-shadow.json`
- `wpt/manifest/upstream-dom-smoke.json`
- `wpt/manifest/upstream-dom.json`

## Non-Negotiable Perf Guard

Run this at the end of every milestone and any substantial sub-chunk:

```sh
zig build -Doptimize=ReleaseFast --summary none
/usr/bin/time -p zig-out/bin/zig-dom test --root ../youneedawiki ../youneedawiki/src/elements/Buttons/Edit.test.tsx
```

Acceptance:

- Test passes: `pass=7 fail=0`.
- ReleaseFast timing should stay close to the current baseline:
  - cold-ish post-build: about `real 0.35-0.40`
  - immediate repeat: about `real 0.16-0.22`
- If it regresses, stop and find the commit/change before continuing.

The recent regression was caused by bypassing setup/onLoad pruning for `@mui/icons-material`. Keep plugin/onLoad ownership intact and preserve generic requested-export pruning.

## General Validation Commands

Use fast Debug builds for implementation loops:

```sh
zig build --summary none
zig build test --summary none
zig-out/bin/zig-dom test tests/runner/native-dom-*.test.js tests/runner/mock-spy.test.ts tests/runner/plugin-onload.test.ts tests/runner/testing-library-role.test.js
```

Use ReleaseFast only for the perf guard or performance comparisons.

Anything in test execution over 30s should be treated as a likely hang, async timeout, or Zig/runtime error. Build time can exceed 30s.

## Milestone 1: Lock In Current Perf Behavior

Tasks:

- Add a local perf regression script or documented command for the `Edit.test.tsx` guard.
- Ensure it is easy for future agents to run without including build time in the measured test runtime.
- Keep this as a manual guard unless there is a stable low-noise automated benchmark path.

Validation:

- Run the full perf guard above.
- Run local runner/DOM regression commands.

## Milestone 2: Broaden YouNeedAWiki Components

Work down `../youneedawiki` component tests by priority.

Suggested next targets:

- `../youneedawiki/src/components/Search/Search.test.tsx`
- `../youneedawiki/src/components/Page/Page.test.tsx`
- `../youneedawiki/src/components/Header/Header.test.tsx`
- `../youneedawiki/src/elements/OrderedListChecklistMacro.test.tsx`

Rules:

- Do not edit downstream tests.
- Do not hardcode downstream package names or component names in runner code.
- Prefer happy-dom/browser-compatible behavior where possible.
- If a test exceeds 30s, treat it as a likely hang/timeout and profile before behavior work.
- If a setup plugin should transform or skip a module, fix generic `Bun.plugin(...).onLoad` support instead of special-casing that module.

Likely areas:

- Testing Library role/name compatibility.
- User-event/fireEvent form behavior.
- Focus/selection/activeElement behavior.
- Fetch/Response/Headers completeness.
- Mock lifecycle and `mock.module` cleanup.
- URL/URLSearchParams semantics.
- QuickJS shutdown cleanup for leaked globals/cycles.
- Module loader/onLoad performance and correctness.

Validation after each fixed file:

```sh
zig build --summary none
zig-out/bin/zig-dom test --root ../youneedawiki <fixed-test-file>
```

Then run the mandatory `Edit.test.tsx` ReleaseFast perf guard.

## Milestone 3: Platform Globals

Fill browser/node compatibility gaps generically as they are exposed by `../youneedawiki`.

- `fetch`, `Request`, `Response`, `Headers`, `Blob`.
- `URL`, `URLSearchParams`.
- `Image`.
- `ResizeObserver`, `MutationObserver`, `matchMedia`.
- `localStorage`, `sessionStorage`.
- Minimal `node:*` shims only when needed by real dependency graphs.

Rules:

- Keep unsupported APIs explicit and diagnosable.
- Avoid fake network behavior unless the browser API shape requires a resolved/rejected promise.
- Downstream setup should be able to mock/spy on globals.

Validation:

```sh
zig-out/bin/zig-dom test tests/runner/native-dom-window-globals.test.js tests/runner/mock-spy.test.ts tests/runner/setup-preload.test.ts tests/runner/plugin-onload.test.ts
```

Then run the mandatory `Edit.test.tsx` ReleaseFast perf guard.

## Milestone 4: DOM Loading Configuration

The runner should not always pay DOM startup cost for plain non-DOM tests.

Target behavior:

- Default to installing DOM globals for `.jsx` and `.tsx` test files.
- Default to not installing DOM globals for plain `.js` and `.ts` tests unless needed by setup or config.
- Add a CLI/config flag to override this behavior.

Suggested flags:

```sh
zig-out/bin/zig-dom test --dom auto tests/runner/basic.test.ts
zig-out/bin/zig-dom test --dom always tests/runner/native-dom-smoke.test.js
zig-out/bin/zig-dom test --dom never tests/runner/basic.test.ts
```

Tasks:

- Add runner config plumbing for `dom = auto | always | never`.
- In `auto`, enable DOM for JSX/TSX files and for WPT.
- Make setup/preload behavior explicit: if setup expects DOM in a `.ts` suite, users can pass `--dom always`.
- Keep `zig-dom` builtin imports working even when global DOM auto-load is disabled, or fail with a clear message if the import requires DOM.
- Measure whether non-DOM `.ts` tests get faster with DOM disabled.

Validation:

```sh
zig build --summary none
zig-out/bin/zig-dom test --dom never tests/runner/basic.test.ts
zig-out/bin/zig-dom test --dom auto tests/runner/basic.test.tsx
zig-out/bin/zig-dom test --dom always tests/runner/native-dom-smoke.test.js
```

Then run the mandatory `Edit.test.tsx` ReleaseFast perf guard.

## Milestone 5: Fast WPT Iteration

Before expanding WPT coverage, make WPT debugging fast enough for normal development.

Tasks:

- Add a way to run one WPT file directly.
- Add a way to filter a manifest to one file or one small subset.
- Add tiny smoke manifests or filters for each area:
  - `dom-core-smoke`
  - `events-smoke`
  - `forms-smoke`
  - `selectors-smoke`
  - `parser-smoke`
- Improve WPT failure output so the default report shows:
  - file path
  - test name
  - first failing assertion
  - expected/actual when available
  - stack when available
- Keep full harness dumps behind an explicit debug flag.
- Add expected-failure tooling for selected manifests only, with clear reporting for:
  - newly passing tests
  - newly failing tests
  - still expected-failing tests

Target command shapes:

```sh
zig-out/bin/zig-dom wpt --file wpt/runner/tests/events-basic.any.ts
zig-out/bin/zig-dom wpt --manifest wpt/manifest/events.json --filter events-basic
zig-out/bin/zig-dom wpt --manifest wpt/manifest/fast-smoke.json --expected wpt/expected/fast-smoke.json
```

These flags/manifests are not all implemented yet. Implement them in this milestone before relying on them in later WPT work.

Acceptance:

- A single WPT file runs in Debug mode without requiring ReleaseFast.
- A small smoke manifest stays under the 30s iteration budget.
- Full upstream manifests are not required during normal fix/debug loops.

Validation:

```sh
zig build --summary none
zig-out/bin/zig-dom wpt --file wpt/runner/tests/events-basic.any.ts
zig-out/bin/zig-dom wpt --manifest wpt/manifest/fast-smoke.json --expected wpt/expected/fast-smoke.json
```

Then run the mandatory `Edit.test.tsx` ReleaseFast perf guard.

## Milestone 6: Expand WPT DOM Core

Start with the smallest manifests and keep expected failures explicit.

Recommended order:

1. `dom-core`
2. `events`
3. `forms`
4. `selectors`
5. `parser-fragments`

Commands:

```sh
zig-out/bin/zig-dom wpt --manifest wpt/manifest/dom-core.json --expected wpt/expected/dom-core.json
zig-out/bin/zig-dom wpt --manifest wpt/manifest/events.json --expected wpt/expected/events.json
zig-out/bin/zig-dom wpt --manifest wpt/manifest/forms.json --expected wpt/expected/forms.json
zig-out/bin/zig-dom wpt --manifest wpt/manifest/selectors.json --expected wpt/expected/selectors.json
zig-out/bin/zig-dom wpt --manifest wpt/manifest/parser-fragments.json --expected wpt/expected/parser-fragments.json
```

Rules:

- Add or update expected failures only when the failure is understood.
- Prefer implementing missing standards behavior over widening expectations.
- Keep each WPT slice small enough to debug quickly.
- Add focused `tests/runner/native-dom-*.test.js` regressions for every WPT behavior fixed.

Run the mandatory `Edit.test.tsx` ReleaseFast perf guard after each WPT slice.

## Milestone 7: Events And Forms Depth

Expand coverage for:

- `addEventListener` options: capture, once, passive.
- `stopPropagation`, `stopImmediatePropagation`, `preventDefault`.
- Event target/currentTarget/eventPhase ordering.
- Input, change, submit, click defaults.
- Form ownership, `form.elements`, disabled controls, labels.
- Text selection APIs needed by user-event.

Validation:

```sh
zig-out/bin/zig-dom test tests/runner/native-dom-events.test.js tests/runner/native-dom-forms-elements.test.js
zig-out/bin/zig-dom wpt --manifest wpt/manifest/events.json --expected wpt/expected/events.json
zig-out/bin/zig-dom wpt --manifest wpt/manifest/forms.json --expected wpt/expected/forms.json
```

Then run the mandatory `Edit.test.tsx` ReleaseFast perf guard.

## Milestone 8: Selectors, Parsing, Serialization

Expand support for:

- Common selector combinations used by Testing Library and WPT.
- Attribute selectors and simple negation without falling back to slow paths unnecessarily.
- `matches`, `closest`, `querySelector`, `querySelectorAll` consistency.
- `innerHTML`, `outerHTML`, `insertAdjacentHTML`, text/entity serialization.
- Fragment parsing.

Validation:

```sh
zig-out/bin/zig-dom test tests/runner/native-dom-querying.test.js tests/runner/native-dom-parsing-serialization.test.js tests/runner/testing-library-role.test.js
zig-out/bin/zig-dom wpt --manifest wpt/manifest/selectors.json --expected wpt/expected/selectors.json
zig-out/bin/zig-dom wpt --manifest wpt/manifest/parser-fragments.json --expected wpt/expected/parser-fragments.json
```

Then run the mandatory `Edit.test.tsx` ReleaseFast perf guard.

## Milestone 9: WPT Upstream Smoke

Once local WPT slices improve, run broader upstream smoke:

```sh
zig-out/bin/zig-dom wpt --manifest wpt/manifest/upstream-dom-smoke.json --expected wpt/expected/upstream-dom-smoke.json
```

Then start reducing failures in:

```sh
zig-out/bin/zig-dom wpt --manifest wpt/manifest/upstream-dom.json --expected wpt/expected/upstream-dom.json
```

Do not try to make all upstream WPT green in one pass. Pick a cluster, fix it, add local regression tests, update expected failures only when justified, then run the perf guard.

## Milestone 10: Remove Legacy JS Package Layer

The runner and native DOM should be the source of truth. The old Bun FFI package layer should be removed or reduced to thin compatibility exports after downstream and WPT coverage is strong enough.

Current files to audit:

- `js/ffi.ts`
- `js/wrappers/*`
- `js/global-registrator.ts`
- `js/index.ts`
- `src/runner/builtins/zig-dom/index.js`
- `src/runner/builtins/zig-dom/global-registrator.js`
- `package.json` exports and scripts

Tasks:

- Remove `bun:ffi` from the package module path.
- Consolidate duplicate global registrators into one source of truth.
- Keep `src/runner/builtins/zig-dom/index.js` only if imports still need a thin compatibility module.
- Prefer native runtime global installation over JS wrapper behavior.
- Update package exports, README notes, and tests around the new native-only API.
- Delete obsolete wrapper/bootstrap files only after local runner tests, WPT slices, and downstream smoke tests prove they are unused.

Validation:

```sh
zig build --summary none
zig build test --summary none
zig-out/bin/zig-dom test tests/runner/global-registrator-builtin.test.js tests/runner/zig-dom-builtin-module.test.js tests/runner/native-dom-*.test.js
```

Then run the mandatory `Edit.test.tsx` ReleaseFast perf guard.

## Done Criteria For This Phase

- More `../youneedawiki` component tests pass without downstream edits.
- WPT manifests have narrower or better-understood expected-failure files.
- Local runner/DOM suites stay green.
- `Edit.test.tsx` ReleaseFast perf guard remains stable after every milestone and substantial sub-chunk.
- No new package-specific module hacks are added.
- Legacy Bun FFI wrapper code is either deleted or clearly isolated from the native runner path.

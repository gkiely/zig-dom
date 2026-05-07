# Agent Handoff Plan

## Goal

Broaden `zig-dom` runner support against real downstream usage and WPT while preserving the current fast iteration loop.

Primary tracks:

1. Keep runner performance stable, especially `Edit.test.tsx`.
2. Broaden `../youneedawiki` component support without editing downstream tests.
3. Add fast WPT iteration tooling.
4. Expand WPT coverage with expected-failure accounting.

Prefer generic fixes in the runner, native DOM, module loader, setup/plugin handling, mocks, and platform globals. Do not add package-specific hacks unless explicitly approved.

## Guardrails

`../youneedawiki` is a compatibility suite, not an implementation target.

Do not hardcode downstream-specific behavior in `zig-dom`, including component names, file paths, package names, module specifiers, setup file names, environment variables, CSS/runtime bypasses, plugin names, test names, or downstream library shims.

If a downstream test needs special setup behavior, implement the generic mechanism that Bun/browser-compatible tests expect:

- `Bun.plugin(...).onLoad`
- `mock.module`
- setup/preload ordering
- import/module resolution
- browser/platform globals
- DOM and Testing Library compatible behavior
- standard environment/config flags supplied by the user

Allowed downstream references: commands in this plan, regression test names used for validation, and comments in tests that explain downstream behavior being generalized.

Agents may add dev-only dependencies with `--save-dev` when they are needed for focused compatibility tests, for example `swr`.

## Validation Loop

Use the Debug development build for local and downstream single-file validation:

```sh
bun run build:dev
```

Run the ReleaseFast perf guard at the end of every milestone and any substantial sub-chunk:

```sh
bun run build:perf
bun run build:perf <test-file-token>
```

Use ReleaseFast only for the perf guard or performance comparisons. If the default perf guard regresses, stop and find the change before continuing.

## Baseline

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

The recent perf regression was caused by bypassing setup/onLoad pruning for `@mui/icons-material`. Keep plugin/onLoad ownership intact and preserve generic requested-export pruning.

## Milestones

### 1. Simple Downstream Components

- `WikiDomainSelector.test.tsx`
- `ShareModal.legacy.test.tsx`
- `AddMenu.test.tsx`
- `AddMenuLegacy.test.tsx`
- `AvatarMenu.test.tsx`
- `PrevNext.test.tsx`
- `Breadcrumbs.test.tsx`
- `Outline.test.tsx`

Likely areas: Testing Library role/name compatibility, user-event/fireEvent form behavior, focus/selection/activeElement behavior, fetch/Response/Headers, mock lifecycle, URL semantics, QuickJS shutdown cleanup, and module loader/onLoad behavior.

### 2. Platform Globals

Fill browser/node compatibility gaps generically as exposed by downstream tests:

- `fetch`, `Request`, `Response`, `Headers`, `Blob`
- `URL`, `URLSearchParams`
- `Image`
- `ResizeObserver`, `MutationObserver`, `matchMedia`
- `localStorage`, `sessionStorage`
- minimal `node:*` shims only when needed by real dependency graphs

Keep unsupported APIs explicit and diagnosable. Avoid fake network behavior unless the browser API shape requires a resolved or rejected promise.

### 3. Fast WPT Iteration

Implement:

- one-file WPT execution
- manifest filtering to one file or a small subset
- tiny smoke manifests or filters for `dom-core`, `events`, `forms`, `selectors`, and `parser`
- concise failure output with file path, test name, first failing assertion, expected/actual when available, and stack when available
- expected-failure reporting for newly passing, newly failing, and still expected-failing tests

Keep full harness dumps behind an explicit debug flag.

### 4. WPT DOM Core

Expand from the smallest manifests and keep expected failures explicit:

1. `dom-core`
2. `events`
3. `forms`
4. `selectors`
5. `parser-fragments`

Add or update expected failures only when the failure is understood. Prefer implementing missing standards behavior over widening expectations. Add focused `tests/runner/native-dom-*.test.js` regressions for every WPT behavior fixed.

### 5. Events And Forms Depth

Expand event semantics and form behavior:

- `addEventListener` options: capture, once, passive
- `stopPropagation`, `stopImmediatePropagation`, `preventDefault`
- event target/currentTarget/eventPhase ordering
- input, change, submit, click defaults
- form ownership, `form.elements`, disabled controls, labels
- text selection APIs needed by user-event

Use `native-dom-events`, `native-dom-forms-elements`, and the `events` / `forms` WPT manifests as focused checks.

### 6. Selectors, Parsing, Serialization

Expand support for selector and HTML parsing behavior:

- common selector combinations used by Testing Library and WPT
- attribute selectors and simple negation without unnecessary slow paths
- `matches`, `closest`, `querySelector`, `querySelectorAll`
- `innerHTML`, `outerHTML`, `insertAdjacentHTML`, text/entity serialization
- fragment parsing

Use `native-dom-querying`, `native-dom-parsing-serialization`, `testing-library-role`, and the `selectors` / `parser-fragments` WPT manifests as focused checks.

## Done Criteria

- More `../youneedawiki` component tests pass without downstream edits.
- WPT manifests have narrower or better-understood expected-failure files.
- Local runner/DOM suites stay green.
- `Edit.test.tsx` ReleaseFast perf guard remains stable after every milestone and substantial sub-chunk.
- No new package-specific module hacks are added.

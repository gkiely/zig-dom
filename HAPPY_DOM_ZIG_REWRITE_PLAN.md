# Plan: zig-dom, A Bun-Only Zig Rewrite Of Happy DOM

## Goal

Build `zig-dom`: a Zig-backed DOM implementation that can be imported from JavaScript as a smaller `happy-dom`-compatible package, runs only under Bun, and can be tested continuously against:

1. A small local compatibility suite.
2. A curated subset of Web Platform Tests (WPT).
3. In-repo Bun tests that render React components with `@testing-library/react` before the implementation is complete.

The project should optimize for an early usable slice, then grow spec coverage incrementally. Do not try to implement the entire WHATWG DOM and HTML surface before integration testing.

## Current Facts To Preserve

- `happy-dom` is a TypeScript monorepo package under `packages/happy-dom`; the public package exports browser-like APIs such as `Window`, `Browser`, `Document`, `HTMLElement`, and global registration helpers.
- Happy DOM’s stated scope is browser simulation for testing, scraping, and SSR, not full rendering.
- Happy DOM supports Vitest, Bun, Jest, Testing Library, React, Vue, Svelte, Angular, and Lit-style workflows.
- WPT `testharness.js` tests are the right compliance target for non-rendering browser behavior. Reftests/manual/layout tests are out of scope for the first rewrite.
- Bun FFI supports C ABI libraries including Zig, represents pointers as JS numbers, supports `CString`, `ptr`, `toArrayBuffer`, and requires explicit memory ownership decisions.
- Bun’s FFI docs currently mark `bun:ffi` experimental. Keep a small binding layer so Node-API or direct JS fallback remains possible later.
- Bun’s current FFI docs list primitive, pointer, buffer, cstring, and callback/function types, but do not document returning C structs by value. Treat all result structs below as internal Zig shapes unless verified against the Bun version in use; the FFI-facing ABI should prefer primitive status codes plus out-pointers or separately readable result buffers.
- Bun’s public DOM testing docs still use test preloads plus global registration. There does not appear to be a documented Bun API for JavaScriptCore global-scope extensions as of May 2026, but the concept is relevant if Bun exposes it later because it could avoid repeated global setup/teardown costs.
- Bun’s Testing Library guide recommends `@testing-library/jest-dom` in addition to React/DOM Testing Library, and a preload that extends Bun’s `expect` plus optionally runs Testing Library `cleanup()` after each test.
- Zig’s documented C ABI export path uses `export fn` and shared libraries built via `zig build-lib ... -dynamic` or `b.addLibrary(.{ .linkage = .dynamic, ... })`. Any exported structs/enums must be explicitly C ABI-compatible, for example `extern struct` or enums with explicit integer tags.

Sources checked:

- https://github.com/capricorn86/happy-dom
- https://github.com/capricorn86/happy-dom/wiki/Getting-started
- https://github.com/capricorn86/happy-dom/wiki/Setup-as-Test-Environment
- https://web-platform-tests.org/writing-tests/testharness.html
- https://web-platform-tests.org/running-tests/from-web.html
- https://bun.com/docs/runtime/ffi
- https://bun.com/docs/test/dom
- https://bun.com/docs/guides/test/testing-library
- https://ziglang.org/documentation/master/#Exporting-a-C-Library
- https://github.com/oven-sh/bun/issues/5845
- https://github.com/oven-sh/bun/issues/6044
- https://github.com/oven-sh/bun/issues/8852

## Non-Goals For The First Usable Version

- No visual layout engine.
- No CSS cascade implementation beyond attributes/style text needed by tests.
- No network stack beyond stubs and later delegation to Bun `fetch`.
- No script execution sandbox initially.
- No iframe browsing context isolation initially.
- No complete Custom Elements implementation until basic node/document/element/event behavior is stable.
- No broad happy-dom source port. Use happy-dom as API compatibility reference, not as the main test source.
- No Node.js, Jest, or Vitest runtime support requirement. Bun is the only required runtime.
- No untrusted script execution support.

## Architectural Decision

Use a hybrid architecture:

- Zig owns the DOM tree, node identity, attributes, text storage, selector indexes, parser state, and serialization.
- TypeScript owns the public JavaScript class surface, Web IDL-ish ergonomics, exceptions, iterable wrappers, and framework compatibility shims.
- Bun FFI exposes coarse native operations. Avoid one FFI call per trivial property access where batching is possible.
- JS wrapper objects are identity-preserving proxies around native node handles.
- Native handles are opaque `u64` IDs or pointer-sized handles. Prefer stable IDs internally so stale pointer detection and generation checks are possible.

## Bun Global Scope Strategy

A 2023 Bun runtime idea described using JavaScriptCore global-scope extensions to make DOM globals behave like an implicit scope layer, avoiding the cost and hazards of assigning/removing many properties on `globalThis`. This would be highly relevant to test startup performance, but it should be treated as a future runtime optimization, not a dependency.

Plan for today:

- Implement `GlobalRegistrator.register()` using Bun’s documented preload model.
- Install globals once per Bun test process by default, then reset `document` state between tests instead of unregistering/re-registering everything.
- Keep all global installation code isolated in `js/global-registrator.ts` and `tests/setup/register-dom.ts`.
- Track the time spent in:
  - package import
  - native library load
  - `GlobalRegistrator.register()`
  - per-test DOM cleanup
- Avoid per-test global teardown. Prefer `document.body.replaceChildren()` or a native `zig_dom_document_reset()` fast path.
- Add a feature-detection branch only if Bun exposes an official API later. Do not use private Bun/JSC symbols.

If Bun later exposes a global-scope-extension API:

- Add an adapter in `js/global-scope.ts`.
- Keep the public setup API unchanged.
- Benchmark current preload/global assignment against the new scope-extension path.
- Only make it the default if it is faster and does not break ESM, Testing Library cleanup, or Bun’s built-in globals.

## Project Decisions

- Package name: `zig-dom`.
- Runtime target: Bun only.
- Toolchain target: latest stable Bun and Zig. At handoff start, record `bun --version`, `bun --revision`, and `zig version` in `docs/compatibility.md`; current local versions are Bun `1.3.13` and Zig `0.16.0`.
- Test environment setup: explicit Bun preload via `bunfig.toml`, matching the happy-dom setup style.
- Compatibility target: a smaller happy-dom-compatible subset is acceptable while the rewrite matures.
- Script security: untrusted scripts are not expected to run inside this DOM.

## Agent Iteration Strategy

Use the fastest real feedback loop possible. The agent should not disappear into a large native DOM implementation before React, Testing Library, and a few WPT slices are exercising the public surface.

Preferred loop:

1. Prove the Zig/Bun FFI contract with a tiny dynamic library and unit test.
2. Build the JavaScript package shell, public classes, exports, and `GlobalRegistrator` early, even if some behavior is temporarily JS-owned.
3. Add a React Testing Library smoke test as soon as globals, constructors, element creation, text nodes, attributes, and basic queries exist.
4. Keep a missing-API harvest file at `examples/bun-react-smoke/failures.md` so each React smoke failure becomes an explicit implementation target.
5. Move hot or identity-sensitive DOM tree behavior into Zig incrementally.
6. Add WPT only as curated micro-slices for behavior already under implementation. Do not run broad WPT before local DOM and React smoke tests give useful signal.

Iteration rule:

- Every early ticket should leave one of these commands more useful than before: `bun test tests/unit`, `bun test tests/integration/dom`, `bun test tests/integration/react`, or `bun run test:wpt:dom`.
- React smoke failures are allowed before Ticket 5 only if the failing/missing API names are captured in `examples/bun-react-smoke/failures.md`.
- WPT expected failures must include a reason. A broad WPT failure list with no owner/reason is not useful progress.

## Repository Shape

Create this structure:

```text
zig-dom/
  build.zig
  build.zig.zon
  package.json
  tsconfig.json
  src/
    zig_dom.zig
    dom/
      arena.zig
      document.zig
      node.zig
      element.zig
      attr.zig
      text.zig
      event.zig
      selector.zig
      parser.zig
      serializer.zig
      string_pool.zig
      exception.zig
    ffi/
      api.zig
      handles.zig
      result.zig
  js/
    index.ts
    ffi.ts
    memory.ts
    wrappers/
      Window.ts
      Document.ts
      Node.ts
      Element.ts
      HTMLElement.ts
      Text.ts
      Comment.ts
      DocumentFragment.ts
      Event.ts
      NodeList.ts
      HTMLCollection.ts
    global-registrator.ts
    compatibility/
      happy-dom-symbols.ts
  tests/
    setup/
      register-dom.ts
    unit/
    integration/
      dom/
      react/
    fixtures/
  wpt/
    manifest/
    runner/
    expected/
  examples/
    bun-react-smoke/
  scripts/
    build-native.ts
    run-wpt-subset.ts
    sync-wpt.ts
    smoke-bun-react.ts
```

## Phase 0: Agent Bootstrap

Detailed steps:

1. Initialize the repo with Bun and Zig.
2. Add `package.json` scripts:
   - `build:native`: compile Zig dynamic library.
   - `build:js`: compile TypeScript to ESM.
   - `build`: run native and JS builds.
   - `test`: run local Bun tests.
   - `test:wpt:dom`: run curated WPT DOM subset.
   - `test:react`: run Bun React DOM smoke tests with `@testing-library/react`.
3. Configure package exports to mimic happy-dom enough for Bun test users:
   - `.` exports `Window`, DOM classes, `GlobalRegistrator`, and compatibility symbols.
   - `./global-registrator` exports `GlobalRegistrator`.
4. Add `bunfig.toml` with explicit preload setup for DOM/React integration tests.
5. Add CI-free local scripts first. Do not block early work on GitHub Actions.
6. Add a `docs/compatibility.md` file listing implemented APIs, known gaps, and WPT pass counts.

Exit criteria:

- `bun run build` produces `dist/index.js` and a platform-specific dynamic library.
- `import { Window } from './dist/index.js'` works in Bun.
- A native `zig_dom_version()` function can be called through Bun FFI.

## Phase 1: FFI Contract

Build the C ABI before implementing broad DOM behavior.

Native exported functions:

```zig
pub export fn zig_dom_version() [*:0]const u8;
pub export fn zig_dom_create_window() ZigDomHandle;
pub export fn zig_dom_destroy_window(window: ZigDomHandle) void;
pub export fn zig_dom_window_document(window: ZigDomHandle) ZigDomHandle;
pub export fn zig_dom_node_kind(node: ZigDomHandle) u32;
pub export fn zig_dom_node_parent(node: ZigDomHandle) ZigDomHandle;
pub export fn zig_dom_node_first_child(node: ZigDomHandle) ZigDomHandle;
pub export fn zig_dom_node_next_sibling(node: ZigDomHandle) ZigDomHandle;
pub export fn zig_dom_node_append_child(parent: ZigDomHandle, child: ZigDomHandle) ZigDomResult;
pub export fn zig_dom_node_remove_child(parent: ZigDomHandle, child: ZigDomHandle) ZigDomResult;
pub export fn zig_dom_document_create_element(document: ZigDomHandle, name_ptr: [*]const u8, name_len: usize) ZigDomResultHandle;
pub export fn zig_dom_document_create_text_node(document: ZigDomHandle, data_ptr: [*]const u8, data_len: usize) ZigDomResultHandle;
pub export fn zig_dom_element_get_attribute(element: ZigDomHandle, name_ptr: [*]const u8, name_len: usize) ZigDomStringResult;
pub export fn zig_dom_element_set_attribute(element: ZigDomHandle, name_ptr: [*]const u8, name_len: usize, value_ptr: [*]const u8, value_len: usize) ZigDomResult;
pub export fn zig_dom_element_remove_attribute(element: ZigDomHandle, name_ptr: [*]const u8, name_len: usize) ZigDomResult;
pub export fn zig_dom_node_text_content(node: ZigDomHandle) ZigDomStringResult;
pub export fn zig_dom_node_set_text_content(node: ZigDomHandle, data_ptr: [*]const u8, data_len: usize) ZigDomResult;
pub export fn zig_dom_node_outer_html(node: ZigDomHandle) ZigDomStringResult;
pub export fn zig_dom_document_reset(document: ZigDomHandle) ZigDomResult;
pub export fn zig_dom_free_string(ptr: [*]u8, len: usize) void;
pub export fn zig_dom_release_handle(handle: ZigDomHandle) void;
```

Rules:

- Every FFI function returns either a primitive, a handle, or an ABI shape verified with Bun FFI. Do not return Zig structs by value through Bun FFI until a local version probe proves it works; prefer a status code plus out parameters for handles, strings, and exception metadata.
- No Zig panic crosses the FFI boundary.
- Every error maps to a DOMException name and message.
- Strings crossing JS to Zig are UTF-8 bytes with explicit length.
- Strings crossing Zig to JS are copied to JS immediately, then freed with `zig_dom_free_string`.
- JS wrappers must never expose raw pointers publicly.

Exit criteria:

- Local tests cover handle creation/destruction, string round trips, exception mapping, and FinalizationRegistry cleanup.
- Running with `BUN_GC_TIMER` or explicit `gc()` in Bun can verify native release counts in debug builds.

## Phase 2: Memory Ownership Model

Implement memory rules before building many APIs.

Zig side:

- Each `Window` owns one allocator arena or general-purpose allocator instance.
- Each `Document` belongs to exactly one `Window`.
- Each node record has:
  - `id`
  - `generation`
  - `kind`
  - `owner_document`
  - `parent`
  - `first_child`
  - `last_child`
  - `prev_sibling`
  - `next_sibling`
  - `ref_count`
  - type-specific payload index
- A handle encodes `id + generation` or indexes into a table that validates generation.
- JS wrappers call `retain` when created and `release` when finalized.
- DOM tree ownership is separate from JS wrapper liveness. Removing a JS wrapper must not delete a node still owned by the DOM tree.
- Closing a window releases the document tree and invalidates all handles from that window.

JS side:

- Use a `WeakMap<number, NodeWrapper>` per window/document to preserve wrapper identity.
- Use `FinalizationRegistry` to call `zig_dom_release_handle`.
- Add explicit `window.close()` and `happyDOM.abort()` paths that free native resources deterministically.
- Mark wrappers from closed windows as detached-invalid and throw useful errors on use.

Exit criteria:

- Repeated create/append/remove/drop cycles do not leak in a debug allocation counter.
- Double-finalization does not double-free.
- Accessing a stale handle returns a controlled exception, not a crash.

## Phase 3: Minimal DOM Slice For React Smoke Tests

Implement only the APIs needed to mount and test simple React components under Testing Library.

Priority APIs:

- `new Window({ url })`
- `window.document`
- `document.documentElement`
- `document.head`
- `document.body`
- `document.createElement`
- `document.createTextNode`
- `document.createComment`
- `document.createDocumentFragment`
- `document.getElementById`
- `document.querySelector`
- `document.querySelectorAll`
- `Node.nodeType`
- `Node.nodeName`
- `Node.parentNode`
- `Node.childNodes`
- `Node.firstChild`
- `Node.lastChild`
- `Node.nextSibling`
- `Node.previousSibling`
- `Node.appendChild`
- `Node.insertBefore`
- `Node.removeChild`
- `Node.replaceChild`
- `Node.textContent`
- `Element.tagName`
- `Element.id`
- `Element.className`
- `Element.classList`
- `Element.attributes`
- `Element.getAttribute`
- `Element.setAttribute`
- `Element.removeAttribute`
- `Element.hasAttribute`
- `Element.innerHTML`
- `Element.outerHTML`
- `Element.children`
- `Element.matches`
- Basic `HTMLElement`
- Basic `HTMLInputElement`, `HTMLButtonElement`, `HTMLFormElement` stubs where React expects constructors.
- `Event`, `CustomEvent`, `MouseEvent` minimal constructors.
- `addEventListener`, `removeEventListener`, `dispatchEvent`.

Important React-specific notes:

- React uses feature detection heavily. Constructors and prototypes must exist even if some methods are stubs.
- `node.ownerDocument`, `document.defaultView`, and `window.HTMLElement` must be coherent.
- Events can initially be JS-owned, but event target registration may live in JS until native dispatch is worth optimizing.
- `MutationObserver` can be a no-op for the first smoke test only if the target repo does not require it. Add a failing compatibility test documenting the gap.

Exit criteria:

- This script passes:

```ts
import { Window } from "../dist/index.js";

const window = new Window({ url: "http://localhost/" });
const document = window.document;
const div = document.createElement("div");
div.id = "root";
document.body.appendChild(div);
div.innerHTML = "<button class=\"primary\">Save</button>";
console.assert(document.querySelector("button.primary")?.textContent === "Save");
window.close();
```

- A simple React component can render into `document.body` under Bun test.

## Phase 4: Bun React DOM Test Loop

The agent must make framework testing easy before broad spec work. The first integration target is an in-repo Bun test that imports React Testing Library and renders a real component.

Test workflow:

1. Add React, React DOM, and Testing Library as dev dependencies:
   - `react`
   - `react-dom`
   - `@testing-library/react`
   - `@testing-library/dom`
   - `@testing-library/jest-dom`
2. Add a reusable DOM setup file at `tests/setup/register-dom.ts`.
3. Add a reusable Testing Library setup file at `tests/setup/testing-library.ts` that imports matchers from `@testing-library/jest-dom/matchers`, calls `expect.extend(matchers)`, and runs `cleanup()` in `afterEach()` once that is stable.
4. Add direct DOM tests under `tests/integration/dom/*.test.ts`.
5. Add `tests/integration/react/App.tsx`.
6. Add `tests/integration/react/render.test.tsx`.
7. Configure `bunfig.toml` to preload both setup files, matching Bun’s documented happy-dom/Testing Library setup style.
8. Run `bun test tests/integration/dom tests/integration/react`.
9. Save recurring missing APIs or framework compatibility gaps to `examples/bun-react-smoke/failures.md`.

Minimum setup file:

```ts
import { GlobalRegistrator } from "zig-dom/global-registrator";

GlobalRegistrator.register({
  url: "http://localhost:3000",
  width: 1024,
  height: 768
});
```

Minimum Testing Library setup file:

```ts
import { afterEach, expect } from "bun:test";
import { cleanup } from "@testing-library/react";
import * as matchers from "@testing-library/jest-dom/matchers";

expect.extend(matchers);

afterEach(() => {
  cleanup();
  window.happyDOM.reset();
});
```

Minimum React smoke test:

```tsx
import "../../setup/register-dom";
import { render } from "@testing-library/react";
import { expect, test } from "bun:test";
import App from "./App";

test("renders", () => {
  const { container } = render(<App />);

  expect(container.firstChild).not.toBeNull();
});
```

Minimum `App.tsx`:

```tsx
export default function App() {
  return <main data-testid="app-root">Hello from Zig DOM</main>;
}
```

`GlobalRegistrator.register()` minimum behavior:

- Create one `Window`.
- Assign `globalThis.window`.
- Assign `globalThis.document`.
- Assign common constructors:
  - `Node`
  - `Element`
  - `HTMLElement`
  - `HTMLButtonElement`
  - `HTMLInputElement`
  - `HTMLFormElement`
  - `Text`
  - `Comment`
  - `DocumentFragment`
  - `Event`
  - `CustomEvent`
  - `MouseEvent`
  - `Document`
- Assign timer functions by delegating to Bun initially.
- Expose `happyDOM.abort()` and `happyDOM.close()` compatibility methods.
- Be idempotent. Calling it twice should reuse the existing registered window unless explicit options request a new one.
- Do not unregister/re-register globals between tests. Provide `GlobalRegistrator.reset()` or `window.happyDOM.reset()` to clear document state cheaply.

Exit criteria:

- `bun test tests/integration/react/render.test.tsx` runs with no external repo.
- `bun test tests/integration/dom tests/integration/react` is the standard early integration command.
- The smoke script or test output prints:
  - passed/failed tests
  - top missing API names from thrown errors
- `bun test` can include the React smoke test once it is stable enough not to slow down the inner loop.

## Phase 5: WPT Runner

Do not try to run all WPT at once.

First runner design:

- Vendor or shallow-clone WPT into `.wpt-cache/web-platform-tests`.
- Maintain `wpt/manifest/dom-core.json` listing explicit test files.
- Support only `testharness.js` tests at first.
- Transform or load WPT tests into a Bun VM-like execution context backed by the Zig DOM window.
- Provide `/resources/testharness.js` and `/resources/testharnessreport.js`.
- Capture `promise_test`, `async_test`, `test`, assertions, and completion callbacks.
- Report TAP or JSON.
- Track expected failures in `wpt/expected/*.json`.

Initial WPT subset:

- `dom/nodes/Node-appendChild.html`
- `dom/nodes/Node-insertBefore.html`
- `dom/nodes/Node-removeChild.html`
- `dom/nodes/Node-replaceChild.html`
- `dom/nodes/Document-createElement.html`
- `dom/nodes/Document-createTextNode.html`
- `dom/nodes/Element-getAttribute.html`
- `dom/nodes/Element-setAttribute.html`
- `dom/nodes/ParentNode-querySelector-All.html` or smaller selector-specific files if available.
- DOMException tests relevant to node insertion.

Runner stages:

1. Execute pure `.any.js` tests that require no HTML parser.
2. Execute `.html` testharness files by extracting scripts and creating the requested document.
3. Add support for `META: script` includes.
4. Add support for variants.
5. Add idlharness once Web IDL surfaces stabilize.

Exit criteria:

- `bun run test:wpt:dom` runs a fixed subset in under 10 seconds.
- Output includes pass count, fail count, expected fail count, unexpected pass count, and links/paths to failing tests.
- WPT expected-failure files require a reason and owner.

## Phase 6: DOM Core Completion

Implement DOM Standard core behavior with WPT-driven slices:

1. Node tree mutation algorithms.
2. Document ownership and adoption/import rules.
3. DocumentFragment insertion behavior.
4. Text, CharacterData, Comment, CDATA if needed.
5. DOMException names and messages.
6. Node normalization.
7. `compareDocumentPosition`.
8. `contains`.
9. `cloneNode`.
10. `isEqualNode`.
11. `getRootNode`.
12. Live `NodeList` and `HTMLCollection`.

Implementation guidance:

- Make tree mutation native from the beginning.
- Keep event listener storage in JS until profiling says otherwise.
- Make live collections lazy and generation-based:
  - Document has a mutation version.
  - Collection wrappers cache matching handles and invalidate when version changes.
- Maintain fast indexes for:
  - `id`
  - tag name
  - class tokens
- Keep selector engine incremental:
  - tag, id, class first
  - attribute presence/equality next
  - descendant/child combinators next
  - pseudo-classes after WPT pressure requires them.

Exit criteria:

- DOM core WPT subset is green except documented expected failures.
- Bun React smoke remains green.
- Benchmarks show native tree operations faster than pure JS wrappers for large append/query/serialize cases.

## Phase 7: HTML Parser And Serializer

Start with practical HTML, then approach spec behavior.

Steps:

1. Implement a simple tokenizer/parser sufficient for:
   - element tags
   - attributes
   - text
   - comments
   - void elements
   - entity decoding
2. Implement `innerHTML` and `outerHTML`.
3. Add fragment parsing with context element.
4. Handle table insertion modes enough for common frameworks.
5. Add template contents.
6. Add malformed HTML recovery WPT cases.

Consider using or studying existing Zig parser libraries only if license and performance fit. Do not invent a complex parser abstraction before the first smoke tests.

Exit criteria:

- `div.innerHTML = "<button disabled>Hello</button>"` works.
- Common React Testing Library snapshots serialize correctly.
- WPT HTML fragment/parser subset is running with expected failures tracked.

## Phase 8: Events

Start JS-owned, then move hot paths native if needed.

Steps:

1. Implement `EventTarget` in TypeScript wrappers.
2. Implement capture/bubble propagation using native parent chain lookups.
3. Implement:
   - `Event`
   - `CustomEvent`
   - `MouseEvent`
   - `InputEvent` minimal
   - `KeyboardEvent` minimal
4. Support:
   - `target`
   - `currentTarget`
   - `eventPhase`
   - `bubbles`
   - `cancelable`
   - `defaultPrevented`
   - `preventDefault`
   - `stopPropagation`
   - `stopImmediatePropagation`
5. Add property handler support:
   - `onclick`
   - `oninput`
   - `onchange`

Exit criteria:

- React click/change tests pass in Bun integration tests.
- WPT event dispatch basics pass.

## Phase 9: Browser Compatibility Surface

Implement enough happy-dom public API compatibility for common test environments.

Classes/modules:

- `Window`
- `Browser`
- `BrowserContext`
- `Page`
- `GlobalRegistrator`
- `PropertySymbol` compatibility export
- `DetachedWindowAPI`-like `window.happyDOM`

Minimal behavior:

- `Browser.newPage()` returns page with `mainFrame.document`.
- `page.content` maps to document HTML.
- `page.url` updates location.
- `waitUntilComplete()` drains known timers/promises where possible.
- `abort()` cancels registered timers/fetches where possible.
- `close()` frees native window.

Exit criteria:

- Existing happy-dom usage examples work, with unsupported methods documented.
- Vitest setup can use this package as a custom environment or setup import.

## Phase 10: Performance Work

Benchmark before optimizing.

Benchmarks:

- import time
- `GlobalRegistrator.register()` time
- per-test DOM reset time
- React Testing Library `cleanup()` time
- create 10k elements
- append 10k children
- set/get 10k attributes
- `querySelectorAll("div")`
- `querySelectorAll(".class")`
- `querySelectorAll("[data-x]")`
- `innerHTML` parse for common component HTML
- `outerHTML` serialize
- React render smoke test time

Optimization targets:

- Batch FFI calls for list returns and serialization.
- Intern tag names, attribute names, namespace strings, and common values.
- Store ASCII-lowercase tag/attribute names once.
- Use arena allocation per window plus free lists for removed nodes.
- Avoid JS wrapper creation for query operations until results are accessed, if possible.
- Profile FinalizationRegistry overhead; add explicit close paths for deterministic tests.

Exit criteria:

- Benchmarks compare against current `happy-dom` and `jsdom`.
- Regressions over 10 percent require a note or fix.

## Phase 11: Compliance Expansion

Add these areas in WPT-driven order:

1. URL/location basics.
2. `DOMTokenList`.
3. `dataset`.
4. `style` as text plus basic `CSSStyleDeclaration`.
5. Forms and form controls.
6. Focus/blur.
7. Selection and ranges.
8. MutationObserver.
9. Custom Elements.
10. Shadow DOM.
11. Fetch/File/FormData/Headers where needed.
12. Storage/cookies.

Rule for each area:

- Add WPT subset manifest first.
- Add a local Bun integration regression if a real framework or app pattern needs it.
- Implement minimal passing behavior.
- Update `docs/compatibility.md`.

## Handoff Task Template For Agents

Use this for each implementation ticket:

```md
## Task
Implement [specific API/behavior].

## Scope
Files/modules likely involved:
- src/dom/[module].zig
- src/ffi/api.zig
- js/wrappers/[Wrapper].ts
- tests/unit/[test].test.ts
- wpt/manifest/[subset].json
- wpt/expected/[subset].json

## Requirements
- Preserve JS wrapper identity.
- Validate native handles before use.
- Map errors to DOMException-compatible names.
- Add local unit tests.
- Add or update WPT subset entries.
- Run `bun run build`, `bun test`, and relevant WPT subset.
- Run `bun test tests/integration/react/render.test.tsx` if behavior can affect framework tests.

## Done When
- Local tests pass.
- WPT subset pass count does not decrease unless expected failures are updated with reasons.
- Bun React smoke result is unchanged or improved.
- `docs/compatibility.md` is updated.
```

## First Seven Tickets

### Ticket 1: Scaffold Build And FFI ABI Probe

Implement repo skeleton, Zig dynamic library build, TypeScript `dlopen`, and a tiny FFI test surface.

Scope:

- `build.zig`
- `build.zig.zon`
- `package.json`
- `tsconfig.json`
- `src/zig_dom.zig`
- `src/ffi/api.zig`
- `js/ffi.ts`
- `js/memory.ts`
- `tests/unit/ffi.test.ts`
- `docs/compatibility.md`

Required probes:

- `zig_dom_version()`.
- JS string to Zig bytes with explicit length.
- Zig allocated string copied to JS and freed with `zig_dom_free_string`.
- Pointer/handle round trip using the intended handle representation.
- ABI decision test proving whether Bun can safely read the planned result shape. If C/Zig struct returns are not proven, use primitive status codes plus out-pointers.

Done when:

- `bun run build` succeeds.
- `bun test tests/unit/ffi.test.ts` passes.
- `docs/compatibility.md` records Bun version, Bun revision, Zig version, platform, library extension, and FFI ABI decisions.

### Ticket 2: JavaScript Package Shell And Global Registration

Implement the public package shape before broad native behavior. It is acceptable for this ticket to use a small JS-owned DOM skeleton while the Zig handle table is still thin.

Scope:

- `js/index.ts`
- `js/global-registrator.ts`
- `js/wrappers/Window.ts`
- `js/wrappers/Document.ts`
- `js/wrappers/Node.ts`
- `js/wrappers/Element.ts`
- `js/wrappers/HTMLElement.ts`
- `js/wrappers/Text.ts`
- `js/wrappers/Comment.ts`
- `js/wrappers/DocumentFragment.ts`
- `js/compatibility/happy-dom-symbols.ts`
- `tests/setup/register-dom.ts`
- `tests/integration/dom/global-registrator.test.ts`

Required behavior:

- Package exports for `.` and `./global-registrator`.
- `new Window({ url })`, `window.document`, `document.defaultView`, `document.documentElement`, `document.head`, and `document.body`.
- Global registration of `window`, `document`, common constructors, timers delegated to Bun, and `window.happyDOM.reset()/close()/abort()`.
- Idempotent `GlobalRegistrator.register()`.
- Basic JS wrapper identity preservation, even if native handles are introduced in the next ticket.

Done when:

- `new Window().document` returns stable object identity.
- `bun test tests/integration/dom/global-registrator.test.ts` passes.
- `import { Window, GlobalRegistrator } from "./dist/index.js"` works in Bun after `bun run build`.

### Ticket 3: React Testing Library Smoke Harness

Add React and Testing Library integration before completing the native DOM. This ticket is allowed to expose missing APIs, but it must make those failures easy to act on.

Scope:

- `bunfig.toml`
- `tests/setup/register-dom.ts`
- `tests/setup/testing-library.ts`
- `tests/integration/react/App.tsx`
- `tests/integration/react/render.test.tsx`
- `scripts/smoke-bun-react.ts`
- `examples/bun-react-smoke/failures.md`
- Any JS wrapper stubs needed for React feature detection.

Required behavior:

- Install React, React DOM, `@testing-library/react`, `@testing-library/dom`, and `@testing-library/jest-dom`.
- Preload DOM globals and Testing Library matchers.
- Provide constructors/prototypes React commonly feature-detects: `Node`, `Element`, `HTMLElement`, `HTMLButtonElement`, `HTMLInputElement`, `HTMLFormElement`, `Text`, `Comment`, `DocumentFragment`, `Event`, `CustomEvent`, `MouseEvent`, and `Document`.
- Run a smoke test that renders a simple component into `document.body`.
- Capture missing API names and representative stack traces in `examples/bun-react-smoke/failures.md` when the smoke is not yet green.

Done when:

- `bun test tests/integration/react/render.test.tsx` either passes or fails only with documented missing APIs in `examples/bun-react-smoke/failures.md`.
- The smoke output prints the top missing API names from thrown errors.
- The next implementation target is obvious from the failure list.

### Ticket 4: Native Window, Document, Handle Table, And Node Tree

Move the core identity and tree model into Zig now that the JS package surface and React harness exist.

Scope:

- `src/dom/arena.zig`
- `src/dom/document.zig`
- `src/dom/node.zig`
- `src/dom/element.zig`
- `src/dom/text.zig`
- `src/ffi/api.zig`
- `src/ffi/handles.zig`
- `js/wrappers/Window.ts`
- `js/wrappers/Document.ts`
- `js/wrappers/Node.ts`
- `js/wrappers/Element.ts`
- `js/wrappers/Text.ts`
- `tests/unit/handles.test.ts`
- `tests/integration/dom/tree-mutation.test.ts`

Required behavior:

- Native window/document creation and deterministic `window.close()`.
- Handle table with generation validation.
- JS wrapper identity maps per window/document.
- FinalizationRegistry release path plus explicit close path.
- `createElement`, `createTextNode`, `appendChild`, `insertBefore`, `removeChild`, and `replaceChild`.
- Controlled exceptions for stale or invalid handles.

Done when:

- Basic DOM tree unit and integration tests pass.
- `new Window().document` still returns stable object identity.
- Repeated create/append/remove/drop cycles do not leak in a debug allocation counter.
- React smoke failure list shrinks or remains unchanged.

### Ticket 5: Make React Smoke Green

Implement the minimum DOM APIs needed for the simple React Testing Library render test to pass end to end.

Scope:

- `js/wrappers/Document.ts`
- `js/wrappers/Element.ts`
- `js/wrappers/HTMLElement.ts`
- `js/wrappers/Event.ts`
- `src/dom/attr.zig`
- `src/dom/selector.zig`
- `src/dom/serializer.zig`
- `src/ffi/api.zig`
- `tests/integration/react/render.test.tsx`
- `examples/bun-react-smoke/failures.md`

Required behavior:

- Element attributes, `id`, `className`, `classList` minimal, `textContent`, `innerHTML` subset, `children`, `childNodes`, `querySelector`, and `querySelectorAll`.
- Basic `EventTarget` storage in JS if native dispatch is not needed yet.
- Enough constructors and prototype relationships for React and Testing Library feature detection.
- `window.happyDOM.reset()` clears document state cheaply between tests.

Done when:

- `bun test tests/integration/react/render.test.tsx` passes.
- At least one React Testing Library render/assertion test passes using:

```tsx
import "../../setup/register-dom";
import { render } from "@testing-library/react";
import { expect, test } from "bun:test";
import App from "./App";

test("renders", () => {
  const { container } = render(<App />);

  expect(container.firstChild).not.toBeNull();
});
```

### Ticket 6: Tiny WPT Runner And DOM Micro-Slices

Add the WPT runner only after local DOM and React smoke tests provide useful signal. Keep the first WPT scope deliberately small.

Scope:

- `wpt/runner/`
- `wpt/manifest/dom-core.json`
- `wpt/expected/dom-core.json`
- `scripts/sync-wpt.ts`
- `scripts/run-wpt-subset.ts`
- `tests/integration/wpt-runner/*.test.ts`
- `docs/compatibility.md`

Initial WPT subset:

- One `.any.js` test that needs no parser.
- One focused node mutation test such as append/remove.
- One focused `Document.createElement` or `createTextNode` test.
- One focused attribute get/set test.

Required runner capabilities:

- Discover and execute explicit manifest entries.
- Load enough `testharness.js` support to capture sync and promise tests.
- Produce deterministic JSON output with file, subtest name, status, message, duration, and expected-failure comparison.
- Require reason strings for expected failures.

Done when:

- `bun run test:wpt:dom` runs the tiny manifest reliably in under 10 seconds.
- `docs/compatibility.md` records subset size and pass/fail/expected-fail counts.
- Adding the next WPT file should not require a runner redesign.

### Ticket 7: UI-Oriented Bun React Tests

Add a broader in-repo UI test suite that exercises the DOM the way component tests actually use it. This should still run under `bun test`; do not introduce Playwright or a browser for this ticket.

Scope:

- `tests/integration/react/App.tsx`
- `tests/integration/react/render.test.tsx`
- `tests/integration/react/events.test.tsx`
- `tests/integration/react/forms.test.tsx`
- `tests/setup/register-dom.ts`
- `js/wrappers/Event.ts`
- `js/wrappers/Element.ts`
- `js/wrappers/HTMLElement.ts`
- Any native DOM APIs needed by these tests.

Required UI scenarios:

- Render a component and assert text/attributes with Testing Library queries.
- Click a button and assert React state updates.
- Type/change an input and assert `value`, `input`, and `change` behavior.
- Submit a form and assert `preventDefault()` works.
- Conditional rendering that removes and re-adds nodes.
- Cleanup between tests using Testing Library `cleanup()` plus `window.happyDOM.reset()` or equivalent.

Recommended test shape:

```tsx
import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "bun:test";
import { cleanup } from "@testing-library/react";

afterEach(() => {
  cleanup();
  window.happyDOM.reset();
});

test("click updates UI", () => {
  render(<Counter />);
  fireEvent.click(screen.getByRole("button", { name: "Increment" }));
  expect(screen.getByText("Count: 1")).toBeDefined();
});
```

Done when:

- `bun test tests/integration/react` passes.
- Missing API failures from Testing Library are captured in `examples/bun-react-smoke/failures.md`.
- Event dispatch, form value reflection, and cleanup/reset behavior have unit or integration coverage.
- Phase 8/Event requirements are updated if this ticket discovers necessary event APIs.

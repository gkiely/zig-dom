# zig-dom compatibility

## Environment

- Date: 2026-05-03
- Platform: macOS
- Bun version: 1.3.13
- Bun revision: 1.3.13+bf2e2cecf
- Zig version: 0.16.0
- TypeScript version: 6.0.3
- Native library extension: dylib
- FFI ABI decision: Bun struct-by-value return is treated as unsupported for stable ABI. Public FFI uses status codes + out pointers.

## Implemented API slices

- Native: window/document creation, node tree mutation, attribute get/set/remove, attribute list export, text content, outer HTML, basic selector fast path, document reset.
- Native relationship ops: `zig_dom_node_contains()` and `zig_dom_node_compare_document_position()` now back `Node.contains()` and `Node.compareDocumentPosition()` from Zig.
- JS wrappers: Window, Document, Node, Element, HTMLElement, Text, Comment, DocumentFragment, Event, CustomEvent, MouseEvent, InputEvent, KeyboardEvent, and DOMException-compatible errors.
- DOM core extras: `getRootNode()`, `compareDocumentPosition()`, `cloneNode()`, `isEqualNode()`, `normalize()`, `dataset`, and reflected style text via `HTMLElement.style`.
- DOM ownership APIs: `Document.adoptNode()` and `Document.importNode()` are implemented with cross-window insertion protection and clone/import coverage.
- Selector expansion: grouped selectors, child/adjacent/general sibling combinators, attribute operators (`=`, `~=`, `|=`, `^=`, `$=`, `*=`), and pseudo-classes (`:first-child`, `:last-child`, `:nth-child()`, `:not()`, `:is()`, `:where()`) are available through the JS selector engine with native fast-path fallback for simple selectors.
- URL basics: `window.location` supports `href`, `protocol`, `host`, `hostname`, `port`, `pathname`, `search`, `hash`, `origin`, `assign()`, and `replace()`.
- Focus basics: `HTMLElement.focus()`, `HTMLElement.blur()`, and `document.activeElement` are implemented for test-environment behavior.
- MutationObserver surface: queued mutation records for `attributes`, `childList`, and `characterData`, including subtree and oldValue options, plus async callback delivery and `takeRecords()` drain behavior.
- Selection basics: `Range`, `Selection`, `document.createRange()`, and `document.getSelection()` are implemented with minimal behavior.
- Storage/cookie basics: `localStorage`, `sessionStorage`, and simple `document.cookie` name/value handling are implemented.
- Fetch/file/form basics: `window.fetch`, `Headers`, `Request`, `Response`, `FormData`, `Blob`, and `File` are exposed via Bun primitives.
- Forms and controls: `HTMLInputElement` (`value/defaultValue`, `checked/defaultChecked`), `HTMLFormElement.elements/reset/submit`, `HTMLSelectElement`, `HTMLOptionElement`, `HTMLTextAreaElement`, and `HTMLLabelElement.control` are implemented for React/Testing Library compatibility.
- Events/UI events: composed path support, listener object removal correctness, `once`/`capture`/`passive` option handling, disabled submit control behavior, and expanded event fields (for example `MouseEvent.relatedTarget`, `KeyboardEvent.location`).
- Custom element semantics: upgrade and lifecycle callbacks (`connectedCallback`, `disconnectedCallback`, `attributeChangedCallback`) remain covered, including late-upgrade flows.
- Shadow DOM basics: `HTMLElement.attachShadow({ mode })` and `shadowRoot` (open mode) are implemented and covered by local and WPT-style tests.
- Registration: GlobalRegistrator preload setup with idempotent register/reset/unregister.
- Compatibility exports: PropertySymbol and browser-like Browser/BrowserContext/Page with lifecycle/content/url coverage in integration tests.
- Test harnesses: Bun unit/integration tests, React smoke integration, tiny WPT-style subset runner with `.any.ts`, `.html` (inline + `META: script=` includes), and manifest-driven variant/variants execution.
- WPT manifests: dedicated manifests now exist for selectors, events, parser fragments, forms, and custom-elements/shadow slices in addition to the tiny core manifest.
- Native debug probe: test-only debug counters expose window/node create-destroy balance for leak verification in repeated create/append/remove/close cycles.
- Placeholder Zig DOM modules under `src/dom/` were removed to avoid stale boundary placeholders until real module extraction is introduced.
- Performance path optimizations: known-kind node wrapping for creation APIs, lazy `HTMLElement.style` and `Element.classList` allocation, zero-copy native reads for `getAttribute()`, encoded window-scoped native handles with indexed node lookup, and `ReleaseFast` native builds by default.
- Source import policy: TypeScript source now uses `.ts` relative import specifiers with compiler rewrite to emitted `.js` paths.

## Known gaps

- HTML parser for `innerHTML` is still pragmatic and not fully spec-complete (notably table/template insertion-mode behavior and broad malformed-markup recovery semantics).
- Event system is significantly deeper but still not full DOM/UI events parity for all default actions, composed/shadow dispatch edge cases, and full constructor field coverage.
- Selector support is substantially expanded but still not full CSS selector parity (for example advanced structural/state pseudo-classes remain partial).
- WPT runner now has explicit category manifests, but remains an in-repo curated harness rather than full upstream idlharness/resource loading.
- Expected-failure map is intentionally strict: each entry must include non-empty `reason` and `owner`, and duplicate file/subtest keys are rejected.
- Custom Elements and Shadow DOM remain partial for advanced lifecycle/slotting/composed-tree edge cases.
- Benchmark caveats: `global_register_ms` and cross-runtime React smoke are not available for happy-dom/jsdom in the current harness.
- Benchmark methodology note: `append_10k_children_ms` pre-creates children before timing so the row measures append throughput rather than create+append mixed cost (creation is already covered by `create_10k_elements_ms`).

## Verification log

- `bun run build`: pass
- `bun run verify:ffi`: pass (4 tests, includes native contains/compare/attributes assertions)
- `bun run verify:dom`: pass (40 tests)
- `bun run verify:react`: pass (React smoke)
- `bun run verify:wpt:tiny`: pass (12/12 subtests pass, 0 expected fail)
- `bun run test:wpt:expanded`: pass (selectors/events/parser/forms/custom-elements-shadow manifests all green)
- `bun run verify:fast`: pass
- `bun test`: pass (49 tests across 17 files, 147 assertions)
- tiny WPT files include TypeScript (`.any.ts`) plus `.html` harness coverage with `META: script=` includes and variants, covering `compareDocumentPosition`, selectors, location, dataset, and storage/cookie basics.
- `bun run benchmark:dom`: pass and writes `docs/benchmarks/latest.json` with zig-dom vs happy-dom vs jsdom metrics.

## Benchmark snapshot (latest)

- `create_10k_elements_ms`: zig-dom 5.95, happy-dom 6.27, jsdom 12.75
- `append_10k_children_ms`: zig-dom 2.09, happy-dom 6.22, jsdom 16.25
- `set_get_10k_attributes_ms`: zig-dom 12.05, happy-dom 19.60, jsdom 23.23
- `query_all_div_10k_ms`: zig-dom 2.86, happy-dom 13.14, jsdom 13.29
- `query_all_class_10k_ms`: zig-dom 1.70, happy-dom 20.09, jsdom 29.73
- `query_all_attr_10k_ms`: zig-dom 1.38, happy-dom 8.75, jsdom 19.85
- `inner_html_parse_ms`: zig-dom 6.06, happy-dom 13.32, jsdom 27.69
- `outer_html_serialize_ms`: zig-dom 0.16, happy-dom 2.14, jsdom 2.31
- `import_time_ms`: zig-dom 28.08, happy-dom 55.71, jsdom 359.48
- `global_register_ms`: zig-dom 0.25
- `reset_500x_ms`: zig-dom 0.50, happy-dom 0.71, jsdom 3.74
- `react_render_smoke_ms`: zig-dom 140.18

## Warm-run timing (macOS)

- `verify:ffi`: ~0.35s
- `verify:dom`: ~1.2s
- `verify:react`: ~1.1s
- `verify:wpt:tiny`: 0.04s
- `verify:fast`: ~2.8s

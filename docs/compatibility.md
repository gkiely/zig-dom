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

- Native: window/document creation, node tree mutation, attribute get/set/remove, attribute list export, text content, outer HTML, basic selectors, document reset.
- Native relationship ops: `zig_dom_node_contains()` and `zig_dom_node_compare_document_position()` now back `Node.contains()` and `Node.compareDocumentPosition()` from Zig.
- JS wrappers: Window, Document, Node, Element, HTMLElement, Text, Comment, DocumentFragment, Event, CustomEvent, MouseEvent, InputEvent, KeyboardEvent.
- DOM core extras: `getRootNode()`, `compareDocumentPosition()`, `cloneNode()`, `isEqualNode()`, `normalize()`, `dataset`, and reflected style text via `HTMLElement.style`.
- URL basics: `window.location` supports `href`, `protocol`, `host`, `hostname`, `port`, `pathname`, `search`, `hash`, `origin`, `assign()`, and `replace()`.
- Focus basics: `HTMLElement.focus()`, `HTMLElement.blur()`, and `document.activeElement` are implemented for test-environment behavior.
- MutationObserver surface: `MutationObserver` exists with construct/observe/disconnect/takeRecords no-op semantics for compatibility.
- Selection basics: `Range`, `Selection`, `document.createRange()`, and `document.getSelection()` are implemented with minimal behavior.
- Storage/cookie basics: `localStorage`, `sessionStorage`, and simple `document.cookie` name/value handling are implemented.
- Fetch/file/form basics: `window.fetch`, `Headers`, `Request`, `Response`, `FormData`, `Blob`, and `File` are exposed via Bun primitives.
- Custom element basics: `customElements.define/get/whenDefined` and prototype upgrade on `document.createElement()` are implemented.
- Shadow DOM basics: `HTMLElement.attachShadow({ mode })` and `shadowRoot` (open mode) are implemented.
- Registration: GlobalRegistrator preload setup with idempotent register/reset/unregister.
- Compatibility exports: PropertySymbol and browser-like Browser/BrowserContext/Page with lifecycle/content/url coverage in integration tests.
- Test harnesses: Bun unit/integration tests, React smoke integration, tiny WPT-style subset runner with `.any.ts`, `.html` (inline + `META: script=` includes), and manifest-driven variant/variants execution.
- Performance path optimizations: known-kind node wrapping for creation APIs, lazy `HTMLElement.style` and `Element.classList` allocation, zero-copy native reads for `getAttribute()`, encoded window-scoped native handles with indexed node lookup, and `ReleaseFast` native builds by default.
- Source import policy: TypeScript source now uses `.ts` relative import specifiers with compiler rewrite to emitted `.js` paths.

## Known gaps

- Selector engine currently supports basic selectors and descendant combinators only.
- HTML parser for innerHTML is pragmatic and not fully spec-complete.
- Event system supports capture/target/bubble and common event classes, but not full DOM Events and UI Events edge-case parity.
- WPT runner supports tiny in-repo subset files, basic `.html` harness execution, `META: script=` includes, and manifest variant/variants options, but not full upstream testharness HTML loading (idlharness/full resource model).
- Expected-failure map is intentionally strict: each entry must include non-empty `reason` and `owner`, and duplicate file/subtest keys are rejected.
- Custom Elements and Shadow DOM advanced lifecycle semantics are not implemented yet.
- Benchmark caveats: `global_register_ms` and cross-runtime React smoke are not available for happy-dom/jsdom in the current harness.
- Benchmark methodology note: `append_10k_children_ms` pre-creates children before timing so the row measures append throughput rather than create+append mixed cost (creation is already covered by `create_10k_elements_ms`).

## Verification log

- `bun run build`: pass
- `bun run verify:ffi`: pass (4 tests, includes native contains/compare/attributes assertions)
- `bun run verify:dom`: pass (24 tests)
- `bun run verify:react`: pass (React smoke)
- `bun run verify:wpt:tiny`: pass (11/11 subtests pass, 0 expected fail)
- `bun run verify:fast`: pass
- `bun test`: pass (30 tests across 14 files, 92 assertions)
- tiny WPT files include TypeScript (`.any.ts`) plus `.html` harness coverage with `META: script=` includes and variants, covering `compareDocumentPosition`, location, dataset, and storage/cookie basics.
- `bun run benchmark:dom`: pass and writes `docs/benchmarks/latest.json` with zig-dom vs happy-dom vs jsdom metrics.

## Benchmark snapshot (latest)

- `create_10k_elements_ms`: zig-dom 5.02, happy-dom 9.79, jsdom 20.84
- `append_10k_children_ms`: zig-dom 5.29, happy-dom 7.67, jsdom 17.93
- `set_get_10k_attributes_ms`: zig-dom 6.42, happy-dom 19.57, jsdom 15.83
- `query_all_div_10k_ms`: zig-dom 8.04, happy-dom 10.07, jsdom 14.47
- `query_all_class_10k_ms`: zig-dom 1.93, happy-dom 18.34, jsdom 24.35
- `query_all_attr_10k_ms`: zig-dom 1.76, happy-dom 8.29, jsdom 18.93
- `inner_html_parse_ms`: zig-dom 6.42, happy-dom 13.93, jsdom 24.71
- `outer_html_serialize_ms`: zig-dom 0.18, happy-dom 2.63, jsdom 3.16
- `import_time_ms`: zig-dom 15.17, happy-dom 51.96, jsdom 350.32
- `reset_500x_ms`: zig-dom 0.55, happy-dom 0.85, jsdom 3.98
- `react_render_smoke_ms`: zig-dom 136.12

## Warm-run timing (macOS)

- `verify:ffi`: 0.38s
- `verify:dom`: 1.10s
- `verify:react`: 1.05s
- `verify:wpt:tiny`: 0.04s
- `verify:fast`: 2.60s

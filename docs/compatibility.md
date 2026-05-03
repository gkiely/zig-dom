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

- Native: window/document creation, node tree mutation, attribute get/set/remove, text content, outer HTML, basic selectors, document reset.
- JS wrappers: Window, Document, Node, Element, HTMLElement, Text, Comment, DocumentFragment, Event, CustomEvent, MouseEvent, InputEvent, KeyboardEvent.
- DOM core extras: `getRootNode()`, `compareDocumentPosition()`, `cloneNode()`, `isEqualNode()`, `normalize()`, `dataset`, and reflected style text via `HTMLElement.style`.
- URL basics: `window.location` supports `href`, `protocol`, `host`, `hostname`, `port`, `pathname`, `search`, `hash`, `origin`, `assign()`, and `replace()`.
- Focus basics: `HTMLElement.focus()`, `HTMLElement.blur()`, and `document.activeElement` are implemented for test-environment behavior.
- MutationObserver surface: `MutationObserver` exists with construct/observe/disconnect/takeRecords no-op semantics for compatibility.
- Selection basics: `Range`, `Selection`, `document.createRange()`, and `document.getSelection()` are implemented with minimal behavior.
- Storage/cookie basics: `localStorage`, `sessionStorage`, and simple `document.cookie` name/value handling are implemented.
- Custom element basics: `customElements.define/get/whenDefined` and prototype upgrade on `document.createElement()` are implemented.
- Shadow DOM basics: `HTMLElement.attachShadow({ mode })` and `shadowRoot` (open mode) are implemented.
- Registration: GlobalRegistrator preload setup with idempotent register/reset/unregister.
- Compatibility exports: PropertySymbol and browser-like Browser/BrowserContext/Page with lifecycle/content/url coverage in integration tests.
- Test harnesses: Bun unit/integration tests, React smoke integration, tiny WPT-style subset runner.
- Source import policy: TypeScript source now uses `.ts` relative import specifiers with compiler rewrite to emitted `.js` paths.

## Known gaps

- Selector engine currently supports basic selectors and descendant combinators only.
- HTML parser for innerHTML is pragmatic and not fully spec-complete.
- Event system supports capture/target/bubble and common event classes, but not full DOM Events and UI Events edge-case parity.
- WPT runner currently executes tiny in-repo subset files, not full upstream testharness HTML loading.
- Custom Elements and Shadow DOM advanced lifecycle semantics are not implemented yet.

## Verification log

- `bun run build`: pass
- `bun run verify:ffi`: pass (4 tests)
- `bun run verify:dom`: pass (22 tests)
- `bun run verify:react`: pass (React smoke)
- `bun run verify:wpt:tiny`: pass (4/4 pass, 0 expected fail)
- `bun run verify:fast`: pass
- `bun test`: pass (26 tests across 13 files, 76 assertions)
- tiny WPT files are TypeScript (`.any.ts`) and include `compareDocumentPosition` coverage.

## Warm-run timing (macOS)

- `verify:ffi`: 0.38s
- `verify:dom`: 1.10s
- `verify:react`: 1.05s
- `verify:wpt:tiny`: 0.04s
- `verify:fast`: 2.60s

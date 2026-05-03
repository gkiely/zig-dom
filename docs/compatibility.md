# zig-dom compatibility

## Environment

- Date: 2026-05-03
- Platform: macOS
- Bun version: 1.3.13
- Bun revision: 1.3.13+bf2e2cecf
- Zig version: 0.16.0
- Native library extension: dylib
- FFI ABI decision: Bun struct-by-value return is treated as unsupported for stable ABI. Public FFI uses status codes + out pointers.

## Implemented API slices

- Native: window/document creation, node tree mutation, attribute get/set/remove, text content, outer HTML, basic selectors, document reset.
- JS wrappers: Window, Document, Node, Element, HTMLElement, Text, Comment, DocumentFragment, Event, CustomEvent, MouseEvent.
- Registration: GlobalRegistrator preload setup with idempotent register/reset/unregister.
- Compatibility exports: PropertySymbol and browser-like Browser/BrowserContext/Page stubs.
- Test harnesses: Bun unit/integration tests, React smoke integration, tiny WPT-style subset runner.

## Known gaps

- Selector engine currently supports basic selectors and descendant combinators only.
- HTML parser for innerHTML is pragmatic and not fully spec-complete.
- Event system is focused on component-test behavior and not full DOM Events compliance.
- WPT runner currently executes tiny in-repo subset files, not full upstream testharness HTML loading.

## Verification log

- Pending first full run after bootstrap.

# Bun-Specific Performance Plan

This is a short list of `zig-dom` library performance ideas that specifically use Bun or fit Bun-only constraints. The target workload is real React/Testing Library usage such as `../youneedawiki`'s DOM tests, not the benchmark harness itself.

## 1. Try `Bun.escapeHTML()` in serialization

`zig-dom` currently has JS-side escaping in serialization paths such as `outerHTML`. Bun exposes `Bun.escapeHTML()`, which is implemented natively and optimized for large strings.

Validation:
- Compare text-node serialization, attribute serialization, and full `outerHTML` output against existing tests.
- Attribute escaping may need a separate path if DOM attribute rules diverge from `Bun.escapeHTML()`.
- Add focused benchmarks for large text nodes, many small text nodes, and React Testing Library debug-style output.

## 2. Move bulk string work over the native boundary

Any hot path that walks many nodes in JS and concatenates strings is a candidate for a larger Zig/native operation. The key is to avoid many tiny FFI calls and prefer one bulk call returning a complete string or typed buffer.

Candidates:
- Full subtree serialization.
- Bulk `textContent` collection.
- Larger `innerHTML` parse/replace operations.

Validation:
- Profile `../youneedawiki` `test-dom` to confirm which serialization or string paths dominate.
- Measure against both small DOM updates and large tree render/debug cases.

## 3. Delegate compatible primitives to Bun-native Web APIs

Because `zig-dom` is Bun-only, it can use Bun's built-in Web APIs where behavior matches DOM expectations closely enough.

Candidates:
- `URL` and `URLSearchParams`.
- `TextEncoder` and `TextDecoder`.
- `Blob`, `File`, `FormData`, `Headers`, `Request`, and `Response`.
- Possibly `EventTarget`, only if DOM propagation semantics can remain correct.

Validation:
- Keep compatibility tests around edge cases before replacing local implementations.
- Prefer small targeted delegations over broad rewrites.

## 4. Add build-time fast-path constants

Use Bun-compatible static constants or defines to strip slow debug or strict validation branches from production/test builds where appropriate.

Possible constants:
- `ZIG_DOM_COMPAT_DEBUG`
- `ZIG_DOM_STRICT_SPEC_ERRORS`
- `ZIG_DOM_TRACE_MUTATIONS`

Validation:
- Only gate code that is measurably hot or noisy.
- Keep default behavior spec-compatible unless an explicit fast mode is requested.

## 5. Experiment with bundled bytecode for JS wrappers

Bun bytecode caching can reduce startup/import cost by avoiding repeated parse and compile work. `zig-dom` has a nontrivial JS wrapper layer imported by test preloads.

Experiment:
- Bundle the JS wrapper entrypoints for Bun.
- Generate `.jsc` bytecode as part of the build.
- Compare cold import time and full `../youneedawiki` `test-dom` wall time.

Notes:
- Bytecode is tied to Bun versions and should be regenerated, not hand-maintained.
- This is more likely to improve startup than hot DOM operations.

## 6. Revisit selector cache strategy after profiling

Selector matching is important in React tests, and `zig-dom` already caches parsed selectors. Bun utilities such as native hashing may or may not beat plain `Map<string, ...>`.

Validation:
- Profile selector parse/cache churn before changing anything.
- Benchmark repeated selectors from Testing Library queries, not only synthetic selector loops.

## Preferred Order

1. `Bun.escapeHTML()` serialization experiment.
2. Profile `../youneedawiki` `test-dom` and identify top `zig-dom` hot paths.
3. Bulk native serialization/text operations if profiling supports it.
4. Bun-native primitive delegation where compatibility is straightforward.
5. Bytecode/bundled wrapper startup experiment.
6. Selector cache tuning only if profiling points there.

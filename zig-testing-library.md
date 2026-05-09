Agent handoff: Zig-native Testing Library

## Goal

Replace the runner's dependency on upstream `@testing-library/dom` and
`@testing-library/react` with Zig-owned built-in modules that expose compatible
APIs for this repo's React and DOM test workflows.

Keep the implementation inside the existing Zig runner/runtime. Do not add a
new JS wrapper package or reintroduce `js/wrappers`.

## Current Shape

- `package.json` still lists `@testing-library/dom` and
  `@testing-library/react` as dev dependencies.
- Existing tests already exercise the desired surface:
  - `tests/runner/testing-library-role.test.js`
  - `tests/runner/native-dom-testing-library-smoke.test.jsx`
  - `tests/integration/react/*.tsx`
- Module loading has a built-in-module path in `src/runner/execution.zig`:
  - `loadNativeBuiltInModule`
  - `builtInModuleSource`
  - `exportApiMembersAsModule`
- `bun:test` is already implemented as a native built-in module by exporting a
  global API object from Zig.
- DOM behavior is implemented in `src/dom/*.zig`; selectors, attributes, events,
  focus, form values, and React 18 smoke tests already exist.

## Target Architecture

Use parser-level import stripping as the fast path, backed by Zig-owned global
API objects and native built-in modules.

For test transforms only, rewrite known Testing Library imports:

```ts
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
```

to lexical bindings from the Zig-owned API:

```ts
const { cleanup, fireEvent, render, screen, waitFor, within } = globalThis.__zigTestingLibraryReact;
```

Preserve aliases:

```ts
import { render as rtlRender } from '@testing-library/react';
```

becomes:

```ts
const { render: rtlRender } = globalThis.__zigTestingLibraryReact;
```

Only bind names that were explicitly imported by the file. Do not inject all
Testing Library names into every test module.

Also add two native built-in modules as the fallback/resolution layer:

- `@testing-library/dom`
- `@testing-library/react`

Install their API objects on `globalThis` during test runtime setup, then export
those objects through `loadNativeBuiltInModule`, matching the current
`bun:test` pattern.

Suggested files:

- `src/host/testing_library_dom.zig`
- `src/host/testing_library_react.zig`
- `src/runner/execution.zig`
- `src/runner/yuku_transform.zig` or the import-rewrite layer used by test
  transforms
- `src/host/runner.zig` or the existing host install path that initializes
  `expect`, mocks, and DOM cleanup

Use Zig C callbacks for query and event entrypoints where behavior benefits
from direct DOM access or consistent error formatting. It is acceptable to use
small embedded JS helper strings only for glue, especially for React's
`createRoot`/`act` integration.

## Downstream Surface

`../youneedawiki` currently imports a small Testing Library surface from
`@testing-library/react`:

- `screen`
- `render`
- `fireEvent`
- `waitFor`
- `within`
- `renderHook`
- `cleanup`
- `waitForElementToBeRemoved`

Treat these as first-class compatibility targets. `renderHook`, `waitFor`, and
`waitForElementToBeRemoved` are required before using
`../youneedawiki node --run test-dom` as a serious gate.

`@testing-library/user-event` is present in `youneedawiki/src/test-utils`, but
that helper already wraps the common fast paths with `fireEvent`. Leave
`user-event` out of this pass unless the React Testing Library surface is green
and downstream still needs it.

## Milestone 1: Import Rewrite Skeleton

1. Add a test-transform rewrite for named imports from:
   - `@testing-library/dom`
   - `@testing-library/react`

2. Rewrite only static named imports. Keep namespace, default, side-effect, and
   dynamic imports on the built-in-module fallback path until they are needed.

3. Preserve local aliases and type-only imports. Runtime import stripping must
   not remove type-only information before the TS/TSX transform has consumed it.

4. Rewritten imports should bind to:
   - `globalThis.__zigTestingLibraryDom`
   - `globalThis.__zigTestingLibraryReact`

5. Add regression tests for:
   - simple named imports
   - aliased imports
   - unused imported names being harmless
   - no `node_modules/@testing-library/*` read for stripped imports

Acceptance:

```sh
bun run test native-dom-testing-library-smoke testing-library-role
```

## Milestone 2: Built-In Module Fallback

1. Add specifier constants in `src/runner/execution.zig`:
   - `testing_library_dom_specifier = "@testing-library/dom"`
   - `testing_library_react_specifier = "@testing-library/react"`

2. Extend `loadNativeBuiltInModule` to create modules for both specifiers.

3. Extend `builtInModuleSource` so static import graph collection treats both
   modules as built-ins.

4. Export a small initial API:
   - DOM: `screen`, `within`, `queries`, `getByText`, `queryByText`,
     `getByTestId`, `queryByTestId`, `fireEvent`, `cleanup`, `waitFor`,
     `waitForElementToBeRemoved`
   - React: re-export DOM APIs plus `render` and `renderHook`

5. Add a regression proving fallback imports resolve without reading
   `node_modules`.
   Start with a focused test file under `tests/runner/`.

Acceptance:

```sh
bun run test native-dom-testing-library-smoke
```

## Milestone 3: DOM Query Core

Implement a shared query engine in `testing_library_dom.zig`.

Required query families for parity with current tests and common app usage:

- `*ByText`
- `*ByTestId`
- `*ByLabelText`
- `*ByRole`
- `*ByDisplayValue`
- `*ByPlaceholderText`
- `*ByTitle`
- `*ByAltText`

For each family, implement:

- `queryBy*`
- `queryAllBy*`
- `getBy*`
- `getAllBy*`
- `findBy*`
- `findAllBy*`

Keep async `findBy*` simple at first: return a resolved or rejected Promise.
Add polling later only if downstream tests require it.

Use Testing Library's observable semantics:

- `queryBy*` returns `null` when there is no match and throws on multiple.
- `getBy*` throws on zero or multiple.
- `queryAllBy*` returns an array.
- `getAllBy*` throws on zero.
- Error messages should include the query type and useful DOM text, but do not
  chase exact upstream wording in the first pass.

Matching rules:

- Accept string, RegExp, and function matchers.
- Support `{ exact: false }` for string text matching.
- Support `{ selector }` for text queries.
- Default `testIdAttribute` to `data-testid`.

Implementation notes:

- Prefer DOM APIs already present: `querySelectorAll`, `matches`, `textContent`,
  attributes, form `value`, and labels.
- For traversal, start with `container.querySelectorAll("*")`; include the
  container itself when it is an element and can match.
- Keep query logic independent from React.

Acceptance:

```sh
bun run test testing-library-role native-dom-testing-library-smoke
```

## Milestone 4: Role Queries and Accessible Names

Implement enough accessibility semantics for app tests without pulling in
`aria-query`.

Start with:

- Explicit `role` attribute.
- Implicit roles:
  - `a[href]` -> `link`
  - `button` -> `button`
  - `img[alt]` -> `img`
  - `input` text/search/url/tel/email/password without `list` -> `textbox`
  - `textarea` -> `textbox`
  - `select` -> `combobox`
  - `option` -> `option`
  - `form` with accessible name -> `form`
  - `nav` -> `navigation`
  - `main` -> `main`
  - `aside` -> `complementary`
  - `ul`/`ol` -> `list`
  - `li` -> `listitem`
  - headings `h1`-`h6` -> `heading` with `level`

Accessible name order for the first pass:

1. `aria-label`
2. `aria-labelledby`
3. associated `<label>`
4. `alt` for images
5. text content
6. `title`

Support common `getByRole` options:

- `name`
- `hidden`
- `selected`
- `checked`
- `pressed`
- `expanded`
- `level`

Hidden filtering:

- Exclude `[hidden]`, `aria-hidden="true"`, and inline `display: none` /
  `visibility: hidden` unless `{ hidden: true }`.

Acceptance:

```sh
bun run test testing-library-role
```

## Milestone 5: Async Helpers

Implement the async helpers used by `youneedawiki`:

- `waitFor(callback, options)`
- `waitForElementToBeRemoved(callbackOrElement, options)`
- `findBy*`
- `findAllBy*`

Behavior:

- Poll until the callback stops throwing, returns a truthy value, or the timeout
  expires.
- Support at least `timeout` and `interval`; default to Testing Library-like
  values, but keep short intervals such as `{ interval: 1 }` working.
- Flush pending Promise jobs between polling attempts.
- `waitForElementToBeRemoved` should accept a callback returning an element,
  array, `null`, or `undefined`.

Acceptance:

```sh
bun run test Search Tree Page OrderedListChecklistMacro
```

## Milestone 6: Events and fireEvent

Implement `fireEvent` in Zig as a callable object with methods.

Base API:

- `fireEvent(node, event)`
- `fireEvent.click`
- `fireEvent.input`
- `fireEvent.change`
- `fireEvent.keyDown`
- `fireEvent.keyUp`
- `fireEvent.submit`
- `fireEvent.focus`
- `fireEvent.blur`
- `fireEvent.compositionStart`
- `fireEvent.compositionUpdate`
- `fireEvent.compositionEnd`

Behavior:

- Construct native `Event`, `MouseEvent`, `KeyboardEvent`, `InputEvent`, or
  `CompositionEvent` where available.
- Copy init payload fields such as `bubbles`, `cancelable`, `data`, `key`,
  `code`, `button`, and modifier keys.
- For `change` and `input`, apply `target.value` / `target.checked` before
  dispatch when supplied.
- Default bubbling should match Testing Library expectations for each event.

Acceptance:

```sh
bun run test events native-dom-events native-dom-testing-library-smoke
```

## Milestone 7: React render and renderHook

Implement `@testing-library/react` as a thin layer over the DOM module and
installed `react-dom/client`.

`render(ui, options)` should:

- Create a `div` container when `options.container` is absent.
- Append the container to `document.body` when needed.
- Use `ReactDOM.createRoot(container).render(ui)`.
- Return:
  - `container`
  - `baseElement`
  - `debug`
  - `unmount`
  - `rerender`
  - bound query functions from `within(baseElement)`

Also export:

- `screen`
- `within`
- `fireEvent`
- `cleanup`
- `waitFor`
- `waitForElementToBeRemoved`
- `renderHook`
- `act` when available from React/ReactDOM

Cleanup:

- Track mounted roots in module state.
- `cleanup()` unmounts every root and removes auto-created containers.
- Keep the existing runner after-each DOM cleanup, but ensure Testing Library
  cleanup runs before body reset so React roots can unmount normally.

`renderHook(callback, options)` can start as a small React component that stores
the latest callback result and returns `{ result, rerender, unmount }`. Support
`options.wrapper`, since `youneedawiki` uses wrapper providers.

Acceptance:

```sh
bun run test native-dom-testing-library-smoke render events hooks forms
```

## Milestone 8: Remove Upstream Dependency

After the built-ins pass repo coverage:

1. Remove `@testing-library/dom` and `@testing-library/react` from
   `package.json`.
2. Run install/update so the lockfile no longer pulls those packages.
3. Keep React and ReactDOM dependencies.
4. Add a test that imports both Testing Library modules while `node_modules`
   lacks those packages.

Acceptance:

```sh
bun run test testing-library native-dom-testing-library-smoke
bun run test:perf
node --run test
```

## Milestone 9: Downstream Verification

Use the real consumer suite before calling this done.

```sh
../youneedawiki node --run test-dom
```

If downstream exposes missing Testing Library APIs, add them in the Zig modules
instead of restoring upstream dependencies or adding test-specific hacks.

## Non-Goals

- Do not implement `@testing-library/user-event` in this pass.
- Do not strip arbitrary package imports.
- Do not require exact upstream error text.
- Do not implement the full ARIA spec before app coverage needs it.
- Do not replace React itself.
- Do not add wrapper-era JS package entrypoints.

## Work Loop

1. Add the smallest failing test for one API group.
2. Add or extend the import rewrite only when the API object already exists.
3. Verify with `bun run test <target>`.
4. Run `bun run test:perf` after query traversal or module-loader changes.
5. Run `node --run test` before handoff.
6. Run `../youneedawiki node --run test-dom` before removing upstream packages.

Keep each milestone independently reviewable. If a query needs a broader DOM
primitive, fix the DOM primitive in `src/dom/*.zig` and add DOM coverage for it
before depending on it from Testing Library.

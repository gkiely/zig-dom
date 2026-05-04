# zig-dom

A Bun-only DOM implementation backed by Zig, with a JavaScript surface that is intentionally close to `happy-dom`.

`zig-dom` is for tests, tools, experiments, and server-side DOM work where you want a real DOM-like API inside Bun without launching a browser. It ships a prebuilt native library and TypeScript declarations in the npm package.

## Install

```sh
bun add zig-dom
```

## Requirements

- Bun
- macOS for the currently published native binary

This package is not a browser polyfill for Node.js yet. The current npm package includes `dist/native/libzig_dom.dylib`, so Linux and Windows support will need platform-specific native builds.

## Usage

Create an isolated window:

```ts
import { Window } from "zig-dom";

const window = new Window({ url: "http://localhost/" });
const { document } = window;

document.body.innerHTML = `
  <main>
    <button id="save">Save</button>
  </main>
`;

const button = document.querySelector("#save");
button?.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

window.close();
```

Register DOM globals for tests:

```ts
import { GlobalRegistrator } from "zig-dom/global-registrator";

GlobalRegistrator.register({
  url: "http://localhost:3000",
  width: 1024,
  height: 768
});
```

That installs globals such as `window`, `document`, `HTMLElement`, `Event`, `MutationObserver`, `localStorage`, `customElements`, `location`, `fetch`, `FormData`, and timer APIs on `globalThis`.

Clean up when a test suite is done:

```ts
import { GlobalRegistrator } from "zig-dom/global-registrator";

GlobalRegistrator.unregister();
```

## Exports

```ts
import {
  Window,
  Document,
  Element,
  HTMLElement,
  Event,
  CustomEvent,
  MouseEvent,
  MutationObserver,
  Range,
  Selection,
  Storage,
  Browser
} from "zig-dom";
```

`Browser`, `BrowserContext`, and `Page` are lightweight happy-dom-style helpers for code that expects that shape.

## Development

Install dependencies:

```sh
bun install
```

Build the native library and JavaScript output:

```sh
bun run build
```

Run the fast verification suite:

```sh
bun run verify:fast
```

Run the default test suite:

```sh
bun test
```

Run selected WPT subsets:

```sh
bun run test:wpt:dom
bun run test:wpt:expanded
```

## Status

This is early software. The goal is a fast Bun-native DOM with broad enough compatibility for React tests, Testing Library workflows, and meaningful Web Platform Test coverage. Some browser APIs are incomplete, and behavior may change quickly while the implementation fills out.

## License

No license has been added yet.

# zig-dom

Bun-only Zig-backed DOM implementation with a `happy-dom`-compatible surface.

## Install

| Bun | npm |
| --- | --- |
| `bun add zig-dom` | `npm install zig-dom` |

The current package ships a macOS native library. Linux and Windows builds are not published yet.

## React Test Setup

Use a Bun preload file, similar to `react-ts-template`:

```ts
// preload.ts
import { GlobalRegistrator } from "zig-dom/global-registrator";
import * as matchers from "@testing-library/jest-dom/matchers";
import { afterEach, expect } from "bun:test";

GlobalRegistrator.register();
expect.extend(matchers);

const { cleanup } = await import("@testing-library/react");
afterEach(() => cleanup());
```

Then run tests with:

```sh
bun test --preload ./preload.ts
```

## Direct Usage

```ts
import { Window } from "zig-dom";

const window = new Window({ url: "http://localhost/" });
window.document.body.innerHTML = "<button>Save</button>";

console.log(window.document.querySelector("button")?.textContent);

window.close();
```

## Development

```sh
bun install
bun run build
bun run verify:fast
```

## Status

Early and incomplete, but already useful for Bun-based React and DOM tests.

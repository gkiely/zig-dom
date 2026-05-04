# zig-dom

Bun-only Zig-backed DOM implementation with a `happy-dom`-compatible surface.

## Install

| Bun | npm |
| --- | --- |
| `bun add zig-dom` | `npm install zig-dom` |

The current package ships a macOS native library. Linux and Windows builds are not published yet.

## Direct Usage

Use `Window` directly when you want an isolated DOM:

```ts
import { Window } from "zig-dom";

const window = new Window({ url: "http://localhost/" });
window.document.body.innerHTML = "<button>Save</button>";

console.log(window.document.querySelector("button")?.textContent);

window.close();
```

## Test Setup

Create a Bun preload file:

```ts
// preload.ts
import { GlobalRegistrator } from "zig-dom/global-registrator";

GlobalRegistrator.register();
```

| bunfig.toml | CLI fallback |
| --- | --- |
| <pre lang="toml">[test]<br>preload = ["./preload.ts"]</pre> | <pre lang="sh">bun test --preload ./preload.ts</pre> |

| Vanilla JS | React |
| --- | --- |
| <pre lang="ts">import { test, expect } from "bun:test";<br><br>test("updates the document", () => {<br>  document.body.innerHTML = "&lt;button&gt;Save&lt;/button&gt;";<br>  expect(document.querySelector("button")?.textContent).toBe("Save");<br>});</pre> | <pre lang="tsx">import { render, screen } from "@testing-library/react";<br>import { test, expect } from "bun:test";<br><br>test("renders", () => {<br>  render(&lt;button&gt;Save&lt;/button&gt;);<br>  expect(screen.getByRole("button").textContent).toBe("Save");<br>});</pre> |

## Development

```sh
bun install
bun run build
bun run verify:fast
```

## Status

Early and incomplete, but already useful for Bun-based React and DOM tests.

# zig-dom

Bun-only Zig-backed DOM implementation with a `happy-dom`-compatible surface.

## Install

### Bun

```sh
bun add zig-dom
```

### npm

```sh
npm install zig-dom
```

## Test Setup

Create a Bun preload file:

```ts
// preload.ts
import { GlobalRegistrator } from "zig-dom/global-registrator";

GlobalRegistrator.register();
```

### bunfig.toml

```toml
[test]
preload = ["./preload.ts"]
```

### CLI

```sh
bun test --preload ./preload.ts
```

### Vanilla JS

```ts
import { test, expect } from "bun:test";

test("updates the document", () => {
  document.body.innerHTML = "<button>Save</button>";
  expect(document.querySelector("button")?.textContent).toBe("Save");
});
```

### React

```tsx
import { render, screen } from "@testing-library/react";
import { test, expect } from "bun:test";

test("renders", () => {
  render(<button>Save</button>);
  expect(screen.getByRole("button").textContent).toBe("Save");
});
```

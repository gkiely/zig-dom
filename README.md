# zig-dom

A Zig-backed DOM implementation.

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

## Benchmarks

Run with:

```sh
bun run benchmark:dom
```

Latest local run: 2026-05-04 15:03:55 UTC on `darwin-arm64`, after `bun run build`.

| Metric | zig-dom | happy-dom | jsdom | vs happy-dom |
| --- | ---: | ---: | ---: | --- |
| Append 10k children | 0.74 ms | 3.99 ms | 8.94 ms | zig-dom is 5.4x faster |
| Create 10k elements | 1.92 ms | 3.36 ms | 6.45 ms | zig-dom is 1.8x faster |
| Query `.class` across 10k nodes | 1.52 ms | 13.45 ms | 14.33 ms | zig-dom is 8.9x faster |
| Query `[attr]` across 10k nodes | 1.38 ms | 5.87 ms | 12.09 ms | zig-dom is 4.2x faster |
| Parse `innerHTML` | 0.42 ms | 11.68 ms | 23.97 ms | zig-dom is 28.0x faster |
| Serialize `outerHTML` | 0.21 ms | 2.42 ms | 2.78 ms | zig-dom is 11.8x faster |
| Mixed DOM workflow, 1k ops | 2.36 ms | 8.05 ms | 10.45 ms | zig-dom is 3.4x faster |
| Mutation observer append, 1k nodes | 1.50 ms | 1.75 ms | 4.34 ms | zig-dom is 1.2x faster |
| React render, 10k rows | 46.58 ms | 97.46 ms | 124.01 ms | zig-dom is 2.1x faster |
| React update, 10k rows | 28.70 ms | 37.25 ms | 49.66 ms | zig-dom is 1.3x faster |
| Import time | 44.22 ms | 75.58 ms | 420.75 ms | zig-dom is 1.7x faster |

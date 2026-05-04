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

Latest local run: 2026-05-04 13:35:24 UTC on `darwin-arm64`, after `bun run build`.

| Metric | zig-dom | happy-dom | jsdom | vs happy-dom |
| --- | ---: | ---: | ---: | --- |
| Append 10k children | 0.94 ms | 3.05 ms | 8.75 ms | zig-dom: 3.2x faster |
| Create 10k elements | 2.31 ms | 3.13 ms | 8.83 ms | zig-dom: 1.4x faster |
| Query `.class` across 10k nodes | 1.49 ms | 15.45 ms | 18.90 ms | zig-dom: 10.4x faster |
| Query `[attr]` across 10k nodes | 1.38 ms | 6.53 ms | 12.44 ms | zig-dom: 4.7x faster |
| Parse `innerHTML` | 0.51 ms | 17.94 ms | 24.79 ms | zig-dom: 35.1x faster |
| Serialize `outerHTML` | 0.13 ms | 2.23 ms | 2.11 ms | zig-dom: 16.9x faster |
| Mixed DOM workflow, 1k ops | 2.44 ms | 8.80 ms | 10.87 ms | zig-dom: 3.6x faster |
| Mutation observer append, 1k nodes | 1.51 ms | 1.62 ms | 4.26 ms | zig-dom: 1.1x faster |
| React render, 10k rows | 48.14 ms | 86.25 ms | 125.68 ms | zig-dom: 1.8x faster |
| React update, 10k rows | 30.45 ms | 41.30 ms | 48.42 ms | zig-dom: 1.4x faster |
| Import time | 40.83 ms | 68.19 ms | 447.44 ms | zig-dom: 1.7x faster |

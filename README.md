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

Latest local run: 2026-05-04 15:06:41 UTC on `darwin-arm64`.

| Metric | zig-dom | happy-dom | jsdom | vs happy-dom |
| --- | ---: | ---: | ---: | --- |
| Append 10k children | 0.84 ms | 3.23 ms | 9.59 ms | zig-dom is 3.8x faster |
| Create 10k elements | 2.14 ms | 4.13 ms | 7.96 ms | zig-dom is 1.9x faster |
| Query `.class` across 10k nodes | 1.52 ms | 13.70 ms | 18.09 ms | zig-dom is 9.0x faster |
| Query `[attr]` across 10k nodes | 1.41 ms | 6.08 ms | 13.44 ms | zig-dom is 4.3x faster |
| Parse `innerHTML` | 0.44 ms | 10.31 ms | 25.38 ms | zig-dom is 23.4x faster |
| Serialize `outerHTML` | 0.22 ms | 2.07 ms | 1.96 ms | zig-dom is 9.3x faster |
| Mixed DOM workflow, 10k ops | 22.26 ms | 71.75 ms | 114.08 ms | zig-dom is 3.2x faster |
| Mutation observer append, 10k nodes | 11.82 ms | 15.02 ms | 33.35 ms | zig-dom is 1.3x faster |
| React render, 10k rows | 45.02 ms | 105.69 ms | 135.57 ms | zig-dom is 2.3x faster |
| React update, 10k rows | 29.48 ms | 37.47 ms | 49.60 ms | zig-dom is 1.3x faster |
| Import time | 38.05 ms | 55.54 ms | 393.83 ms | zig-dom is 1.5x faster |

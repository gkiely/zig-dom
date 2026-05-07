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

## Development Commands

Use the package scripts for local development validation:

```sh
bun run build:dev
bun run build:dev <test-file-token>
bun run build:perf
bun run build:perf <test-file-token>
```

Current status:

- `test` command discovers test files in Zig, transforms TS/JSX as needed, and executes through the embedded QuickJS-ng runtime.
- Runner collection and execution are split phases with support for nested `describe`, hooks, `skip`, and `only`.
- `wpt`, `wpt-sync`, and `wpt-manifest` bridge to existing scripts under `scripts/`.
- The runtime abstraction files were added in `src/runtime/` for upcoming QuickJS embedding work.

## Perf Build (Edit.test.tsx)

Milestone work should run the ReleaseFast guard for `../youneedawiki/src/elements/Buttons/Edit.test.tsx`.

```sh
bun run build:perf
```

The helper script builds with ReleaseFast first, then runs two timed test invocations so build time is not included in runtime timing.

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

Latest local run: 2026-05-04 21:20:08 UTC on `darwin-arm64`.

| Metric | zig-dom | happy-dom | jsdom | vs happy-dom |
| --- | ---: | ---: | ---: | --- |
| Append 10k children | 0.89 ms | 3.30 ms | 8.55 ms | zig-dom is 3.7x faster |
| Create 10k elements | 2.35 ms | 3.38 ms | 7.30 ms | zig-dom is 1.4x faster |
| Query `.class` across 10k nodes | 1.58 ms | 13.98 ms | 18.45 ms | zig-dom is 8.8x faster |
| Query `[attr]` across 10k nodes | 1.32 ms | 7.01 ms | 15.06 ms | zig-dom is 5.3x faster |
| Parse `innerHTML` | 0.44 ms | 11.54 ms | 25.03 ms | zig-dom is 26.0x faster |
| Serialize `outerHTML` | 0.13 ms | 1.88 ms | 2.06 ms | zig-dom is 14.7x faster |
| Mixed DOM workflow, 10k ops | 20.70 ms | 76.69 ms | 116.29 ms | zig-dom is 3.7x faster |
| Mutation observer append, 10k nodes | 11.01 ms | 16.42 ms | 36.68 ms | zig-dom is 1.5x faster |
| React render, 10k rows | 48.92 ms | 103.81 ms | 132.10 ms | zig-dom is 2.1x faster |
| React update, 10k rows | 39.03 ms | 39.38 ms | 53.39 ms | zig-dom is 1.0x faster |
| Import time | 29.94 ms | 68.86 ms | 491.57 ms | zig-dom is 2.3x faster |

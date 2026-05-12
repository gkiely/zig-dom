# zig-dom

A Zig-backed native DOM implementation with a built-in test runner.

## Development

```sh
bun run test basic.test
bun run test tests/runner/basic.test.ts
bun run test --root ../youneedawiki-zig-dom src/components/Tree/Tree.test.tsx
bun run test:perf --root ../youneedawiki-zig-dom src/components/Tree/Tree.test.tsx
```

Sample a command on macOS:

```sh
bun run sample -- zig-out/bin/zig-dom test --root ../youneedawiki-zig-dom src/components/Tree/Tree.test.tsx
```

The `test` command runs JavaScript, TypeScript, JSX, and TSX tests through the embedded QuickJS-ng runtime. DOM support can be enabled for all files with `--dom`, is enabled automatically for `.jsx` and `.tsx`, or can be customized with suffixes:

```sh
bun run test tests/runner --dom
bun run test tests/runner --dom=.vue,.jsx,.tsx
```

## WPT

Native WPT support is driven by generated manifests under `wpt/manifest`.

```sh
bun run test:wpt
```

To refresh upstream WPT inputs directly:

```sh
bun run scripts/sync-wpt.ts
bun run scripts/generate-wpt-manifest.ts
```

## Layout

- `src/dom`: native DOM implementation and public DOM API.
- `src/host`: host assertions, mocks, platform glue, and runner bridge.
- `src/runner`: CLI, transform, test discovery, and execution.
- `src/runtime.zig`, `src/quickjs_ng.zig`, `src/value.zig`, `src/main.zig`: runtime entrypoints and shared QuickJS bindings.

import { expect, test } from 'bun:test';

test('tmp dynamic import resolves', async () => {
  const module = await import('./package.json');
  expect(module.default.name).toBe('zig-dom');
});

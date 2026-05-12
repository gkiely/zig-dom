import { expect, test } from 'bun:test';

let cached: unknown = null;
let promise: Promise<void> | null = null;

const load = async () => {
  if (!promise) {
    promise = import('./package.json').then((module) => {
      cached = module.default;
    });
  }
  await promise;
  if (!cached) throw new Error('missing cache');
};

test('tmp dynamic import then resolves before await continuation', async () => {
  await load();
  expect((cached as { name: string }).name).toBe('zig-dom');
});

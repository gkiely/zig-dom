import { expect, test } from 'bun:test';

test('module namespace mutability', async () => {
  const ns = await import('./tmp-ns-target');
  let assignOk = true;
  try {
    // @ts-ignore
    ns.value = 2;
  } catch {
    assignOk = false;
  }
  expect(assignOk).toBe(true);
  expect(ns.value).toBe(2);
  expect(ns.fn()).toBe(2);
});

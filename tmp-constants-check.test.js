import { expect, test } from 'bun:test';
import { LEGACY, MODERN, isBun } from '../youneedawiki/src/utils/constants';

test('constants under zig runner', () => {
  console.log('flags', { isBun, LEGACY, MODERN, viteLegacy: import.meta.env.VITE_LEGACY });
  expect(isBun).toBe(true);
});

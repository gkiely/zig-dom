import { expect, test } from 'bun:test';
import { isBun } from '../youneedawiki/src/utils/constants';

test('isBun flag in zig runner', () => {
  expect(typeof Bun).toBe('object');
  expect(isBun).toBe(true);
});

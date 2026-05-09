import { expect, test } from 'bun:test';

test('setting window.location.href updates location pathname and search', () => {
  window.location.href = 'http://localhost/app/page/1/2?tab=abc#hash';
  expect(window.location.pathname).toBe('/app/page/1/2');
  expect(location.pathname).toBe('/app/page/1/2');
  expect(window.location.search).toBe('?tab=abc');
  expect(location.search).toBe('?tab=abc');
  expect(window.location.hash).toBe('#hash');
  expect(location.hash).toBe('#hash');
});

import { expect, test } from 'bun:test';

test('gapi token default scope', () => {
  const token = gapi.client.getToken();
  console.log('token scope', token?.scope);
  expect(typeof token?.scope).toBe('string');
});

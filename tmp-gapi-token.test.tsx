import { expect, test } from 'bun:test';

test('gapi token scope is not drive.file by default', () => {
  const token = gapi.client.getToken();
  expect(token?.scope.includes('https://www.googleapis.com/auth/drive.file')).toBe(false);
  expect(token?.scope.includes('https://www.googleapis.com/auth/drive')).toBe(true);
});

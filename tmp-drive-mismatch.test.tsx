import { expect, test } from 'bun:test';
import { mockDriveRequest } from '../youneedawiki/src/utils/test-utils';
import { get } from '../youneedawiki/src/utils/DriveAPI';

test('show mismatch logs', async () => {
  mockDriveRequest('https://www.googleapis.com/drive/v3/files/999', { id: '999' } as any);
  let failed = false;
  try {
    await get({ id: '0' });
  } catch {
    failed = true;
  }
  expect(failed).toBe(true);
});

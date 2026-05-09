import { expect, test } from 'bun:test';
import { mockDriveRequest } from '../youneedawiki/src/utils/test-utils';
import type { DriveFile } from '../youneedawiki/shared/DriveTypes';
import { get } from '../youneedawiki/src/utils/DriveAPI';

test('mockDriveRequest intercepts DriveAPI.get', async () => {
  const wiki = {
    id: '0',
    name: 'A folder',
    mimeType: 'application/vnd.google-apps.folder',
  } as DriveFile;

  mockDriveRequest(`https://www.googleapis.com/drive/v3/files/${wiki.id}`, wiki);

  const result = await get({ id: wiki.id });
  expect(result.id).toBe(wiki.id);
});

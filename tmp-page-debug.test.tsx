import { mimeTypes } from '../youneedawiki/shared/constants';
import type { DriveFile } from '../youneedawiki/shared/DriveTypes';
import { mockFetch } from '../youneedawiki/shared/test-utils';
import { render, screen, waitFor } from '@testing-library/react';
import { expect, spyOn, test } from 'bun:test';
import { wrapper } from '../youneedawiki/src/utils/test-utils';

const Page = await import('../youneedawiki/src/components/Page/Page').then((m) => m.default);

test('debug Page calls', async () => {
  const wiki = {
    id: '0',
    name: 'A folder',
    mimeType: 'application/vnd.google-apps.folder',
  } as DriveFile;
  const file = {
    id: '1',
    name: 'A file',
    parents: ['0'],
    mimeType: mimeTypes.document,
    modifiedTime: new Date().toISOString(),
  } as DriveFile;

  const calls: string[] = [];
  mockFetch('/api/user/me', null);
  spyOn(gapi.client, 'request').mockImplementation((args: any) => {
    calls.push(args.path);
    if (args.path === 'https://www.googleapis.com/drive/v3/files') {
      return {
        getPromise: () => Promise.resolve({ result: { files: [file] } }),
      } as never;
    }
    if (args.path === `https://www.googleapis.com/drive/v3/files/${file.id}`) {
      return {
        getPromise: () => Promise.resolve({ result: file }),
      } as never;
    }
    if (args.path === `https://www.googleapis.com/drive/v3/files/${wiki.id}`) {
      return {
        getPromise: () => Promise.resolve({ result: wiki }),
      } as never;
    }
    if (args.path === `https://www.googleapis.com/drive/v3/files/${file.id}/export`) {
      return {
        getPromise: () => Promise.resolve({ body: '<p>content</p>', result: { body: '' } }),
      } as never;
    }
    return {
      getPromise: () => Promise.reject(new Error(`Unhandled: ${args.path}`)),
    } as never;
  });

  render(<Page wikiId={wiki.id} id={file.id} />, { wrapper });

  await waitFor(() => {
    expect(screen.getByText('content')).toBeInTheDocument();
  });

  console.log('calls', calls);
});

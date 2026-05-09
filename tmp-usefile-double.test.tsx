import { expect, spyOn, test } from 'bun:test';
import React from 'react';
import { render, waitFor } from '@testing-library/react';
import type { DriveFile } from '../youneedawiki/shared/DriveTypes';
import { useFile } from '../youneedawiki/src/utils/hooks/hooks';
import { mockDriveRequest, wrapper } from '../youneedawiki/src/utils/test-utils';

function Probe() {
  const a = useFile('0', [], '0');
  const b = useFile('0', [], '0');
  if (a.data && b.data) {
    return React.createElement('div', { id: 'ready' });
  }
  return React.createElement('div', { id: 'pending' });
}

test('duplicate useFile key dedupes requests', async () => {
  const wiki = {
    id: '0',
    name: 'A folder',
    mimeType: 'application/vnd.google-apps.folder',
  } as DriveFile;

  const req = spyOn(gapi.client, 'request');
  mockDriveRequest(`https://www.googleapis.com/drive/v3/files/${wiki.id}`, wiki);

  render(React.createElement(Probe), { wrapper });

  await waitFor(() => {
    expect(document.getElementById('ready')).toBeInTheDocument();
  });

  expect(req.mock.calls.length).toBe(1);
});

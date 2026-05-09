import { mimeTypes } from '@/shared/constants';
import { type DriveFile } from '@/shared/DriveTypes';
import { fireEvent, render, screen } from '@testing-library/react';
import { expect, spyOn, test } from 'bun:test';
import { mockModule } from '~/test-utils/mockModule';
import { useStore } from '~/utils/store';
import { delay } from '~/utils/utils';

const wiki = {
  id: 'wiki-1',
  name: 'Test Wiki',
  mimeType: mimeTypes.folder,
  capabilities: { canEdit: true },
  properties: { showInlineEditing: 'true' },
} as DriveFile;

const page = {
  id: 'page-1',
  name: 'Test Page',
  mimeType: mimeTypes.document,
  parents: [wiki.id],
  capabilities: { canEdit: true },
  webViewLink: 'https://docs.google.com/document/d/page-1/edit',
} as DriveFile;

const user = { email: 'test@example.com', paid: true };
const hooks = await import('~/utils/hooks/hooks');
const { Header } = await import('../youneedawiki/src/components/Header/Header');

test('debug header inline edit view flow', async () => {
  const fetchSpy = spyOn(global, 'fetch').mockResolvedValue(new Response());
  useStore.setState({ theme: 'light', themeMode: 'light' });

  using _ = await mockModule('~/utils/hooks/hooks', () => ({
    ...hooks,
    useWikis: () => ({ data: [wiki] }),
    useFiles: () => ({ data: [page] }),
    useFile: (id: string) => ({ data: id === wiki.id ? wiki : page }),
    useAuth: () => ({ anonymous: false, data: user }),
  }));

  render(<Header wikiId={wiki.id} id={page.id} />);

  const editButton = screen.getByTitle('Edit (e)');
  fireEvent.click(editButton);
  await delay();

  const viewButton = screen.getByTitle('View (e)');
  fireEvent.click(viewButton);

  console.log('call-count', fetchSpy.mock.calls.length);
  for (const [i, call] of fetchSpy.mock.calls.entries()) {
    console.log('call', i + 1, call[0], call[1]);
  }

  const [url, options] = fetchSpy.mock.lastCall ?? [];
  console.log('last', url, options);

  expect(true).toBe(true);
});

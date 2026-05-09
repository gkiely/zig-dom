import { mimeTypes } from '@/shared/constants';
import { type DriveFile } from '@/shared/DriveTypes';
import { fireEvent, render, screen } from '@testing-library/react';
import { expect, it, spyOn } from 'bun:test';
import { usePopupState } from 'material-ui-popup-state/hooks';
import { AddNewButton } from '~/elements/Buttons/AddNew';
import { type MockDriveRequest } from '~/utils/types';
import { AddMenuLegacy } from '~/components/AddMenuLegacy/AddMenuLegacy';
import { AddModalLegacy } from '~/components/AddMenuLegacy/AddModalLegacy';

const Wrapper = () => {
  const popupState = usePopupState({ variant: 'popper' });
  const modalState = usePopupState({ variant: 'dialog' });
  const file = { parents: ['1'] } as DriveFile;
  return (
    <>
      <AddNewButton file={file} popupState={popupState} wiki={{} as DriveFile} />
      <AddMenuLegacy popupState={popupState} wiki={{} as DriveFile} file={{} as DriveFile} modalState={modalState} />
      <AddModalLegacy file={{ parents: ['1'] } as DriveFile} modalState={modalState} />
    </>
  );
};

it('debug add menu legacy request calls', () => {
  (spyOn(gapi.client, 'request') as MockDriveRequest<'List'>).mockReturnValueOnce({
    getPromise: () => Promise.resolve({ result: { files: [] } }),
  });

  window.location.href = 'http://localhost/app/page/1/2';
  render(<Wrapper />);
  const button = screen.getByRole('button');
  fireEvent.click(button);
  const menuItem = screen.getByRole('menuitem', { name: /document/i });
  fireEvent.click(menuItem);
  const input = screen.getByRole('textbox');
  fireEvent.change(input, { target: { value: 'Test Page' } });

  const spy = spyOn(gapi.client, 'request');
  spy.mockReturnValueOnce({
    getPromise: () => Promise.resolve({ result: { id: '1' } }),
  } as never);

  const createButton = screen.getByRole('button', { name: /create/i });
  fireEvent.click(createButton);

  console.log('calls.length', spy.mock.calls.length);
  for (let i = 0; i < spy.mock.calls.length; i++) {
    const call = spy.mock.calls[i] as [unknown];
    console.log('call', i + 1, JSON.stringify(call?.[0]));
  }

  expect(spy.mock.calls.length).toBeTruthy();
  expect(spy).toHaveBeenNthCalledWith(
    2,
    expect.objectContaining({
      path: 'https://www.googleapis.com/drive/v3/files',
      method: 'POST',
      body: {
        name: 'Test Page',
        mimeType: mimeTypes.document,
        parents: ['1'],
      },
    })
  );
});

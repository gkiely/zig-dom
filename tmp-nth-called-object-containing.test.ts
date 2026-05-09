import { expect, spyOn, test } from 'bun:test';

test('re-spy keeps call history and matches nested objectContaining on nth call', () => {
  const api = {
    request(args: unknown) {
      return {
        getPromise: async () => ({ result: args }),
      };
    },
  };

  const first = spyOn(api, 'request');
  first.mockReturnValueOnce({ getPromise: async () => ({ result: { files: [] } }) } as never);

  api.request({
    path: 'https://www.googleapis.com/drive/v3/files',
    method: 'GET',
  });

  const second = spyOn(api, 'request');
  second.mockReturnValueOnce({ getPromise: async () => ({ result: { id: '1' } }) } as never);

  api.request({
    path: 'https://www.googleapis.com/drive/v3/files',
    method: 'POST',
    body: {
      name: 'Test Page',
      mimeType: 'application/vnd.google-apps.document',
      parents: ['1'],
    },
  });

  expect(first).toBe(second);
  expect(second).toHaveBeenNthCalledWith(
    2,
    expect.objectContaining({
      path: 'https://www.googleapis.com/drive/v3/files',
      method: 'POST',
      body: {
        name: 'Test Page',
        mimeType: 'application/vnd.google-apps.document',
        parents: ['1'],
      },
    })
  );
});

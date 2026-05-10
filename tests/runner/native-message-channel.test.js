test('MessageChannel delivers posted messages asynchronously', async () => {
  const channel = new MessageChannel();
  const seen = [];

  channel.port1.onmessage = (event) => {
    seen.push(event.data);
  };

  channel.port2.postMessage('scheduled');
  expect(seen).toEqual([]);

  await Promise.resolve();
  expect(seen).toEqual(['scheduled']);
});

test('MessageChannel is linked on window', () => {
  expect(window.MessageChannel).toBe(MessageChannel);
});

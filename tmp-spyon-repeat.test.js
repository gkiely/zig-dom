import { expect, spyOn, test } from 'bun:test';

test('repeated spyOn queues implementationOnce on same mock', () => {
  const obj = {
    fn: () => 'orig',
  };

  const first = spyOn(obj, 'fn');
  first.mockImplementationOnce(() => 'one');

  const second = spyOn(obj, 'fn');
  second.mockImplementationOnce(() => 'two');

  expect(first).toBe(second);
  expect(obj.fn()).toBe('one');
  expect(obj.fn()).toBe('two');
  expect(obj.fn()).toBe('orig');
});

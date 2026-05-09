import React from 'react';
import { expect, spyOn, test } from 'bun:test';
import { fireEvent, render, screen } from '@testing-library/react';

test('react onSubmit fires when clicking submit button', () => {
  const handler = spyOn({ fn: () => {} }, 'fn');

  render(
    <form
      onSubmit={(event) => {
        event.preventDefault();
        handler();
      }}
    >
      <input name="title" defaultValue="hello" />
      <button type="submit">Create</button>
    </form>
  );

  fireEvent.click(screen.getByRole('button', { name: /create/i }));

  expect(handler).toHaveBeenCalledTimes(1);
});

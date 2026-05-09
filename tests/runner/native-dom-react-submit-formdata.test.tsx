import { expect, test } from 'bun:test';
import { fireEvent, render, screen } from '@testing-library/react';

test('React submit handler runs for submit button click and can read FormData(form)', () => {
  let submitCount = 0;
  let submittedValue: FormDataEntryValue | null = null;

  render(
    <form
      onSubmit={(event) => {
        event.preventDefault();
        const data = new FormData(event.currentTarget);
        submittedValue = data.get('title');
        submitCount += 1;
      }}
    >
      <input name="title" defaultValue="Untitled" />
      <button type="submit">Create</button>
    </form>
  );

  const input = screen.getByRole('textbox');
  fireEvent.change(input, { target: { value: 'Test Page' } });
  fireEvent.click(screen.getByRole('button', { name: /create/i }));

  expect(submitCount).toBe(1);
  expect(submittedValue).toBe('Test Page');
});

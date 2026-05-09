import { expect, test } from 'bun:test';
import { fireEvent, render, screen } from '@testing-library/react';
import { createPortal } from 'react-dom';

test('submit events from a portal form reach React onSubmit handlers', () => {
  let submitCount = 0;
  let submittedValue: FormDataEntryValue | null = null;

  const PortalForm = () =>
    createPortal(
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
      </form>,
      document.body
    );

  render(<PortalForm />);

  const createButton = screen.getByRole('button', { name: /create/i });
  fireEvent.click(createButton);

  expect(submitCount).toBe(1);
  expect(submittedValue).toBe('Untitled');
});

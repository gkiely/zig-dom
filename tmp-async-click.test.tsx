import { fireEvent, render, screen } from '@testing-library/react';
import { expect, test } from 'bun:test';
import { useState } from 'react';

function AsyncClick() {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        onClick={async () => {
          await import('./package.json');
          setOpen(true);
        }}
      >
        Open
      </button>
      {open ? <div role="dialog">Loaded</div> : null}
    </>
  );
}

test('tmp async click state update resolves', async () => {
  render(<AsyncClick />);
  fireEvent.click(screen.getByText('Open'));
  expect(await screen.findByRole('dialog')).toBeInTheDocument();
});

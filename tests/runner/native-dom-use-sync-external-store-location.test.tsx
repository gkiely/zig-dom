import { expect, test } from 'bun:test';
import { render, screen } from '@testing-library/react';
import { useSyncExternalStore } from 'react';

const usePathnameSnapshot = () =>
  useSyncExternalStore(
    () => () => {},
    () => location.pathname,
    () => location.pathname
  );

const PathProbe = () => {
  const path = usePathnameSnapshot();
  return <div data-testid="path-probe" data-path={path} />;
};

test('useSyncExternalStore reads current location pathname after href assignment', () => {
  window.location.href = 'http://localhost/app/page/1/2';
  expect(location.pathname).toBe('/app/page/1/2');

  render(<PathProbe />);
  const probe = screen.getByTestId('path-probe');
  expect(probe.getAttribute('data-path')).toBe('/app/page/1/2');
});

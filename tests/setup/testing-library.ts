import { afterEach, expect } from "bun:test";

if (process.env.ZIG_DOM_SKIP_TESTING_LIBRARY !== "1") {
  const { cleanup } = await import("@testing-library/react");
  const matchers = await import("@testing-library/jest-dom/matchers");

  expect.extend(matchers);

  afterEach(() => {
    cleanup();
    const maybeWindow = globalThis.window as unknown as { happyDOM?: { reset: () => void } } | undefined;
    maybeWindow?.happyDOM?.reset?.();
  });
}

import { afterEach, expect } from "bun:test";
import { cleanup } from "@testing-library/react";
import * as matchers from "@testing-library/jest-dom/matchers";

expect.extend(matchers);

afterEach(() => {
  cleanup();
  const maybeWindow = globalThis.window as unknown as { happyDOM?: { reset: () => void } } | undefined;
  maybeWindow?.happyDOM?.reset?.();
});

import { expect, test } from "bun:test";

const setupGlobal = globalThis as typeof globalThis & {
  __zigAutoRootPreload?: boolean;
};

if (setupGlobal.__zigAutoRootPreload === true) {
  throw new Error("bunfig preload should not run unless --root is provided");
}

test("bunfig preload is opt-in via --root", () => {
  expect(setupGlobal.__zigAutoRootPreload).toBe(undefined);
});

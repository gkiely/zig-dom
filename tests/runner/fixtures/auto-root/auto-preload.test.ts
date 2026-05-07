import { expect, test } from "bun:test";

const setupGlobal = globalThis as typeof globalThis & {
  __zigAutoRootPreload?: boolean;
};

if (setupGlobal.__zigAutoRootPreload !== true) {
  throw new Error("auto bunfig preload did not run before collection");
}

test("auto bunfig preload executes when --root is provided", () => {
  expect(setupGlobal.__zigAutoRootPreload).toBe(true);
});

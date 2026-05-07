import { expect, test } from "bun:test";

const setupGlobal = globalThis as typeof globalThis & {
  __zigSetupToken?: string;
  __zigSetupExpectExtended?: boolean;
};

if (setupGlobal.__zigSetupToken !== "setup-ready") {
  throw new Error("setup global missing before module collection");
}

test("setup files install globals before module collection", () => {
  expect(setupGlobal.__zigSetupToken).toBe("setup-ready");
});

test("setup files can extend expect", () => {
  expect(setupGlobal.__zigSetupExpectExtended).toBe(true);
  (expect("HELLO") as any).toBeUppercase();
  expect(() => (expect("Hello") as any).toBeUppercase()).toThrow();
});

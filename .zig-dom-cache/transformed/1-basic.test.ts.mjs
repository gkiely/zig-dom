import { expect, test } from "bun:test";
test("zig CLI runner ts smoke", () => {
  const value = 40 + 2;
  expect(value).toBe(42);
});

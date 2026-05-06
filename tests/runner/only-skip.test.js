import { expect, test } from "bun:test";

test.skip("a", () => {
  throw new Error("skip callback must not run");
});

test("b", () => {
  throw new Error("non-only callback must not run when an only test exists");
});

test.only("c", () => {
  expect(2 + 2).toBe(4);
});

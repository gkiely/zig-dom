import { expect, test } from "bun:test";

test("tsx auto mode installs web globals", () => {
  const doc = (globalThis as any)["doc" + "ument"];
  expect(typeof doc.createElement).toBe("function");
});

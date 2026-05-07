import { expect, test } from "bun:test";

test("plain ts auto mode skips web globals", () => {
  expect((globalThis as any)["doc" + "ument"]).toBe(undefined);
});

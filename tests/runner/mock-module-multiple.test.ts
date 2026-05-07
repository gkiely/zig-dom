import { expect, test } from "bun:test";
import "./fixtures/setup/mock-module-multiple.ts";

test("mock.module keeps multiple module overrides from setup", async () => {
  const one = await import("virtual-multiple-one");
  const two = await import("virtual-multiple-two");

  expect(one.default).toBe("one-default");
  expect(one.one).toBe(1);
  expect(two.default).toBe("two-default");
  expect(two.two).toBe(2);
});

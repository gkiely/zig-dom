import "./fixtures/setup/mock-module-async.ts";
import { expect, test } from "bun:test";

test("mock.module supports async module override factories", async () => {
  const overridden = await import("virtual-async-target");
  expect(overridden.default).toBe("async-default");
  expect(overridden.namedValue).toBe(23);
});

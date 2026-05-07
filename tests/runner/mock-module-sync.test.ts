import "./fixtures/setup/mock-module-sync.ts";
import { expect, test } from "bun:test";

test("mock.module supports sync module override factories", async () => {
  const overridden = await import("virtual-sync-target");
  expect(overridden.default).toBe("sync-default");
  expect(overridden.namedValue).toBe(17);
});

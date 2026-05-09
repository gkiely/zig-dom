import { expect, mock, test } from "bun:test";
import { currentValue, readValue } from "./fixtures/modules/mock-module-live-target";

test("mock.module patches exports of already imported modules", async () => {
  expect(currentValue).toBe("original");
  expect(readValue()).toBe("original");

  await mock.module("./fixtures/modules/mock-module-live-target", () => ({
    currentValue: "patched",
    readValue: () => "patched",
  }));

  expect(currentValue).toBe("patched");
  expect(readValue()).toBe("patched");

  const reimported = await import("./fixtures/modules/mock-module-live-target");
  expect(reimported.currentValue).toBe("patched");
  expect(reimported.readValue()).toBe("patched");
});

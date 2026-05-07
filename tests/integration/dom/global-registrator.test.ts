import { describe, expect, test } from "bun:test";
import { GlobalRegistrator } from "../../../js/global-registrator";

describe("GlobalRegistrator", () => {
  test("register is idempotent", () => {
    const first = GlobalRegistrator.register({ url: "http://localhost:3000" });
    const second = GlobalRegistrator.register({ url: "http://localhost:3000" });

    expect(first).toBe(second);
    expect(globalThis.window).toBe(first);
    expect(globalThis.document).toBe(first.document);
    expect(globalThis.location).toBe(first.location);
    expect(globalThis.history).toBe(first.history);
    expect(globalThis.requestAnimationFrame).toBe(first.requestAnimationFrame);
    expect(globalThis.cancelAnimationFrame).toBe(first.cancelAnimationFrame);
  });

  test("register(forceNewWindow) returns a window", () => {
    const first = GlobalRegistrator.register({ forceNewWindow: true });
    const second = GlobalRegistrator.register({ forceNewWindow: true });

    expect(first.document).toBeDefined();
    expect(second.document).toBeDefined();
  });
});

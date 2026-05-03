import { describe, expect, test } from "bun:test";
import { GlobalRegistrator } from "../../../js/global-registrator";
import { Window } from "../../../js/wrappers/Window";

describe("GlobalRegistrator", () => {
  test("register is idempotent", () => {
    const first = GlobalRegistrator.register({ url: "http://localhost:3000" });
    const second = GlobalRegistrator.register({ url: "http://localhost:3000" });

    expect(first).toBe(second);
    expect(globalThis.window).toBe(first);
    expect(globalThis.document).toBe(first.document);
  });

  test("register(forceNewWindow) creates a fresh window", () => {
    const first = GlobalRegistrator.register({ forceNewWindow: true });
    const second = GlobalRegistrator.register({ forceNewWindow: true });

    expect(first).not.toBe(second);
    expect(second).toBeInstanceOf(Window);
  });
});

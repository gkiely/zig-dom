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
    expect(globalThis.location).toBe(first.location);
    expect(globalThis.history).toBe(first.history);
    expect(globalThis.EventTarget).toBe(first.EventTarget);
    expect(globalThis.UIEvent).toBe(first.UIEvent);
    expect(globalThis.FocusEvent).toBe(first.FocusEvent);
    expect(globalThis.WheelEvent).toBe(first.WheelEvent);
    expect(globalThis.DOMParser).toBe(first.DOMParser);
    expect(globalThis.URL).toBe(first.URL);
    expect(globalThis.URLSearchParams).toBe(URLSearchParams);
    expect(globalThis.AbortController).toBe(first.AbortController);
    expect(globalThis.AbortSignal).toBe(first.AbortSignal);
    expect(globalThis.requestAnimationFrame).toBe(first.requestAnimationFrame);
    expect(globalThis.cancelAnimationFrame).toBe(first.cancelAnimationFrame);
    expect(globalThis.queueMicrotask).toBe(first.queueMicrotask);
    expect(globalThis.performance).toBe(first.performance);
    expect(typeof globalThis.performance.measure).toBe("function");
  });

  test("register(forceNewWindow) creates a fresh window", () => {
    const first = GlobalRegistrator.register({ forceNewWindow: true });
    const second = GlobalRegistrator.register({ forceNewWindow: true });

    expect(first).not.toBe(second);
    expect(second).toBeInstanceOf(Window);
  });
});

import { describe, expect, test } from "bun:test";

describe("mutation observer compatibility", () => {
  test("MutationObserver can be constructed and used as a no-op observer", () => {
    let callbackCalls = 0;
    const observer = new window.MutationObserver(() => {
      callbackCalls += 1;
    });

    observer.observe(document.body, { childList: true, subtree: true });
    document.body.appendChild(document.createElement("div"));

    expect(callbackCalls).toBe(0);
    expect(observer.takeRecords()).toEqual([]);

    observer.disconnect();
    expect(observer.takeRecords()).toEqual([]);
  });
});

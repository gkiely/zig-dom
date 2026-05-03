import { describe, expect, test } from "bun:test";

describe("mutation observer compatibility", () => {
  test("queues childList records and delivers them asynchronously", async () => {
    let callbackCalls = 0;
    let deliveredRecords = 0;
    const observer = new window.MutationObserver((records) => {
      callbackCalls += 1;
      deliveredRecords += records.length;
    });

    observer.observe(document.body, { childList: true });
    document.body.appendChild(document.createElement("div"));

    await Promise.resolve();
    expect(callbackCalls).toBe(1);
    expect(deliveredRecords).toBe(1);
    expect(observer.takeRecords()).toEqual([]);
    observer.disconnect();
  });

  test("records attribute and characterData changes with oldValue options", () => {
    const target = document.createElement("div");
    const text = document.createTextNode("before");
    target.appendChild(text);

    const observer = new window.MutationObserver(() => undefined);
    observer.observe(target, {
      attributes: true,
      attributeOldValue: true,
      characterData: true,
      characterDataOldValue: true,
      subtree: true
    });

    target.setAttribute("data-state", "ready");
    text.textContent = "after";

    const records = observer.takeRecords();
    expect(records.length).toBe(2);
    expect(records[0]?.type).toBe("attributes");
    expect(records[0]?.attributeName).toBe("data-state");
    expect(records[0]?.oldValue).toBeNull();
    expect(records[1]?.type).toBe("characterData");
    expect(records[1]?.oldValue).toBe("before");
  });
});

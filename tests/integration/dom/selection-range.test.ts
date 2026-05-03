import { describe, expect, test } from "bun:test";

describe("selection and range compatibility", () => {
  test("document.createRange and document.getSelection interoperate", () => {
    const container = document.createElement("div");
    container.innerHTML = "<span>One</span><span>Two</span>";
    document.body.appendChild(container);

    const range = document.createRange();
    range.selectNodeContents(container);

    const selection = document.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    expect(selection.rangeCount).toBe(1);
    expect(selection.getRangeAt(0)).toBe(range);
    expect(range.collapsed).toBe(false);

    selection.removeAllRanges();
    expect(selection.rangeCount).toBe(0);
  });
});

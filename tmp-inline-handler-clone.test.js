import { test, expect } from "bun:test";

test("clone preserves inline oninput handler", () => {
  document.body.innerHTML = "<input id='a' oninput='globalThis.__inlineHit = (globalThis.__inlineHit || 0) + 1'>";
  globalThis.__inlineHit = 0;
  const input = document.getElementById("a");
  const clone = input.cloneNode(true);

  expect(typeof clone.oninput).toBe("function");

  clone.dispatchEvent(new Event("input", { bubbles: true }));
  expect(globalThis.__inlineHit).toBe(1);
});

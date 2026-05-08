import { test, expect } from "bun:test";

test("inline handler this binding", () => {
  document.body.innerHTML = "<input id='x' type='checkbox' oninput='globalThis.__thisChecked = this && this.checked ? 1 : 0'>";
  const x = document.getElementById("x");
  const clone = x.cloneNode(true);
  clone.checked = true;
  globalThis.__thisChecked = -1;
  clone.dispatchEvent(new Event("input", { bubbles: true }));
  expect(globalThis.__thisChecked).toBe(1);
});

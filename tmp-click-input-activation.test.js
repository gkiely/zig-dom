import { test, expect } from "bun:test";

test("checkbox click fires input handler", () => {
  document.body.innerHTML = "<input id='c' type='checkbox' oninput='globalThis.__clickInputHit = (globalThis.__clickInputHit || 0) + 1'>";
  globalThis.__clickInputHit = 0;
  const checkbox = document.getElementById("c");
  checkbox.click();
  expect(globalThis.__clickInputHit).toBe(1);
});

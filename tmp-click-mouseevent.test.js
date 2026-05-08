import { test, expect } from "bun:test";

test("element.click dispatches MouseEvent", () => {
  document.body.innerHTML = "<button id='b' onclick='globalThis.__isMouse = (event instanceof MouseEvent)'></button>";
  globalThis.__isMouse = false;
  const b = document.getElementById("b");
  b.click();
  expect(globalThis.__isMouse).toBe(true);
});

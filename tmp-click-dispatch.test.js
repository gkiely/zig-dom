import { test, expect } from "bun:test";

test("click dispatch details", () => {
  document.body.innerHTML = "<button id='b'></button>";
  const b = document.getElementById("b");
  let clicked = 0;
  let isMouse = false;
  b.addEventListener("click", (event) => {
    clicked += 1;
    isMouse = event instanceof MouseEvent;
  });
  b.click();
  expect(clicked).toBe(1);
  expect(isMouse).toBe(true);
});

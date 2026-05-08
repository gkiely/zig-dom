import { test, expect } from "bun:test";

test("classList add/contains", () => {
  document.body.innerHTML = "<input id='x' class='activates'>";
  const x = document.getElementById("x");
  x.classList.add("test0");
  expect(x.classList.contains("test0")).toBe(true);
  expect(x.className.includes("test0")).toBe(true);
});

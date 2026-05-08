import { test, expect } from "bun:test";

test("mouseevent-instanceof", () => {
  const mouse = new MouseEvent("click", { bubbles: true, cancelable: true });
  const ev = new Event("click");
  expect(mouse instanceof MouseEvent).toBe(true);
  expect(mouse instanceof Event).toBe(true);
  expect(ev instanceof Event).toBe(true);
});

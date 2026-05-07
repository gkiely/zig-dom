import { expect, test } from "bun:test";

test("native DOM window and global constructors", () => {
  expect(window).toBe(self);
  expect(window.document).toBe(document);
  expect(globalThis.window).toBe(window);

  expect(typeof HTMLElement).toBe("function");
  expect(typeof SVGElement).toBe("function");
  expect(typeof DOMRect).toBe("function");
  expect(window.HTMLElement).toBe(HTMLElement);

  const rect = new DOMRect(1, 2, 3, 4);
  expect(rect.x).toBe(1);
  expect(rect.y).toBe(2);
  expect(rect.width).toBe(3);
  expect(rect.height).toBe(4);

  const element = document.createElement("div");
  const box = element.getBoundingClientRect();
  expect(box.width).toBe(0);

  const observer = new MutationObserver(() => {});
  expect(typeof observer.observe).toBe("function");

  const resize = new ResizeObserver(() => {});
  expect(typeof resize.observe).toBe("function");
});

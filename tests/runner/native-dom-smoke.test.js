import { expect, test } from "bun:test";

test("native DOM globals smoke", () => {
  expect(window.document).toBe(document);

  const root = document.createElement("div");
  const child = document.createElement("span");
  child.textContent = "hello";

  root.appendChild(child);
  root.appendChild(new Text(" world"));

  expect(root.textContent).toBe("hello world");
  expect(root instanceof Node).toBe(true);
  expect(child instanceof Element).toBe(true);
});

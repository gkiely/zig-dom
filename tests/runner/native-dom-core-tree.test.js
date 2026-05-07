import { expect, test } from "bun:test";

test("native DOM core tree navigation and mutation", () => {
  const root = document.createElement("div");
  const first = document.createElement("section");
  const middle = document.createElement("article");
  const last = document.createElement("footer");

  expect(root.parentNode).toBe(null);
  expect(root.firstChild).toBe(null);
  expect(root.lastChild).toBe(null);

  root.appendChild(first);
  root.appendChild(last);
  root.insertBefore(middle, last);

  expect(root.firstChild).toBe(first);
  expect(root.lastChild).toBe(last);
  expect(first.nextSibling).toBe(middle);
  expect(last.previousSibling).toBe(middle);
  expect(middle.parentNode).toBe(root);
  expect(middle.parentElement).toBe(root);
  expect(middle.ownerDocument).toBe(document);

  expect(middle.isConnected).toBe(false);
  document.body.appendChild(root);
  expect(middle.isConnected).toBe(true);

  expect(root.nodeType).toBe(Node.ELEMENT_NODE);
  expect(root.nodeName).toBe("DIV");
  expect(root.nodeValue).toBe(null);

  const text = document.createTextNode("abc");
  expect(text.nodeType).toBe(Node.TEXT_NODE);
  expect(text.nodeName).toBe("#text");
  expect(text.nodeValue).toBe("abc");
  text.nodeValue = "xyz";
  expect(text.textContent).toBe("xyz");

  expect(root.contains(middle)).toBe(true);
  expect(middle.contains(root)).toBe(false);

  const replacement = document.createElement("aside");
  const removed = root.replaceChild(replacement, middle);
  expect(removed).toBe(middle);
  expect(replacement.previousSibling).toBe(first);
  expect(replacement.nextSibling).toBe(last);

  const removedFirst = root.removeChild(first);
  expect(removedFirst).toBe(first);
  expect(first.parentNode).toBe(null);

  const deepClone = root.cloneNode(true);
  expect(deepClone.nodeName).toBe("DIV");
  expect(deepClone.firstChild.nodeName).toBe("ASIDE");
  expect(deepClone.lastChild.nodeName).toBe("FOOTER");

  const shallowClone = root.cloneNode(false);
  expect(shallowClone.firstChild).toBe(null);
});

import { expect, test } from "bun:test";

test("native DOM document creation APIs", () => {
  const body = document.body;
  const root = document.documentElement;
  const head = document.head;
  const plain = document.createElement("section");
  const namespaced = document.createElementNS("urn:test", "svg");
  const implementation = document.implementation;
  const text = document.createTextNode("hello");
  const comment = document.createComment("note");
  const doctype = document.createDocumentType("html", "", "");
  const fragment = document.createDocumentFragment();
  fragment.appendChild(text);
  fragment.appendChild(comment);
  expect(Boolean(body)).toBe(true);
  expect(Boolean(head)).toBe(true);
  expect(Boolean(implementation)).toBe(true);
  expect(root.localName).toBe("html");
  expect(plain.localName).toBe("section");
  expect(namespaced.localName).toBe("svg");
  expect(doctype.nodeType).toBe(Node.DOCUMENT_TYPE_NODE);
  expect(doctype.nodeName).toBe("html");
  expect(fragment.childNodes.length).toBe(2);
});

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

test("native DOM wraps span and list element constructors", () => {
  const host = document.createElement("div");
  host.innerHTML = "<ol><li><span>One</span></li></ol><ul><li>Two</li></ul>";

  const ol = host.querySelector("ol");
  const ul = host.querySelector("ul");
  const li = host.querySelector("li");
  const span = host.querySelector("span");

  expect(ol instanceof HTMLOListElement).toBe(true);
  expect(ul instanceof HTMLUListElement).toBe(true);
  expect(li instanceof HTMLLIElement).toBe(true);
  expect(span instanceof HTMLSpanElement).toBe(true);

  expect(document.createElement("ol") instanceof HTMLOListElement).toBe(true);
  expect(document.createElement("ul") instanceof HTMLUListElement).toBe(true);
  expect(document.createElement("li") instanceof HTMLLIElement).toBe(true);
  expect(document.createElement("span") instanceof HTMLSpanElement).toBe(true);
});

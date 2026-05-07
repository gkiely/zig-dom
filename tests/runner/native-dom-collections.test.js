import { expect, test } from "bun:test";

test("native DOM collections and sibling element traversal", () => {
  const root = document.createElement("div");
  const first = document.createElement("p");
  const second = document.createElement("span");
  const trailingText = document.createTextNode("tail");

  first.id = "first";
  second.id = "second";

  root.appendChild(document.createTextNode("head"));
  root.appendChild(first);
  root.appendChild(second);
  root.appendChild(trailingText);

  expect(root.childNodes.length).toBe(4);
  expect(root.childNodes.item(0).nodeType).toBe(Node.TEXT_NODE);
  expect(root.childNodes[1]).toBe(first);
  expect(root.childNodes[2]).toBe(second);

  const nodeNames = [
    root.childNodes.item(0).nodeName,
    root.childNodes.item(1).nodeName,
    root.childNodes.item(2).nodeName,
    root.childNodes.item(3).nodeName
  ];
  expect(nodeNames).toEqual(["#text", "p", "span", "#text"]);

  expect(root.children.length).toBe(2);
  expect(root.children.item(0)).toBe(first);
  expect(root.children.item(1)).toBe(second);
  expect(root.children[0]).toBe(first);
  expect(root.children[1]).toBe(second);

  expect(root.firstElementChild).toBe(first);
  expect(root.lastElementChild).toBe(second);
  expect(first.previousElementSibling).toBe(null);
  expect(first.nextElementSibling).toBe(second);
  expect(second.previousElementSibling).toBe(first);
  expect(second.nextElementSibling).toBe(null);
  expect(root.childElementCount).toBe(2);

  const childIds = [root.children.item(0).id, root.children.item(1).id];
  expect(childIds).toEqual(["first", "second"]);
});

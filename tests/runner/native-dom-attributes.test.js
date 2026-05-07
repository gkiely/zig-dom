import { expect, test } from "bun:test";

test("native DOM element attributes and class/dataset reflection", () => {
  const element = document.createElement("div");

  expect(element.tagName).toBe("DIV");
  expect(element.localName).toBe("div");

  element.id = "root";
  element.className = "alpha";
  expect(element.getAttribute("id")).toBe("root");
  expect(element.getAttribute("class")).toBe("alpha");

  element.classList.add("beta");
  expect(element.classList.contains("alpha")).toBe(true);
  expect(element.classList.contains("beta")).toBe(true);

  element.classList.remove("alpha");
  expect(element.className).toBe("beta");

  expect(element.toggleAttribute("hidden")).toBe(true);
  expect(element.hasAttribute("hidden")).toBe(true);
  expect(element.toggleAttribute("hidden")).toBe(false);
  expect(element.hasAttribute("hidden")).toBe(false);

  element.setAttribute("data-user-id", "42");
  element.dataset.displayName = "Ada";

  expect(element.getAttribute("data-user-id")).toBe("42");
  expect(element.dataset.userId).toBe("42");
  expect(element.getAttribute("data-display-name")).toBe("Ada");

  delete element.dataset.userId;
  expect(element.hasAttribute("data-user-id")).toBe(false);

  const names = element.getAttributeNames().slice().sort();
  expect(names).toEqual(["class", "data-display-name", "id"]);

  element.removeAttribute("data-display-name");
  expect(element.getAttribute("data-display-name")).toBe(null);
});

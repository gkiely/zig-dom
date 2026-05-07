import { expect, test } from "bun:test";
import { screen } from "@testing-library/dom";
import { elementRoles } from "aria-query";

test("testing-library can find implicit link roles", () => {
  document.body.innerHTML = '<a href="https://example.test/"><span>Example</span></a>';
  const link = document.querySelector("a");
  expect(link.matches('a[href]:not([href=""])')).toBe(true);
  expect(Array.from(elementRoles).some(([concept, roles]) => concept.name === "a" && Array.from(roles).includes("link"))).toBe(true);
  expect(screen.getByRole("link").getAttribute("href")).toBe("https://example.test/");
});

test("testing-library can find implicit img roles", () => {
  document.body.innerHTML = '<img alt="icon" src="/icon.png">';
  expect(document.querySelector("img").matches('img[alt]:not([alt=""])')).toBe(true);
  expect(screen.getByRole("img").getAttribute("src")).toBe("/icon.png");
});

test("testing-library can find explicit menu role in modal-like markup", () => {
  document.body.innerHTML =
    '<div aria-hidden="true"><button>Add new</button></div>' +
    '<div role="presentation"><div><ul role="menu" tabindex="-1"><li role="menuitem">Document</li></ul></div></div>';

  expect(screen.getByRole("menu").getAttribute("tabindex")).toBe("-1");
  expect(screen.getByRole("menuitem", { name: /document/i }).textContent).toBe("Document");
});

test("testing-library can find implicit textbox from unlabeled text input", () => {
  document.body.innerHTML = '<input aria-label="Share url" value="http://localhost/app/page/wiki-0/page-1">';

  const input = document.querySelector("input");
  expect(input.matches("input:not([list])")).toBe(true);
  const textbox = screen.getByRole("textbox", { name: /share url/i });
  expect(textbox.getAttribute("value")).toBe("http://localhost/app/page/wiki-0/page-1");
});

test("testing-library can find explicit complementary role", () => {
  document.body.innerHTML = '<aside class="outline" role="complementary"><nav class="outlineNav"></nav></aside>';
  expect(screen.getByRole("complementary").getAttribute("role")).toBe("complementary");
});

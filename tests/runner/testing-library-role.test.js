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

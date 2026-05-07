import { expect, test } from "bun:test";
import { screen } from "@testing-library/dom";

test("element ownerDocument exposes defaultView", () => {
  const element = document.createElement("a");
  document.body.appendChild(element);

  expect(document.defaultView).toBe(window);
  expect(element.ownerDocument).toBe(document);
  expect(element.ownerDocument.defaultView).toBe(window);
  expect(typeof element.ownerDocument.defaultView.getComputedStyle).toBe("function");
});

test("parsed elements expose ownerDocument defaultView", () => {
  const div = document.createElement("div");
  div.innerHTML = '<a href="https://youneedawiki.com"><img src="/icon.svg" alt="You Need A Wiki"><span>Powered by You Need A Wiki</span></a>';
  document.body.appendChild(div);

  const link = div.querySelector("a");
  expect(link.ownerDocument).toBe(document);
  expect(link.ownerDocument.defaultView).toBe(window);
  expect(link.querySelector("img").ownerDocument).toBe(document);
  expect(link.querySelector("span").ownerDocument).toBe(document);
  expect(screen.getByRole("link")).toBe(link);
});

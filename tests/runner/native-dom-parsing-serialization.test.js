import { expect, test } from "bun:test";

test("native DOM parsing and serialization APIs", () => {
  const host = document.createElement("div");
  host.innerHTML = "<span>alpha</span><br>";
  expect(host.childNodes.length).toBe(2);
  expect(host.innerHTML).toBe("<span>alpha</span><br>");

  const holder = document.createElement("div");
  holder.innerHTML = "<b>one</b>";
  holder.firstChild.insertAdjacentHTML("afterend", "<i>two</i>");
  expect(holder.childNodes.length).toBe(2);
  expect(holder.childNodes.item(1).localName).toBe("i");

  const fragment = document.createDocumentFragment();
  fragment.innerHTML = "<em>x</em><!--y-->";
  expect(fragment.childNodes.length).toBe(2);

  const doctype = document.createDocumentType("html", "", "");
  expect(doctype.outerHTML).toBe("<!DOCTYPE html>");
});

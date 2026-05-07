import { expect, test } from "bun:test";

test("native DOM querying APIs", () => {
  const host = document.createElement("section");
  host.innerHTML = '<button id="save" class="primary">Save</button><div class="chip"></div>';
  document.body.appendChild(host);

  const button = document.querySelector("button");
  expect(button.localName).toBe("button");
  expect(document.getElementById("save")).toBe(button);
  expect(host.getElementsByTagName("button").length).toBe(1);
  expect(host.querySelectorAll("*").length).toBe(2);

  const link = document.createElement("a");
  link.setAttribute("href", "https://example.test/");
  host.appendChild(link);
  expect(link.matches("a[href]")).toBe(true);
  expect(link.matches('a[href]:not([href=""])')).toBe(true);
  expect(link.matches("button, a[href]")).toBe(true);
  expect(host.querySelectorAll('*[role~="link"],a,area').length).toBe(1);
});

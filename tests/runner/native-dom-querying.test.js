import { expect, test } from "bun:test";

test("native DOM querying APIs", () => {
  const host = document.createElement("section");
  host.innerHTML = '<button id="save" class="primary">Save</button><div class="chip"></div>';
  document.body.appendChild(host);

  const button = document.querySelector("button");
  expect(button.localName).toBe("button");
  expect(document.getElementById("save")).toBe(button);
  expect(host.getElementsByTagName("button").length).toBe(1);
});

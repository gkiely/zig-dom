import { test, expect } from "bun:test";

test("cloned checkbox activation inside radio parent", () => {
  document.body.innerHTML = `
    <template id='tpl'>
      <input id='child' class='click activates container' type='checkbox' oninput='globalThis.__hit = (globalThis.__hit || 0) + 1'>
      <input id='parent' class='click activates container' type='radio' oninput='globalThis.__parentHit = (globalThis.__parentHit || 0) + 1'>
    </template>
  `;
  globalThis.__hit = 0;
  globalThis.__parentHit = 0;

  const tpl = document.getElementById("tpl");
  const child = tpl.content.children[0].cloneNode(true);
  const parent = tpl.content.children[1].cloneNode(true);

  const host = document.createElement("div");
  document.body.appendChild(host);
  host.appendChild(parent);
  parent.appendChild(child);

  expect(typeof child.oninput).toBe("function");

  child.dispatchEvent(new Event("input", { bubbles: true }));
  expect(globalThis.__hit).toBe(1);
  globalThis.__hit = 0;

  child.click();

  expect(child.checked).toBe(true);
  expect(globalThis.__hit).toBe(1);
  expect(globalThis.__parentHit).toBe(0);
});

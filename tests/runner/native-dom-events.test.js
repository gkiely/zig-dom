import { expect, test } from "bun:test";

test("native DOM event basics", () => {
  const target = document.createElement("div");
  let called = 0;
  target.addEventListener("ping", () => {
    called += 1;
  });
  target.dispatchEvent(new Event("ping"));
  expect(called).toBe(1);
});

test("native DOM event options and payload", () => {
  const target = document.createElement("div");
  let onceCount = 0;

  const onOnce = () => {
    onceCount += 1;
  };

  target.addEventListener("once", onOnce, { once: true });
  target.dispatchEvent(new Event("once"));
  target.dispatchEvent(new Event("once"));
  expect(onceCount).toBe(1);

  target.addEventListener("off", onOnce);
  target.removeEventListener("off", onOnce);
  target.dispatchEvent(new Event("off"));
  expect(onceCount).toBe(1);

  const custom = new CustomEvent("custom", { detail: { ok: true } });
  expect(custom.detail.ok).toBe(true);

  const mouse = new MouseEvent("click", { bubbles: true, clientX: 7, clientY: 9 });
  expect(mouse.clientX).toBe(7);
  expect(mouse.clientY).toBe(9);
});

test("native DOM capture and bubble phases", () => {
  const root = document.createElement("div");
  const child = document.createElement("button");
  root.appendChild(child);
  document.body.appendChild(root);

  const seen = [];
  root.addEventListener(
    "tap",
    (event) => {
      seen.push("capture:" + event.eventPhase + ":" + (event.currentTarget === root));
    },
    { capture: true }
  );

  root.addEventListener("tap", (event) => {
    seen.push("bubble:" + event.eventPhase + ":" + (event.currentTarget === root));
  });

  child.addEventListener("tap", (event) => {
    seen.push("target:" + event.eventPhase + ":" + (event.target === child));
    event.preventDefault();
  });

  const ok = child.dispatchEvent(new Event("tap", { bubbles: true, cancelable: true }));
  expect(ok).toBe(false);
  expect(seen).toEqual([
    "capture:1:true",
    "target:2:true",
    "bubble:3:true"
  ]);
});

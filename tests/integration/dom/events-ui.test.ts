import { describe, expect, test } from "bun:test";

describe("event and ui-event parity", () => {
  test("supports listener options and listener objects", () => {
    const button = document.createElement("button");
    document.body.appendChild(button);

    let onceCalls = 0;
    const objectCalls: string[] = [];

    const listenerObject = {
      handleEvent(event: Event) {
        objectCalls.push(event.type);
      }
    };

    button.addEventListener("click", () => {
      onceCalls += 1;
    }, { once: true });
    button.addEventListener("click", listenerObject);

    button.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    button.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    button.removeEventListener("click", listenerObject);
    button.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    expect(onceCalls).toBe(1);
    expect(objectCalls.length).toBe(2);
  });

  test("composedPath returns target-to-root path", () => {
    const host = document.createElement("section");
    const child = document.createElement("button");
    host.appendChild(child);
    document.body.appendChild(host);

    const event = new MouseEvent("click", { bubbles: true, composed: true });
    child.dispatchEvent(event);

    const path = event.composedPath();
    expect(path[0]).toBe(child);
    expect(path.includes(host)).toBe(true);
    expect(path.includes(document.body)).toBe(true);
  });

  test("disabled submit button does not fire submit", () => {
    const form = document.createElement("form");
    const submit = document.createElement("button") as HTMLButtonElement;
    submit.type = "submit";
    submit.disabled = true;
    form.appendChild(submit);
    document.body.appendChild(form);

    let submitCalls = 0;
    form.addEventListener("submit", () => {
      submitCalls += 1;
    });

    submit.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(submitCalls).toBe(0);
  });

  test("MouseEvent exposes relatedTarget", () => {
    const target = document.createElement("div");
    const related = document.createElement("span");
    const event = new MouseEvent("mouseover", { relatedTarget: related });
    target.dispatchEvent(event);
    expect(event.relatedTarget).toBe(related);
  });
});

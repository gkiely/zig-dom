import { describe, expect, test } from "bun:test";

describe("native-backed tree mutation", () => {
  test("append, insert, replace, and remove maintain stable relationships", () => {
    const root = document.createElement("section");
    const first = document.createElement("div");
    const second = document.createElement("div");
    const replacement = document.createElement("article");

    root.appendChild(first);
    root.appendChild(second);
    root.insertBefore(replacement, second);

    expect(root.firstChild).toBe(first);
    expect(first.nextSibling).toBe(replacement);
    expect(replacement.nextSibling).toBe(second);

    root.replaceChild(document.createElement("span"), replacement);
    expect(root.childNodes.length).toBe(3);

    root.removeChild(second);
    expect(root.childNodes.length).toBe(2);
  });

  test("querySelector can find simple selectors", () => {
    const container = document.createElement("div");
    container.innerHTML = '<button class="primary" id="save">Save</button>';
    document.body.appendChild(container);

    const button = document.querySelector("button.primary");
    expect(button?.textContent).toBe("Save");
    expect(document.getElementById("save")).toBe(button);
  });
});

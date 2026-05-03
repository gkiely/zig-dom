import { describe, expect, test } from "bun:test";

describe("custom elements and shadow dom compatibility", () => {
  test("customElements define/get/whenDefined and createElement prototype upgrade", async () => {
    class FancyBoxElement extends HTMLElement {}

    const ready = customElements.whenDefined("fancy-box");
    customElements.define("fancy-box", FancyBoxElement);
    await ready;

    expect(customElements.get("fancy-box")).toBe(FancyBoxElement);

    const element = document.createElement("fancy-box");
    expect(element instanceof FancyBoxElement).toBe(true);
  });

  test("attachShadow supports open and closed modes", () => {
    const host = document.createElement("section") as HTMLElement;
    const openRoot = host.attachShadow({ mode: "open" });

    expect(host.shadowRoot).toBe(openRoot);

    openRoot.appendChild(document.createElement("span"));
    expect(openRoot.firstChild).not.toBeNull();

    const closedHost = document.createElement("article") as HTMLElement;
    closedHost.attachShadow({ mode: "closed" });
    expect(closedHost.shadowRoot).toBeNull();
  });
});

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

  test("custom element lifecycle callbacks fire for late upgrade and tree connection changes", () => {
    const lifecycleEvents: string[] = [];

    const beforeDefine = document.createElement("late-life-box") as HTMLElement;
    document.body.appendChild(beforeDefine);

    class LateLifecycleElement extends HTMLElement {
      static observedAttributes = ["data-state"];

      connectedCallback(): void {
        lifecycleEvents.push("connected");
      }

      disconnectedCallback(): void {
        lifecycleEvents.push("disconnected");
      }

      attributeChangedCallback(name: string, oldValue: string | null, newValue: string | null): void {
        lifecycleEvents.push(`attr:${name}:${oldValue ?? "null"}->${newValue ?? "null"}`);
      }
    }

    customElements.define("late-life-box", LateLifecycleElement);

    expect(beforeDefine instanceof LateLifecycleElement).toBe(true);
    expect(lifecycleEvents).toContain("connected");

    beforeDefine.setAttribute("data-state", "ready");
    beforeDefine.removeAttribute("data-state");

    expect(lifecycleEvents).toContain("attr:data-state:null->ready");
    expect(lifecycleEvents).toContain("attr:data-state:ready->null");

    document.body.removeChild(beforeDefine);
    expect(lifecycleEvents).toContain("disconnected");
  });
});

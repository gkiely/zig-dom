import { describe, expect, test } from "bun:test";
import { Browser } from "../../../js/index.ts";

describe("browser compatibility surface", () => {
  test("Browser and Page expose document/content/url lifecycle", async () => {
    const browser = await Browser.create();
    const page = browser.newPage({ url: "http://localhost/" });

    expect(page.mainFrame.document).toBe(page.window.document);

    page.content = "<main id=\"app\"><button>Save</button></main>";
    expect(page.window.document.querySelector("#app")?.textContent).toContain("Save");

    page.url = "http://example.test/path";
    expect(page.url).toBe("http://example.test/path");
    expect(page.window.location.hostname).toBe("example.test");
    page.window.location.search = "?q=zig";
    expect(page.window.location.href).toContain("?q=zig");
    page.window.location.hash = "#state";
    expect(page.window.location.hash).toBe("#state");

    expect(page.window.history.length).toBe(1);
    page.window.history.pushState({ page: 2 }, "", "/next?step=2#section");
    expect(page.window.location.href).toBe("http://example.test/next?step=2#section");
    expect(page.window.history.state).toEqual({ page: 2 });
    expect(page.window.history.length).toBe(2);

    page.window.history.replaceState({ page: 3 }, "", "/replaced");
    expect(page.window.location.href).toBe("http://example.test/replaced");
    expect(page.window.history.state).toEqual({ page: 3 });
    expect(page.window.history.length).toBe(2);

    let popState: unknown = null;
    page.window.addEventListener("popstate", (event) => {
      popState = (event as Event & { state: unknown }).state;
    });
    page.window.history.back();
    expect(page.window.location.href).toBe("http://example.test/path?q=zig#state");
    expect(popState).toBeNull();
    page.window.history.forward();
    expect(page.window.location.href).toBe("http://example.test/replaced");
    expect(popState).toEqual({ page: 3 });

    await page.waitUntilComplete();
    page.abort();
    expect(page.window.closed).toBe(true);

    browser.close();
  });

  test("computed style exposes common camel-case properties", async () => {
    const browser = await Browser.create();
    const page = browser.newPage();
    const list = page.window.document.createElement("ol");

    expect(page.window.getComputedStyle(list).listStyleType).toBe("decimal");

    list.setAttribute("style", "list-style-type: lower-roman; color: red;");
    expect(page.window.getComputedStyle(list).listStyleType).toBe("lower-roman");
    expect(page.window.getComputedStyle(list).color).toBe("red");

    browser.close();
  });

  test("elements expose zeroed layout rectangles", async () => {
    const browser = await Browser.create();
    const page = browser.newPage();
    const element = page.window.document.createElement("button");

    expect(element.getBoundingClientRect()).toMatchObject({
      x: 0,
      y: 0,
      width: 0,
      height: 0,
      top: 0,
      right: 0,
      bottom: 0,
      left: 0
    });
    expect(element.getClientRects().length).toBe(0);

    browser.close();
  });

  test("TreeWalker and NodeFilter can walk text nodes", async () => {
    const browser = await Browser.create();
    const page = browser.newPage();
    const link = page.window.document.createElement("a");
    link.innerHTML = "Step <span>[[step]]</span>";

    const walker = page.window.document.createTreeWalker(link, page.window.NodeFilter.SHOW_TEXT);
    const values: string[] = [];
    let node = walker.nextNode();
    while (node) {
      values.push(node.textContent ?? "");
      node = walker.nextNode();
    }

    expect(values).toEqual(["Step ", "[[step]]"]);

    browser.close();
  });
});

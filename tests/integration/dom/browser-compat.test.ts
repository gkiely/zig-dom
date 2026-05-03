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

    await page.waitUntilComplete();
    page.abort();
    expect(page.window.closed).toBe(true);

    browser.close();
  });
});

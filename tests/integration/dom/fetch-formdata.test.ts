import { describe, expect, test } from "bun:test";

describe("fetch and web primitive compatibility", () => {
  test("window exposes fetch-related primitives", async () => {
    expect(typeof window.fetch).toBe("function");
    expect(window.Headers).toBeDefined();
    expect(window.Request).toBeDefined();
    expect(window.Response).toBeDefined();
    expect(window.FormData).toBeDefined();
    expect(window.Blob).toBeDefined();
    expect(window.File).toBeDefined();

    const response = await window.fetch("data:text/plain,zig-dom");
    expect(await response.text()).toBe("zig-dom");
  });

  test("FormData and Headers constructors are usable from window", () => {
    const formData = new window.FormData();
    formData.set("name", "ada");
    expect(formData.get("name")).toBe("ada");

    const headers = new window.Headers();
    headers.set("x-test", "1");
    expect(headers.get("x-test")).toBe("1");
  });
});

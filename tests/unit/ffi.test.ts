import { afterEach, describe, expect, test } from "bun:test";
import { native } from "../../js/ffi";

const windows: number[] = [];

afterEach(() => {
  while (windows.length > 0) {
    const handle = windows.pop();
    if (handle) {
      native.destroyWindow(handle);
    }
  }
});

describe("ffi", () => {
  test("returns version", () => {
    expect(native.version()).toContain("0.1.0");
  });

  test("documents ABI struct decision", () => {
    expect(native.canReturnStructs()).toBe(false);
  });

  test("echoes utf8 strings with explicit length", () => {
    const input = "hello-ffi-✓";
    expect(native.echoUtf8(input)).toBe(input);
  });

  test("creates window and traverses node tree", () => {
    const windowHandle = native.createWindow();
    windows.push(windowHandle);

    const documentHandle = native.windowDocument(windowHandle);
    const bodyHandle = native.windowBody(windowHandle);
    const elementHandle = native.createElement(documentHandle, "div");
    native.setAttribute(elementHandle, "id", "probe");
    native.appendChild(bodyHandle, elementHandle);

    const found = native.documentGetElementById(documentHandle, "probe");
    expect(found).toBe(elementHandle);
    expect(native.nodeParent(elementHandle)).toBe(bodyHandle);
    expect(native.nodeContains(bodyHandle, elementHandle)).toBe(true);

    const siblingHandle = native.createElement(documentHandle, "span");
    native.appendChild(bodyHandle, siblingHandle);
    const relation = native.nodeCompareDocumentPosition(elementHandle, siblingHandle);
    expect((relation & 0x04) !== 0).toBe(true);

    const attrs = native.elementAttributes(elementHandle);
    expect(attrs).toContainEqual({ name: "id", value: "probe" });
  });
});

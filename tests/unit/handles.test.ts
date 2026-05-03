import { afterEach, describe, expect, test } from "bun:test";
import { native } from "../../js/ffi";
import { Window } from "../../js/wrappers/Window";

const windows: number[] = [];

function trackWindow(handle: number): number {
  windows.push(handle);
  return handle;
}

function destroyTrackedWindow(handle: number): void {
  const index = windows.indexOf(handle);
  if (index >= 0) {
    windows.splice(index, 1);
  }
  native.destroyWindow(handle);
}

afterEach(() => {
  while (windows.length > 0) {
    const handle = windows.pop();
    if (handle) {
      native.destroyWindow(handle);
    }
  }
});

describe("native handles", () => {
  test("invalidates document handles after window destruction", () => {
    const windowHandle = trackWindow(native.createWindow());
    const documentHandle = native.windowDocument(windowHandle);
    const elementHandle = native.createElement(documentHandle, "div");

    destroyTrackedWindow(windowHandle);

    expect(() => native.windowDocument(windowHandle)).toThrow(/invalid_handle/);
    expect(() => native.nodeOwnerDocument(elementHandle)).toThrow(/invalid_handle/);
  });

  test("returns a distinct handle after destroy and recreate", () => {
    const firstWindow = native.createWindow();
    const firstDocument = native.windowDocument(firstWindow);

    native.destroyWindow(firstWindow);

    const secondWindow = trackWindow(native.createWindow());
    const secondDocument = native.windowDocument(secondWindow);

    expect(secondWindow).not.toBe(firstWindow);
    expect(secondDocument).not.toBe(firstDocument);
  });

  test("allows explicit retain and release on live handles", () => {
    const windowHandle = trackWindow(native.createWindow());
    const documentHandle = native.windowDocument(windowHandle);

    native.retainHandle(documentHandle);
    native.releaseHandle(documentHandle);

    expect(native.nodeType(documentHandle)).toBe(9);
  });

  test("throws a controlled error when wrappers are used after close", () => {
    const window = new Window();
    const node = window.document.createElement("div");

    window.close();

    expect(() => {
      void node.nodeType;
    }).toThrow("Window is closed");

    expect(() => window.document.createElement("span")).toThrow("Window is closed");
  });

  test("debug counters stay balanced across repeated create/close cycles", () => {
    native.debugResetCounters();

    for (let index = 0; index < 25; index += 1) {
      const window = new Window();
      const root = window.document.createElement("div");
      for (let i = 0; i < 20; i += 1) {
        const child = window.document.createElement("span");
        child.textContent = `node-${index}-${i}`;
        root.appendChild(child);
      }
      window.document.body.appendChild(root);
      window.close();
    }

    const counters = native.debugGetCounters();
    expect(counters.windowsCreated).toBe(counters.windowsDestroyed);
    expect(counters.nodesCreated).toBe(counters.nodesDestroyed);
  });
});

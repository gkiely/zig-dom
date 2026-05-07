import { expect, test } from "bun:test";
import zigDOM, {
  GlobalRegistrator,
  Node,
  Element,
  Window,
  PropertySymbol,
} from "zig-dom";

test("zig-dom builtin module exports native DOM globals", () => {
  expect(Node).toBe(globalThis.Node);
  expect(Element).toBe(globalThis.Element);
  expect(Window).toBe(globalThis.Window);
  expect(zigDOM.Window).toBe(Window);
  expect(zigDOM.GlobalRegistrator).toBe(GlobalRegistrator);
  expect(zigDOM.PropertySymbol).toBe(PropertySymbol);

  const win = new Window({ url: "https://module.test/path?x=1#frag" });
  expect(win instanceof Window).toBe(true);
  expect(win.document instanceof globalThis.Document).toBe(true);
  expect(win.location.href).toBe("https://module.test/path?x=1#frag");
  expect(typeof win.happyDOM.reset).toBe("function");

  const element = win.document.createElement("div");
  element.id = "from-module";
  win.document.body.appendChild(element);

  expect(element instanceof Element).toBe(true);
  expect(win.document.getElementById("from-module")).toBe(element);
});

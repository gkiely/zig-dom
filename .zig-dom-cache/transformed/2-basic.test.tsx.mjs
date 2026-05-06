import { expect, test } from "bun:test";
test("zig CLI runner tsx smoke", () => {
  const node = jsxDEV_7x81h0kn("article", {
    "data-kind": "tsx",
    children: "ok"
  }, undefined, false, undefined, this);
  expect(node.type).toBe("article");
  expect(node.props["data-kind"]).toBe("tsx");
});

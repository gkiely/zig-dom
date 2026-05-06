import React from "react";
import { expect, test } from "bun:test";
test("zig CLI runner jsx smoke", () => {
  const node = jsxDEV_7x81h0kn("section", {
    "data-kind": "smoke",
    children: "ok"
  }, undefined, false, undefined, this);
  expect(node.type).toBe("section");
  expect(node.props["data-kind"]).toBe("smoke");
});

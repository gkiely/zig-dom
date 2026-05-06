import React from "react";
import { expect, test } from "bun:test";

test("zig CLI runner jsx smoke", () => {
  const node = <section data-kind="smoke">ok</section>;
  expect(node.type).toBe("section");
  expect(node.props["data-kind"]).toBe("smoke");
});

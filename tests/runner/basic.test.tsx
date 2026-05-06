import React from "react";
import { expect, test } from "bun:test";

test("zig CLI runner tsx smoke", () => {
  const node: React.ReactElement = <article data-kind="tsx">ok</article>;
  expect(node.type).toBe("article");
  expect(node.props["data-kind"]).toBe("tsx");
});

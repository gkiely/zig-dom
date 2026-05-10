import { expect, test } from "bun:test";

test("custom toBeInTheDocument matcher overrides the built-in matcher", () => {
  expect.extend({
    toBeInTheDocument(value) {
      return {
        pass: value === "custom-pass",
        message: () => "custom matcher result",
      };
    },
  });

  expect("custom-pass").toBeInTheDocument();
  expect("custom-fail").not.toBeInTheDocument();
});

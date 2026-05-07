import { expect, test } from "bun:test";

test("import.meta.env mirrors process env entries", () => {
  const env = import.meta.env;
  expect(typeof env).toBe("object");
  expect(env?.ZIG_DOM_SKIP_TESTING_LIBRARY).toBe("1");
});

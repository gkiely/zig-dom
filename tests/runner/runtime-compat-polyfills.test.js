import { expect, test } from "bun:test";

test("runner exposes modern compatibility polyfills", () => {
  expect(typeof Array.prototype.at).toBe("function");
  expect(["a", "b", "c"].at(-1)).toBe("c");
  expect(typeof String.prototype.at).toBe("function");
  expect("abc".at(-1)).toBe("c");
  expect(typeof Object.hasOwn).toBe("function");
  expect(Object.hasOwn({ a: 1 }, "a")).toBe(true);
});

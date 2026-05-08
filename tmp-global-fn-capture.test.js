import { test, expect } from "bun:test";

test("global assignment of local function capture", () => {
  const source = `
let values = [];
function activated(v) { values.push(v); }
globalThis.activated = activated;
globalThis.__valuesRef = values;
`;
  new Function(source)();
  globalThis.activated("x");
  expect(globalThis.__valuesRef.length).toBe(1);
  expect(globalThis.__valuesRef[0]).toBe("x");
});

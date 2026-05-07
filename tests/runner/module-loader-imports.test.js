import { expect as assert, test as it } from "bun:test";
import defaultThing, { namedThing } from "./fixtures/modules/default-named";
import { getMessage, nestedNumber } from "./fixtures/modules/entry";

it("module loader resolves relative and nested imports", () => {
  assert(getMessage()).toBe("hello-deep-nested");
  assert(nestedNumber).toBe(7);
});

it("module loader supports named and default imports", () => {
  assert(defaultThing).toBe("default-ok");
  assert(namedThing).toBe("named-ok");
});

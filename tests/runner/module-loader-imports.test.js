import { expect as assert, test as it } from "bun:test";
import * as bunTest from "bun:test";
import defaultThing, { namedThing } from "./fixtures/modules/default-named";
import { getMessage, nestedNumber } from "./fixtures/modules/entry";
import { typedValue } from "./fixtures/modules/types-util";
import { tsxNode } from "./fixtures/modules/tsx-node";
import { jsxNode } from "./fixtures/modules/jsx-node";

it("module loader resolves relative and nested imports", () => {
  assert(getMessage()).toBe("hello-deep-nested");
  assert(nestedNumber).toBe(7);
});

it("module loader supports named and default imports", () => {
  assert(defaultThing).toBe("default-ok");
  assert(namedThing).toBe("named-ok");
});

it("module loader supports aliased and namespace bun:test imports", () => {
  bunTest.expect(2 + 2).toBe(4);
  assert(bunTest.expect).toBe(assert);
  assert(bunTest.test).toBe(it);
});

it("module loader handles TS/TSX/JSX transformed dependencies", () => {
  assert(typedValue).toBe(12);
  assert(tsxNode.type).toBe("em");
  assert(tsxNode.props.children).toBe("tsx-12");
  assert(jsxNode.type).toBe("strong");
  assert(jsxNode.props.children).toBe("tsx-12-jsx");
});

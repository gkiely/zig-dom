import { mock } from "bun:test";

await mock.module("virtual-multiple-one", () => ({
  default: "one-default",
  one: 1
}));

await mock.module("virtual-multiple-two", () => ({
  default: "two-default",
  two: 2
}));

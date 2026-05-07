import { mock } from "bun:test";

await mock.module("virtual-async-target", async () => {
  return {
    default: "async-default",
    namedValue: 23
  };
});

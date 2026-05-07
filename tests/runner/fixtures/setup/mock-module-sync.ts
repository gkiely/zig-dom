import { mock } from "bun:test";

await mock.module("virtual-sync-target", () => ({
  default: "sync-default",
  namedValue: 17
}));

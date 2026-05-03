import { expect, test } from "bun:test";

test("tiny wpt subset runner exits successfully", () => {
  const result = Bun.spawnSync([
    "bun",
    "run",
    "scripts/run-wpt-subset.ts",
    "--manifest",
    "wpt/manifest/dom-core.json",
    "--expected",
    "wpt/expected/dom-core.json"
  ]);

  expect(result.exitCode).toBe(0);
});

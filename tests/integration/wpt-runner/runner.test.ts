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

test("tiny wpt subset runner fails when expected failure metadata is incomplete", () => {
  const result = Bun.spawnSync([
    "bun",
    "run",
    "scripts/run-wpt-subset.ts",
    "--manifest",
    "tests/fixtures/wpt-runner/manifest.json",
    "--expected",
    "tests/fixtures/wpt-runner/expected-missing-reason.json"
  ]);

  const stderr = new TextDecoder().decode(result.stderr);
  expect(result.exitCode).not.toBe(0);
  expect(stderr).toContain("Both reason and owner are required");
});

test("tiny wpt subset runner accepts single variant entries", () => {
  const result = Bun.spawnSync([
    "bun",
    "run",
    "scripts/run-wpt-subset.ts",
    "--manifest",
    "tests/fixtures/wpt-runner/manifest-single-variant.json",
    "--expected",
    "tests/fixtures/wpt-runner/expected-empty.json"
  ]);

  expect(result.exitCode).toBe(0);
});

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { Window } from "../js/wrappers/Window";

type ManifestEntry = {
  file: string;
};

type Manifest = {
  tests: ManifestEntry[];
};

type ExpectedEntry = {
  file: string;
  subtest: string;
  reason: string;
  owner: string;
};

type ExpectedMap = {
  expectedFailures: ExpectedEntry[];
};

type SubtestResult = {
  file: string;
  name: string;
  status: "pass" | "fail";
  message?: string;
  durationMs: number;
};

type TinyTest = {
  name: string;
  run: (ctx: {
    assert: {
      equal(actual: unknown, expected: unknown, message?: string): void;
      ok(value: unknown, message?: string): void;
    };
    createWindow: () => Window;
  }) => void | Promise<void>;
};

function arg(name: string): string {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    throw new Error(`Missing argument ${name}`);
  }
  return process.argv[index + 1];
}

function createAssert() {
  return {
    equal(actual: unknown, expected: unknown, message = "Expected values to be equal") {
      if (actual !== expected) {
        throw new Error(`${message}: expected=${String(expected)} actual=${String(actual)}`);
      }
    },
    ok(value: unknown, message = "Expected value to be truthy") {
      if (!value) {
        throw new Error(message);
      }
    }
  };
}

async function runEntry(file: string): Promise<SubtestResult[]> {
  const modulePath = pathToFileURL(resolve(file)).href;
  const mod = (await import(modulePath)) as { tests: TinyTest[] };
  const tests = mod.tests ?? [];
  const results: SubtestResult[] = [];

  for (const testCase of tests) {
    const start = performance.now();
    try {
      await testCase.run({
        assert: createAssert(),
        createWindow: () => new Window({ url: "http://localhost/" })
      });
      results.push({
        file,
        name: testCase.name,
        status: "pass",
        durationMs: performance.now() - start
      });
    } catch (error) {
      results.push({
        file,
        name: testCase.name,
        status: "fail",
        message: error instanceof Error ? error.message : String(error),
        durationMs: performance.now() - start
      });
    }
  }

  return results;
}

const manifestPath = arg("--manifest");
const expectedPath = arg("--expected");

const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;
const expected = JSON.parse(readFileSync(expectedPath, "utf8")) as ExpectedMap;

const expectedMap = new Map(expected.expectedFailures.map((entry) => [`${entry.file}::${entry.subtest}`, entry]));

const allResults: SubtestResult[] = [];
for (const entry of manifest.tests) {
  const fileResults = await runEntry(entry.file);
  allResults.push(...fileResults);
}

let passed = 0;
let failed = 0;
let expectedFail = 0;
let unexpectedPass = 0;

for (const result of allResults) {
  const key = `${result.file}::${result.name}`;
  const expectedFailure = expectedMap.get(key);

  if (result.status === "pass") {
    if (expectedFailure) {
      unexpectedPass += 1;
      console.log(`UNEXPECTED_PASS ${result.file} :: ${result.name}`);
    } else {
      passed += 1;
      console.log(`PASS ${result.file} :: ${result.name}`);
    }
    continue;
  }

  failed += 1;
  if (expectedFailure) {
    expectedFail += 1;
    console.log(`EXPECTED_FAIL ${result.file} :: ${result.name} :: ${expectedFailure.reason} (${expectedFailure.owner})`);
  } else {
    console.log(`FAIL ${result.file} :: ${result.name} :: ${result.message ?? "unknown"}`);
  }
}

const unexpectedFail = failed - expectedFail;
console.log(`SUMMARY pass=${passed} fail=${failed} expected_fail=${expectedFail} unexpected_pass=${unexpectedPass}`);

if (unexpectedFail > 0 || unexpectedPass > 0) {
  process.exit(1);
}

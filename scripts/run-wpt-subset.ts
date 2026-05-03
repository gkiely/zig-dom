import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { Window } from "../js/wrappers/Window";

type ManifestEntry = {
  file: string;
  variants?: string[];
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

type HarnessTest = {
  name: string;
  run: () => void | Promise<void>;
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

function readText(filePath: string): string {
  return readFileSync(resolve(filePath), "utf8");
}

function normalizeVariant(variant: string): string {
  if (variant.startsWith("?") || variant.startsWith("#")) {
    return variant;
  }
  return `?${variant}`;
}

function entryId(file: string, variant?: string): string {
  return variant ? `${file}${normalizeVariant(variant)}` : file;
}

function testUrl(file: string, variant?: string): string {
  const normalizedFile = file.replaceAll("\\", "/");
  const base = `http://localhost/${normalizedFile}`;
  return variant ? `${base}${normalizeVariant(variant)}` : base;
}

function resolveScriptPath(entryFile: string, scriptRef: string): string {
  if (scriptRef.startsWith("/")) {
    return resolve("wpt/runner", scriptRef.slice(1));
  }
  return resolve(dirname(entryFile), scriptRef);
}

function parseMetaScripts(html: string): string[] {
  const metaScripts: string[] = [];
  const regex = /META:\s*script=([^\s]+)/g;
  let match: RegExpExecArray | null = null;
  while ((match = regex.exec(html)) !== null) {
    const scriptRef = match[1]?.trim();
    if (scriptRef) {
      metaScripts.push(scriptRef);
    }
  }
  return metaScripts;
}

function parseScriptBlocks(entryFile: string, html: string): string[] {
  const scripts: string[] = [];
  const regex = /<script([^>]*)>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null = null;

  while ((match = regex.exec(html)) !== null) {
    const attrs = match[1] ?? "";
    const body = match[2] ?? "";
    const srcMatch = attrs.match(/\bsrc\s*=\s*["']([^"']+)["']/i);
    if (srcMatch?.[1]) {
      const sourcePath = resolveScriptPath(entryFile, srcMatch[1]);
      scripts.push(readText(sourcePath));
      continue;
    }

    if (body.trim().length > 0) {
      scripts.push(body);
    }
  }

  return scripts;
}

async function runHtmlEntry(file: string, variant?: string): Promise<SubtestResult[]> {
  const html = readText(file);
  const assert = createAssert();
  const queuedTests: HarnessTest[] = [];
  const fileId = entryId(file, variant);

  const window = new Window({ url: testUrl(file, variant) });
  const test = (fn: () => void | Promise<void>, name = "test") => {
    queuedTests.push({ name, run: fn });
  };

  const promise_test = (fn: () => Promise<void>, name = "promise_test") => {
    queuedTests.push({ name, run: fn });
  };

  const createDeferredAsyncTest = (name: string, callback?: (testObj: {
    done: () => void;
    step: (fn: () => void) => void;
    step_func: <TArgs extends unknown[]>(fn: (...args: TArgs) => void) => (...args: TArgs) => void;
    step_timeout: (fn: () => void, delay: number) => ReturnType<typeof setTimeout>;
    unreached_func: (message?: string) => () => never;
  }) => void) => {
    let complete = false;
    let failError: unknown = null;

    let resolveDone!: () => void;
    const completion = new Promise<void>((resolve) => {
      resolveDone = resolve;
    });

    const testObj = {
      done: () => {
        complete = true;
        resolveDone();
      },
      step: (fn: () => void) => {
        try {
          fn();
        } catch (error) {
          failError = error;
          resolveDone();
        }
      },
      step_func: <TArgs extends unknown[]>(fn: (...args: TArgs) => void) => {
        return (...args: TArgs) => {
          testObj.step(() => fn(...args));
        };
      },
      step_timeout: (fn: () => void, delay: number) => {
        return setTimeout(() => {
          testObj.step(fn);
        }, delay);
      },
      unreached_func: (message?: string) => {
        return () => {
          throw new Error(message ?? "unreached code path invoked");
        };
      }
    };

    const entry: HarnessTest = {
      name,
      async run() {
        if (callback) {
          try {
            callback(testObj);
          } catch (error) {
            failError = error;
            resolveDone();
          }
        }

        const timeout = new Promise<never>((_resolve, reject) => {
          setTimeout(() => {
            reject(new Error(`async_test timeout: ${name}`));
          }, 2000);
        });

        await Promise.race([completion, timeout]);

        if (failError) {
          throw failError;
        }
        if (!complete) {
          throw new Error(`async_test did not call done(): ${name}`);
        }
      }
    };

    queuedTests.push(entry);
    return testObj;
  };

  const async_test = (
    first?: string | ((testObj: {
      done: () => void;
      step: (fn: () => void) => void;
      step_func: <TArgs extends unknown[]>(fn: (...args: TArgs) => void) => (...args: TArgs) => void;
      step_timeout: (fn: () => void, delay: number) => ReturnType<typeof setTimeout>;
      unreached_func: (message?: string) => () => never;
    }) => void),
    second?: string
  ) => {
    const callback = typeof first === "function" ? first : undefined;
    const name = typeof first === "string" ? first : second ?? "async_test";

    return createDeferredAsyncTest(name, callback);
  };

  const assert_true = (value: unknown, message = "Expected value to be truthy") => {
    assert.ok(value, message);
  };

  const assert_equals = (actual: unknown, expected: unknown, message?: string) => {
    assert.equal(actual, expected, message);
  };

  const context: Record<string, unknown> = {
    window,
    self: window,
    document: window.document,
    location: window.location,
    console,
    setTimeout,
    clearTimeout,
    Promise,
    test,
    promise_test,
    async_test,
    assert_true,
    assert_equals,
    add_cleanup: () => undefined
  };
  context.globalThis = context;

  const executeScript = (source: string) => {
    const keys = Object.keys(context);
    const values = keys.map((key) => context[key]);
    const fn = new Function(...keys, source);
    fn(...values);
  };

  const allScripts: string[] = [];
  for (const metaScript of parseMetaScripts(html)) {
    allScripts.push(readText(resolveScriptPath(file, metaScript)));
  }
  allScripts.push(...parseScriptBlocks(file, html));

  try {
    executeScript(allScripts.join("\n;\n"));

    const results: SubtestResult[] = [];
    for (const harnessTest of queuedTests) {
      const start = performance.now();
      try {
        await harnessTest.run();
        results.push({
          file: fileId,
          name: harnessTest.name,
          status: "pass",
          durationMs: performance.now() - start
        });
      } catch (error) {
        results.push({
          file: fileId,
          name: harnessTest.name,
          status: "fail",
          message: error instanceof Error ? error.message : String(error),
          durationMs: performance.now() - start
        });
      }
    }

    return results;
  } finally {
    window.close();
  }
}

async function runEntry(file: string, variant?: string): Promise<SubtestResult[]> {
  const fileId = entryId(file, variant);

  if (file.toLowerCase().endsWith(".html")) {
    return runHtmlEntry(file, variant);
  }

  const modulePath = pathToFileURL(resolve(file)).href;
  const mod = (await import(modulePath)) as { tests: TinyTest[] };
  const tests = mod.tests ?? [];
  const results: SubtestResult[] = [];

  for (const testCase of tests) {
    const start = performance.now();
    try {
      await testCase.run({
        assert: createAssert(),
        createWindow: () => new Window({ url: testUrl(file, variant) })
      });
      results.push({
        file: fileId,
        name: testCase.name,
        status: "pass",
        durationMs: performance.now() - start
      });
    } catch (error) {
      results.push({
        file: fileId,
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

const expectedMap = new Map<string, ExpectedEntry>();
for (const entry of expected.expectedFailures) {
  const reason = entry.reason?.trim();
  const owner = entry.owner?.trim();
  if (!reason || !owner) {
    throw new Error(`Invalid expected failure entry for ${entry.file} :: ${entry.subtest}. Both reason and owner are required.`);
  }

  const key = `${entry.file}::${entry.subtest}`;
  if (expectedMap.has(key)) {
    throw new Error(`Duplicate expected failure entry: ${key}`);
  }
  expectedMap.set(key, entry);
}

const allResults: SubtestResult[] = [];
for (const entry of manifest.tests) {
  if (entry.variants && entry.variants.length > 0) {
    for (const variant of entry.variants) {
      const fileResults = await runEntry(entry.file, variant);
      allResults.push(...fileResults);
    }
  } else {
    const fileResults = await runEntry(entry.file);
    allResults.push(...fileResults);
  }
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

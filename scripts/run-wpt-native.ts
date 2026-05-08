import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";

type ManifestEntry = {
  file: string;
  variant?: string;
  variants?: string[];
};

type Manifest = {
  tests: ManifestEntry[];
};

function arg(name: string): string {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    throw new Error(`Missing argument ${name}`);
  }
  return process.argv[index + 1];
}

function optionalArg(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    return undefined;
  }
  return process.argv[index + 1];
}

function optionalNumberArg(name: string): number | undefined {
  const value = optionalArg(name);
  if (value == null) return undefined;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`Invalid numeric argument for ${name}: ${value}`);
  }
  return parsed;
}

function expandVariants(entry: ManifestEntry): Array<string | undefined> {
  const variants = entry.variants?.filter(Boolean) ?? [];
  if (entry.variant && variants.length > 0) {
    throw new Error(`Manifest entry for ${entry.file} cannot define both variant and variants.`);
  }
  if (entry.variant) return [entry.variant];
  return variants.length > 0 ? variants : [undefined];
}

function scriptFileRef(scriptRef: string): string {
  return scriptRef.split(/[?#]/)[0] ?? scriptRef;
}

function rewriteWptScriptPath(fileRef: string): string {
  const normalized = fileRef.toLowerCase();
  // Upstream WPT server rewrites this legacy path to webidl2.
  if (normalized === "/resources/webidlparser.js") {
    return "/resources/webidl2/lib/webidl2.js";
  }
  return fileRef;
}

function resolveScriptPath(entryFile: string, scriptRef: string, wptRootPath: string): string {
  const fileRef = rewriteWptScriptPath(scriptFileRef(scriptRef));
  if (scriptRef.startsWith("/")) {
    return resolve(wptRootPath, fileRef.slice(1));
  }
  return resolve(dirname(entryFile), fileRef);
}

function parseMetaScripts(html: string): string[] {
  const scripts: string[] = [];
  const regex = /META:\s*script=([^\s]+)/g;
  let match: RegExpExecArray | null = null;
  while ((match = regex.exec(html)) !== null) {
    if (match[1]) scripts.push(match[1]);
  }
  return scripts;
}

function parseScriptBlocks(entryFile: string, html: string, wptRootPath: string): string[] {
  const scripts: string[] = [];
  const regex = /<script([^>]*)>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null = null;
  while ((match = regex.exec(html)) !== null) {
    const attrs = match[1] ?? "";
    const body = match[2] ?? "";
    const srcMatch = attrs.match(/\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))/i);
    const src = srcMatch?.[1] ?? srcMatch?.[2] ?? srcMatch?.[3];
    if (src) {
      const normalized = scriptFileRef(src).toLowerCase();
      if (normalized === "/resources/testharness.js" || normalized === "/resources/testharnessreport.js") {
        continue;
      }
      scripts.push(readFileSync(resolveScriptPath(entryFile, src, wptRootPath), "utf8"));
    } else if (body.trim()) {
      scripts.push(body);
    }
  }
  return scripts;
}

function extractBody(html: string): string {
  const explicitBody = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i)?.[1];
  if (explicitBody != null) return explicitBody;

  // Some WPT files place test markup at top-level without a <body> wrapper.
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<!doctype[^>]*>/gi, "")
    .replace(/<meta\b[^>]*>/gi, "")
    .replace(/<title\b[^>]*>[\s\S]*?<\/title>/gi, "")
    .replace(/<link\b[^>]*>/gi, "")
    .replace(/<\/?(?:html|head|body)\b[^>]*>/gi, "")
    .trim();
}

function toImportPath(fromFile: string, targetFile: string): string {
  let importPath = relative(dirname(fromFile), resolve(targetFile)).replaceAll("\\", "/");
  if (!importPath.startsWith(".")) importPath = `./${importPath}`;
  return importPath;
}

function entryUrl(file: string, variant?: string): string {
  const suffix = variant ? (variant.startsWith("?") || variant.startsWith("#") ? variant : `?${variant}`) : "";
  return `http://localhost/${file.replaceAll("\\", "/")}${suffix}`;
}

function nativeWindowSetupSource(urlExpression: string): string {
  return `
function createNativeWindow() {
  const win = new Window();
  try {
    if (win && win.location) win.location.href = ${urlExpression};
  } catch {}
  return win;
}
`;
}

function generateAnyTest(outFile: string, entry: ManifestEntry, variant?: string): string {
  const url = JSON.stringify(entryUrl(entry.file, variant));
  return `import { expect, test } from "bun:test";
import { tests } from ${JSON.stringify(toImportPath(outFile, entry.file))};

${nativeWindowSetupSource(url)}

function createAssert() {
  return {
    equal(actual, expected, message = "Expected values to be equal") {
      if (actual !== expected) {
        throw new Error(message + ": expected=" + String(expected) + " actual=" + String(actual));
      }
    },
    ok(value, message = "Expected value to be truthy") {
      if (!value) throw new Error(message);
    }
  };
}

for (const testCase of tests) {
  test(${JSON.stringify(entry.file)} + " :: " + testCase.name, async () => {
    await testCase.run({
      assert: createAssert(),
      createWindow: createNativeWindow
    });
  });
}
`;
}

function generateHtmlTest(entry: ManifestEntry, wptRootPath: string, variant?: string): string {
  const html = readFileSync(entry.file, "utf8");
  const scripts = [
    ...parseMetaScripts(html).map((script) => readFileSync(resolveScriptPath(entry.file, script, wptRootPath), "utf8")),
    ...parseScriptBlocks(entry.file, html, wptRootPath)
  ];
  return `import { expect, test as bunTest } from "bun:test";

const pending = [];
const source = ${JSON.stringify(scripts.join("\n;\n"))};

${nativeWindowSetupSource(JSON.stringify(entryUrl(entry.file, variant)))}

const __zigWptInitialBody = ${JSON.stringify(extractBody(html))};
const __zigWptSetups = [];

function resetWptDomFixture() {
  document.body.innerHTML = __zigWptInitialBody;
  if (typeof globalThis.__zigDomSyncWindowNamedProperties === "function") {
    globalThis.__zigDomSyncWindowNamedProperties();
  }
}

function runWptSetups() {
  const setupContext = { add_cleanup() {} };
  for (const setupFn of __zigWptSetups) {
    if (typeof setupFn === "function") {
      setupFn.call(setupContext);
    }
  }
}

function createWptCleanupContext() {
  const cleanups = [];
  return {
    context: {
      add_cleanup(fn) {
        if (typeof fn === "function") {
          cleanups.push(fn);
        }
      }
    },
    runCleanups() {
      for (let i = cleanups.length - 1; i >= 0; i -= 1) {
        try {
          cleanups[i]();
        } catch {}
      }
    }
  };
}

resetWptDomFixture();
try {
  if (window && window.location) window.location.href = ${JSON.stringify(entryUrl(entry.file, variant))};
} catch {}

function fail(message) {
  throw new Error(message);
}

globalThis.test = (fn, name = "test") => {
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, () => {
    resetWptDomFixture();
    runWptSetups();
    const cleanup = createWptCleanupContext();
    try {
      return fn.call(cleanup.context);
    } finally {
      cleanup.runCleanups();
    }
  });
};
globalThis.promise_test = (fn, name = "promise_test") => {
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, async () => {
    resetWptDomFixture();
    runWptSetups();
    const cleanup = createWptCleanupContext();
    try {
      return await fn.call(cleanup.context, cleanup.context);
    } finally {
      cleanup.runCleanups();
    }
  });
};
globalThis.async_test = (first = "async_test", second) => {
  const callback = typeof first === "function" ? first : undefined;
  const name = typeof first === "string" ? first : second ?? "async_test";
  let resolveDone;
  let rejectDone;
  const done = new Promise((resolve, reject) => {
    resolveDone = resolve;
    rejectDone = reject;
  });
  const runStep = (fn, args = []) => {
    try {
      return fn(...args);
    } catch (err) {
      rejectDone(err);
      throw err;
    }
  };
  const testObject = {
    done: () => resolveDone(),
    step: (fn) => runStep(fn),
    step_timeout: (fn, delay = 0) => {
      const timeoutFn = typeof globalThis.setTimeout === "function"
        ? globalThis.setTimeout.bind(globalThis)
        : ((runNow) => {
            runNow();
            return 0;
          });
      return timeoutFn(() => {
        runStep(fn);
      }, Number(delay) || 0);
    },
    step_func: (fn) => (...args) => runStep(fn, args),
    step_func_done: (fn) => (...args) => {
      runStep(fn, args);
      resolveDone();
    },
    unreached_func: (message) => () => {
      const error = new Error(message || "unreached");
      rejectDone(error);
      throw error;
    }
  };
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, async () => {
    resetWptDomFixture();
    runWptSetups();
    if (callback) callback(testObject);
    await done;
  });
  return testObject;
};
globalThis.setup = (fnOrOptions) => {
  if (typeof fnOrOptions === "function") {
    __zigWptSetups.push(fnOrOptions);
  }
};
globalThis.done = () => {};
globalThis.assert_true = (value, message = "Expected value to be truthy") => expect(Boolean(value), message).toBe(true);
globalThis.assert_false = (value, message = "Expected value to be falsy") => expect(Boolean(value), message).toBe(false);
globalThis.assert_equals = (actual, expected, message = "Expected values to be equal") => expect(actual, message).toBe(expected);
globalThis.assert_not_equals = (actual, expected, message = "Expected values to differ") => expect(actual, message).not.toBe(expected);
globalThis.assert_array_equals = (actual, expected, message = "Expected arrays to be equal") => expect(Array.from(actual), message).toEqual(Array.from(expected));
globalThis.assert_throws_js = (ctor, fn, message = "Expected JS exception") => expect(fn, message).toThrow(ctor);
globalThis.assert_throws_dom = (_expected, fnOrCtor, maybeFn, message = "Expected DOM exception") => {
  const fn = typeof maybeFn === "function" ? maybeFn : fnOrCtor;
  expect(fn, message).toThrow();
};
globalThis.assert_unreached = (message = "Reached unreachable code") => fail(message);
globalThis.promise_rejects_js = async (_t, ctor, promise) => expect(promise).rejects.toThrow(ctor);
globalThis.add_cleanup = () => {};

new Function(source)();
await Promise.all(pending);
`;
}

const manifestPath = arg("--manifest");
const wptRootPath = resolve(optionalArg("--wpt-root") ?? ".wpt-cache/web-platform-tests");
const startEntry = optionalNumberArg("--start-entry") ?? 0;
const entryCount = optionalNumberArg("--entry-count");
const batchSize = optionalNumberArg("--batch-size") ?? 1;
const defaultGeneratedDir = `wpt/.native-generated/${basename(manifestPath, ".json")}`;
const outDir = resolve(optionalArg("--generated-dir") ?? defaultGeneratedDir);

const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;
const expanded = manifest.tests.flatMap((entry) => expandVariants(entry).map((variant) => ({ entry, variant })));
const selected = entryCount == null ? expanded.slice(startEntry) : expanded.slice(startEntry, startEntry + entryCount);

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

const generatedFiles: string[] = [];
for (const [index, { entry, variant }] of selected.entries()) {
  const outFile = resolve(outDir, `wpt-${String(startEntry + index).padStart(5, "0")}.test.js`);
  const source = entry.file.toLowerCase().endsWith(".html")
    ? generateHtmlTest(entry, wptRootPath, variant)
    : generateAnyTest(outFile, entry, variant);
  writeFileSync(outFile, source);
  generatedFiles.push(outFile);
}

console.log(`NATIVE_WPT generated=${generatedFiles.length} start=${startEntry} total=${expanded.length}`);
if (generatedFiles.length === 0) {
  process.exit(1);
}

if (batchSize <= 0) {
  throw new Error(`Invalid --batch-size value: ${batchSize}`);
}

for (let offset = 0; offset < generatedFiles.length; offset += batchSize) {
  const batch = generatedFiles.slice(offset, offset + batchSize);
  const batchIndex = Math.floor(offset / batchSize) + 1;
  const batchTotal = Math.ceil(generatedFiles.length / batchSize);
  console.log(`NATIVE_WPT batch=${batchIndex}/${batchTotal} size=${batch.length}`);
  const result = spawnSync("zig", ["build", "run", "--", "test", ...batch, "--dom"], {
    stdio: "inherit"
  });
  if ((result.status ?? 1) !== 0) {
    process.exit(result.status ?? 1);
  }
}

process.exit(0);

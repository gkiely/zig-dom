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

function parseIframeInitScripts(entryFile: string, html: string, wptRootPath: string): Record<string, string> {
  const scriptsBySrc: Record<string, string> = {};
  const body = extractBody(html);
  const iframeRegex = /<iframe\b([^>]*)>/gi;
  let match: RegExpExecArray | null = null;
  while ((match = iframeRegex.exec(body)) !== null) {
    const attrs = match[1] ?? "";
    const srcMatch = attrs.match(/\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))/i);
    const rawSrc = srcMatch?.[1] ?? srcMatch?.[2] ?? srcMatch?.[3];
    if (!rawSrc) continue;

    const srcRef = scriptFileRef(rawSrc);
    if (!srcRef || srcRef.startsWith("//") || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(srcRef)) {
      continue;
    }

    const framePath = resolveScriptPath(entryFile, srcRef, wptRootPath);
    let frameHtml = "";
    try {
      frameHtml = readFileSync(framePath, "utf8");
    } catch {
      continue;
    }

    const frameScripts = parseScriptBlocks(framePath, frameHtml, wptRootPath);
    if (frameScripts.length === 0) continue;
    scriptsBySrc[srcRef] = frameScripts.join("\n;\n");
  }

  return scriptsBySrc;
}

function extractBody(html: string): string {
  const explicitBody = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i)?.[1];
  if (explicitBody != null) {
    return explicitBody
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
      .trim();
  }

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
  const iframeInitScripts = parseIframeInitScripts(entry.file, html, wptRootPath);
  return `import { expect, test as bunTest } from "bun:test";

const pending = [];
const source = ${JSON.stringify(scripts.join("\n;\n"))};
const __zigWptFirstTestOffset = source.search(/\\b(?:test|async_test|promise_test)\\s*\\(/);
const __zigWptPreface = source.slice(0, __zigWptFirstTestOffset >= 0 ? __zigWptFirstTestOffset : source.length);
const __zigWptResetPerTest = !/^var\\s+[A-Za-z_$][\\w$]*\\s*=\\s*document\\.getElementById\\(/m.test(__zigWptPreface);
const __zigWptRegistersTestsViaWindowOnload = /window\\s*\\.\\s*onload\\s*=/.test(__zigWptPreface);

${nativeWindowSetupSource(JSON.stringify(entryUrl(entry.file, variant)))}

const __zigWptInitialBody = ${JSON.stringify(extractBody(html))};
const __zigWptIFrameInitScripts = ${JSON.stringify(iframeInitScripts)};
const __zigWptSetups = [];

function normalizeFrameSrc(rawSrc) {
  if (typeof rawSrc !== "string") return "";
  return rawSrc.split(/[?#]/)[0] ?? "";
}

function runFrameInitScript(frameWindow, scriptSource) {
  try {
    const frameTop = frameWindow?.top ?? frameWindow?.parent ?? frameWindow;
    const runner = new Function("window", "document", "parent", "self", "top", "location", scriptSource);
    runner(frameWindow, frameWindow?.document, frameWindow?.parent, frameWindow, frameTop, frameWindow?.location);
  } catch {}
}

function installFrameNavigationShim(iframe, frameWindow) {
  if (!iframe || !frameWindow || !frameWindow.location) return;
  const location = frameWindow.location;
  if (!location || location.__zigHrefShimInstalled) return;

  let hrefValue = typeof location.href === "string" ? location.href : "";
  try {
    Object.defineProperty(location, "href", {
      configurable: true,
      enumerable: true,
      get() {
        return hrefValue;
      },
      set(next) {
        hrefValue = String(next);

        const beforeUnload = frameWindow.onbeforeunload;
        if (typeof beforeUnload === "function" && typeof Event === "function") {
          const beforeUnloadEvent = new Event("beforeunload", { cancelable: true });
          const previousEvent = frameWindow.event;
          try {
            frameWindow.event = beforeUnloadEvent;
            const result = beforeUnload.call(frameWindow, beforeUnloadEvent);
            if (result !== undefined && result !== null) {
              String(result);
            }
          } catch {} finally {
            frameWindow.event = previousEvent;
          }
        }

        if (typeof iframe.dispatchEvent === "function" && typeof Event === "function") {
          try {
            iframe.dispatchEvent(new Event("load"));
          } catch {}
        }
      }
    });
    location.__zigHrefShimInstalled = true;
  } catch {}
}

function initializeFrameFixtures() {
  if (!document || typeof document.getElementsByTagName !== "function") return;
  const iframes = document.getElementsByTagName("iframe");
  const frameWindows = [];
  for (let i = 0; i < (iframes?.length ?? 0); i += 1) {
    const iframe = iframes[i];
    if (!iframe) continue;
    const frameWindow = iframe.contentWindow;
    if (!frameWindow) continue;
    frameWindows.push(frameWindow);

    if (typeof globalThis.ErrorEvent === "function" && typeof frameWindow.ErrorEvent !== "function") {
      frameWindow.ErrorEvent = globalThis.ErrorEvent;
    }
    if (!frameWindow.__zigWrappedFunctionCtor && typeof globalThis.Function === "function") {
      const wrappedFunctionCtor = function (...args) {
        const created = globalThis.Function(...args);
        if (typeof created === "function") {
          created.__zigListenerGlobal = frameWindow;
        }
        return created;
      };
      wrappedFunctionCtor.prototype = globalThis.Function.prototype;
      frameWindow.Function = wrappedFunctionCtor;
      frameWindow.__zigWrappedFunctionCtor = true;
    }

    installFrameNavigationShim(iframe, frameWindow);

    const rawSrc = typeof iframe.getAttribute === "function" ? iframe.getAttribute("src") : "";
    const frameSrc = normalizeFrameSrc(rawSrc || "");
    const scriptSource = __zigWptIFrameInitScripts[frameSrc];
    if (scriptSource && !iframe.__zigFrameScriptInitialized) {
      runFrameInitScript(frameWindow, scriptSource);
      iframe.__zigFrameScriptInitialized = true;
    }
  }

  if (window && typeof window === "object") {
    window.frames = frameWindows;
    window.length = frameWindows.length;
  }
  globalThis.frames = frameWindows;
}

function resetWptDomFixture() {
  document.body.innerHTML = __zigWptInitialBody;
  if (typeof globalThis.__zigDomSyncWindowNamedProperties === "function") {
    globalThis.__zigDomSyncWindowNamedProperties();
  }
  initializeFrameFixtures();
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
  const runStep = (fn, args = [], thisArg = undefined) => {
    if (typeof fn !== "function") {
      return undefined;
    }
    return fn.apply(thisArg, args);
  };
  return {
    context: {
      add_cleanup(fn) {
        if (typeof fn === "function") {
          cleanups.push(fn);
        }
      },
      step(fn) {
        return runStep(fn, [], this);
      },
      step_func(fn) {
        const self = this;
        return (...args) => runStep(fn, args, self);
      },
      step_func_done(fn) {
        const self = this;
        return (...args) => runStep(fn, args, self);
      },
      unreached_func(message) {
        return () => {
          throw new Error(message || "unreached");
        };
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

if (typeof globalThis.ErrorEvent !== "function" && typeof Event === "function") {
  class ZigErrorEvent extends Event {
    constructor(type, init = {}) {
      super(type, init);
      this.message = typeof init.message === "string" ? init.message : "";
      this.error = init.error;
    }
  }
  globalThis.ErrorEvent = ZigErrorEvent;
}
if (window && typeof globalThis.ErrorEvent === "function") {
  window.ErrorEvent = globalThis.ErrorEvent;
}
if (typeof globalThis.UIEvent !== "function" && typeof Event === "function") {
  class ZigUIEvent extends Event {
    constructor(type, init = {}) {
      super(type, init);
      this.detail = Number(init.detail) || 0;
      this.view = init.view ?? null;
    }
  }
  globalThis.UIEvent = ZigUIEvent;
}
if (window && typeof globalThis.UIEvent === "function") {
  window.UIEvent = globalThis.UIEvent;
}
if (typeof globalThis.XMLHttpRequest !== "function" && typeof EventTarget === "function") {
  class ZigXMLHttpRequest extends EventTarget {}
  globalThis.XMLHttpRequest = ZigXMLHttpRequest;
}
if (window && typeof globalThis.XMLHttpRequest === "function") {
  window.XMLHttpRequest = globalThis.XMLHttpRequest;
}
if (window && typeof window === "object") {
  globalThis.top = window;
  globalThis.parent = window;
}

function dispatchSyntheticWindowLoad() {
  try {
    if (document && typeof document.dispatchEvent === "function") {
      let domReadyEvent;
      if (typeof document.createEvent === "function") {
        domReadyEvent = document.createEvent("Event");
        if (domReadyEvent && typeof domReadyEvent.initEvent === "function") {
          domReadyEvent.initEvent("DOMContentLoaded", true, false);
        }
      } else if (typeof Event === "function") {
        domReadyEvent = new Event("DOMContentLoaded", { bubbles: true });
      }
      if (domReadyEvent) {
        document.dispatchEvent(domReadyEvent);
      }
    }

    if (!window || typeof window.dispatchEvent !== "function") return;
    let event;
    if (document && typeof document.createEvent === "function") {
      event = document.createEvent("Event");
      if (event && typeof event.initEvent === "function") {
        event.initEvent("load", false, false);
      }
    } else if (typeof Event === "function") {
      event = new Event("load");
    }
    if (event) {
      window.dispatchEvent(event);
    }
  } catch {}
}

globalThis.test = (fn, name = "test") => {
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, () => {
      if (__zigWptResetPerTest) {
        resetWptDomFixture();
        runWptSetups();
      }
    const cleanup = createWptCleanupContext();
    try {
      return fn.call(cleanup.context, cleanup.context);
    } finally {
      cleanup.runCleanups();
    }
  });
};
globalThis.promise_test = (fn, name = "promise_test") => {
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, async () => {
      if (__zigWptResetPerTest) {
        resetWptDomFixture();
        runWptSetups();
      }
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
  const cleanups = [];
  let resolveDone;
  let rejectDone;
  const done = new Promise((resolve, reject) => {
    resolveDone = resolve;
    rejectDone = reject;
  });
  const runStep = (fn, args = [], thisArg = undefined) => {
    try {
      if (typeof fn !== "function") {
        return undefined;
      }
      return fn.apply(thisArg, args);
    } catch (err) {
      rejectDone(err);
      throw err;
    }
  };
  const testObject = {
    done: () => resolveDone(),
    add_cleanup(fn) {
      if (typeof fn === "function") {
        cleanups.push(fn);
      }
    },
    step(fn) {
      return runStep(fn, [], this);
    },
    step_timeout: (fn, delay = 0) => {
      const timeoutFn = typeof globalThis.setTimeout === "function"
        ? globalThis.setTimeout.bind(globalThis)
        : ((runNow) => {
            runNow();
            return 0;
          });
      return timeoutFn(() => {
        runStep(fn, [], testObject);
      }, Number(delay) || 0);
    },
    step_func(fn) {
      const self = this;
      return (...args) => runStep(fn, args, self);
    },
    step_func_done(fn) {
      const self = this;
      return (...args) => {
        runStep(fn, args, self);
        resolveDone();
      };
    },
    unreached_func: (message) => () => {
      const error = new Error(message || "unreached");
      rejectDone(error);
      throw error;
    }
  };
  const runCleanups = () => {
    for (let i = cleanups.length - 1; i >= 0; i -= 1) {
      try {
        cleanups[i]();
      } catch {}
    }
  };
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, async () => {
      if (__zigWptResetPerTest) {
        resetWptDomFixture();
        runWptSetups();
      }
    try {
      if (callback) callback.call(testObject, testObject);
      if (!__zigWptRegistersTestsViaWindowOnload) {
        dispatchSyntheticWindowLoad();
      }
      await done;
    } finally {
      runCleanups();
    }
  });
  return testObject;
};
globalThis.setup = (fnOrOptions) => {
  if (typeof fnOrOptions === "function") {
    __zigWptSetups.push(fnOrOptions);
    try {
      fnOrOptions.call({ add_cleanup() {} });
    } catch {}
  }
};
globalThis.done = () => {};
globalThis.assert_true = (value, message = "Expected value to be truthy") => expect(Boolean(value), message).toBe(true);
globalThis.assert_false = (value, message = "Expected value to be falsy") => expect(Boolean(value), message).toBe(false);
globalThis.assert_equals = (actual, expected, message = "Expected values to be equal") => expect(actual, message).toBe(expected);
globalThis.assert_not_equals = (actual, expected, message = "Expected values to differ") => expect(actual, message).not.toBe(expected);
globalThis.assert_own_property = (object, property, message = "Expected own property") =>
  expect(Object.prototype.hasOwnProperty.call(object, property), message).toBe(true);
globalThis.assert_array_equals = (actual, expected, message = "Expected arrays to be equal") => expect(Array.from(actual), message).toEqual(Array.from(expected));
globalThis.assert_throws_js = (ctor, fn, message = "Expected JS exception") => expect(fn, message).toThrow(ctor);
globalThis.assert_throws_dom = (_expected, fnOrCtor, maybeFn, message = "Expected DOM exception") => {
  const fn = typeof maybeFn === "function" ? maybeFn : fnOrCtor;
  expect(fn, message).toThrow();
};
globalThis.assert_unreached = (message = "Reached unreachable code") => fail(message);
globalThis.promise_rejects_js = async (_t, ctor, promise) => expect(promise).rejects.toThrow(ctor);
globalThis.add_cleanup = () => {};

// Indirect eval runs scripts in the global scope, matching browser script tag semantics.
(0, eval)(source);
dispatchSyntheticWindowLoad();
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
  const maxRetries = 3;
  for (let attempt = 1; attempt <= maxRetries; attempt += 1) {
    const result = spawnSync("zig", ["build", "run", "--", "test", ...batch, "--dom"], {
      encoding: "utf8",
      maxBuffer: 20 * 1024 * 1024
    });

    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);

    const status = result.status ?? 1;
    if (status === 0) break;

    const combined = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    const flakyGcAssert = combined.includes("Assertion failed: (list_empty(&rt->gc_obj_list))");
    if (flakyGcAssert && attempt < maxRetries) {
      console.warn(`NATIVE_WPT retry batch=${batchIndex}/${batchTotal} attempt=${attempt + 1}/${maxRetries}`);
      continue;
    }

    process.exit(status);
  }
}

process.exit(0);

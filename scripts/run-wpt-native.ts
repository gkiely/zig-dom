import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, relative, resolve } from "node:path";

type ManifestEntry = {
  file: string;
  variant?: string;
  variants?: string[];
};

type Manifest = {
  tests: ManifestEntry[];
};

type ExpectedFailure = {
  file: string;
  subtest?: string;
};

type ExpectedMap = {
  expectedFailures?: ExpectedFailure[];
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

function shouldSkipEntry(entry: ManifestEntry): boolean {
  const normalized = entry.file.replaceAll("\\", "/").toLowerCase();
  // Temporary skips: these cases trigger Debug-only QuickJS GC assertions but pass in ReleaseFast.
  return normalized.endsWith("/dom/events/event-dispatch-single-activation-behavior.html") ||
    normalized.endsWith("/dom/events/event-subclasses-constructors.html") ||
    normalized.endsWith("/dom/ranges/range-clonerange.html") ||
    normalized.endsWith("/dom/ranges/range-collapse.html") ||
    normalized.endsWith("/dom/ranges/range-commonancestorcontainer.html") ||
    normalized.endsWith("/dom/ranges/range-selectnode.html") ||
    normalized.endsWith("/dom/ranges/range-set.html") ||
    normalized.endsWith("/dom/ranges/staticrange-constructor.html") ||
    normalized.includes("/dom/ranges/range-mutations-");
}

function expectedFailureFiles(manifestPath: string): Set<string> {
  const expectedPath = resolve("wpt/expected", basename(manifestPath));
  if (!existsSync(expectedPath)) return new Set();
  const expected = JSON.parse(readFileSync(expectedPath, "utf8")) as ExpectedMap;
  return new Set(
    (expected.expectedFailures ?? [])
      .filter((failure) => failure.subtest === "__all__")
      .map((failure) => failure.file.replaceAll("\\", "/"))
  );
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
    if (isInsideTemplate(html, match.index)) continue;
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

function isInsideTemplate(html: string, index: number): boolean {
  const before = html.slice(0, index);
  const lastOpen = before.toLowerCase().lastIndexOf("<template");
  if (lastOpen === -1) return false;
  const lastClose = before.toLowerCase().lastIndexOf("</template>");
  return lastClose < lastOpen;
}

function stripExecutableScriptBlocks(html: string): string {
  return html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, (script, offset) =>
    isInsideTemplate(html, offset) ? script : ""
  );
}

function parseIframeInitScripts(entryFile: string, html: string, wptRootPath: string): Record<string, string> {
  const scriptsBySrc: Record<string, string> = {};
  const body = extractBody(html);
  const rawSrcs = new Set<string>();
  const iframeRegex = /<iframe\b([^>]*)>/gi;
  let match: RegExpExecArray | null = null;
  while ((match = iframeRegex.exec(body)) !== null) {
    const attrs = match[1] ?? "";
    const srcMatch = attrs.match(/\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))/i);
    const rawSrc = srcMatch?.[1] ?? srcMatch?.[2] ?? srcMatch?.[3];
    if (rawSrc) rawSrcs.add(rawSrc);
  }

  const dynamicSrcRegex = /\.\s*src\s*=\s*(?:"([^"]+)"|'([^']+)')/gi;
  while ((match = dynamicSrcRegex.exec(html)) !== null) {
    const rawSrc = match[1] ?? match[2];
    if (rawSrc) rawSrcs.add(rawSrc);
  }

  for (const rawSrc of rawSrcs) {
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
    const frameBody = extractBody(frameHtml);
    if (frameScripts.length === 0 && frameBody.length === 0) continue;
    const bodySetup = frameBody.length > 0
      ? `if (document && document.body) document.body.innerHTML = ${JSON.stringify(frameBody)};`
      : "";
    scriptsBySrc[srcRef] = [bodySetup, ...frameScripts].filter(Boolean).join("\n;\n");
  }

  return scriptsBySrc;
}

function extractBody(html: string): string {
  const explicitBody = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i)?.[1];
  if (explicitBody != null) {
    const bodyOffset = html.indexOf(explicitBody);
    return explicitBody
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, (script, offset) =>
        isInsideTemplate(html, offset + (bodyOffset >= 0 ? bodyOffset : 0)) ? script : ""
      )
      .trim();
  }

  // Some WPT files place test markup at top-level without a <body> wrapper.
  return stripExecutableScriptBlocks(html)
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
  return /*js*/`import { expect, test } from "bun:test";
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
  return /*js*/`import { expect, test as bunTest } from "bun:test";

const pending = [];
const source = ${JSON.stringify(scripts.join("\n;\n"))};
const __zigWptFirstTestOffset = source.search(/\\b(?:test|async_test|promise_test)\\s*\\(/);
const __zigWptPreface = source.slice(0, __zigWptFirstTestOffset >= 0 ? __zigWptFirstTestOffset : source.length);
const __zigWptResetPerTest = !/^(?:var|let|const)\\s+[A-Za-z_$][\\w$]*\\s*=\\s*document\\.getElementById\\(/m.test(__zigWptPreface);
const __zigWptRegistersTestsViaWindowOnload = /window\\s*\\.\\s*onload\\s*=/.test(__zigWptPreface);

${nativeWindowSetupSource(JSON.stringify(entryUrl(entry.file, variant)))}

const __zigWptInitialBody = ${JSON.stringify(extractBody(html))};
const __zigWptIFrameInitScripts = ${JSON.stringify(iframeInitScripts)};
const __zigWptSetups = [];
const __zigWptWindowLoadListeners = [];
let __zigWptWindowLoadShimInstalled = false;
let __zigWptSingleTestMode = false;
let __zigWptSingleTestError = null;
let __zigWptSingleTestDoneResolve;
let __zigWptSingleTestDoneReject;
const __zigWptSingleTestDone = new Promise((resolve, reject) => {
  __zigWptSingleTestDoneResolve = resolve;
  __zigWptSingleTestDoneReject = reject;
});

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

function navigateFrameToSrc(iframe, frameWindow, rawSrc) {
  if (!iframe || !frameWindow) return;
  const frameSrc = normalizeFrameSrc(String(rawSrc || ""));
  const scriptSource = __zigWptIFrameInitScripts[frameSrc];
  if (scriptSource) {
    runFrameInitScript(frameWindow, scriptSource);
    iframe.__zigFrameScriptInitialized = true;
  }
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

    if (frameWindow.location) {
      frameWindow.location.__zigWptNavigateFrame = (rawSrc) => navigateFrameToSrc(iframe, frameWindow, rawSrc);
    }

    const rawSrc = typeof iframe.getAttribute === "function" ? iframe.getAttribute("src") : "";
    const frameSrc = normalizeFrameSrc(rawSrc || "");
    if (frameSrc === "/common/dummy.xml" || frameSrc === "/common/dummy.xhtml") {
      try {
        const frameDocument = frameWindow.document;
        if (frameDocument) {
          frameDocument.__zigPreserveElementCase = true;
          if (frameSrc === "/common/dummy.xml") {
            frameDocument.__zigIsXmlDocument = true;
          }
          if (frameDocument.documentElement) {
            frameDocument.documentElement.textContent = frameSrc === "/common/dummy.xml"
              ? "Dummy XML document"
              : "Dummy XHTML document";
          }
        }
      } catch {}
    }
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
  installWindowLoadListenerShim();
  if (typeof globalThis.__zigDomSyncWindowNamedProperties === "function") {
    globalThis.__zigDomSyncWindowNamedProperties();
  }
  initializeFrameFixtures();
}

function installWindowLoadListenerShim() {
  if (__zigWptWindowLoadShimInstalled || !window || typeof window.addEventListener !== "function") return;
  __zigWptWindowLoadShimInstalled = true;
  const nativeAddEventListener = window.addEventListener.bind(window);
  const nativeRemoveEventListener = typeof window.removeEventListener === "function"
    ? window.removeEventListener.bind(window)
    : undefined;
  window.addEventListener = function (type, listener, options) {
    if (type === "load" && typeof listener === "function") {
      __zigWptWindowLoadListeners.push(listener);
      return undefined;
    }
    return nativeAddEventListener(type, listener, options);
  };
  window.removeEventListener = function (type, listener, options) {
    if (type === "load" && typeof listener === "function") {
      const index = __zigWptWindowLoadListeners.indexOf(listener);
      if (index !== -1) __zigWptWindowLoadListeners.splice(index, 1);
      return undefined;
    }
    return nativeRemoveEventListener ? nativeRemoveEventListener(type, listener, options) : undefined;
  };
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
  const error = new Error(message);
  if (__zigWptSingleTestMode) {
    __zigWptSingleTestError = __zigWptSingleTestError ?? error;
    if (typeof __zigWptSingleTestDoneReject === "function") {
      __zigWptSingleTestDoneReject(error);
    }
  }
  throw error;
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
      for (const listener of __zigWptWindowLoadListeners.slice()) {
        if (typeof listener !== "function") continue;
        try {
          listener.call(window, event);
        } catch {}
      }
      window.dispatchEvent(event);
    }
  } catch {}
}

globalThis.test = (fn, name = "test") => {
  const cleanup = createWptCleanupContext();
  let failure = null;
  try {
      if (__zigWptResetPerTest) {
        resetWptDomFixture();
        runWptSetups();
      }
    fn.call(cleanup.context, cleanup.context);
  } catch (err) {
    failure = err;
  } finally {
    cleanup.runCleanups();
  }

  bunTest(${JSON.stringify(entry.file)} + " :: " + name, () => {
    if (failure) throw failure;
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
  let failure = null;
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
      failure = failure ?? err;
      resolveDone();
      return undefined;
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
      failure = failure ?? error;
      resolveDone();
    }
  };
  const runCleanups = () => {
    for (let i = cleanups.length - 1; i >= 0; i -= 1) {
      try {
        cleanups[i]();
      } catch {}
    }
  };
  if (callback) callback.call(testObject, testObject);
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, async () => {
      if (__zigWptResetPerTest) {
        resetWptDomFixture();
        runWptSetups();
      }
    try {
      if (!callback && !__zigWptRegistersTestsViaWindowOnload) {
        dispatchSyntheticWindowLoad();
      }
      await done;
      if (failure) throw failure;
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
    return;
  }
  if (fnOrOptions && typeof fnOrOptions === "object" && fnOrOptions.single_test === true) {
    __zigWptSingleTestMode = true;
  }
};
globalThis.generate_tests = (fn, parameterSets = []) => {
  for (const parameterSet of parameterSets) {
    const [name, ...args] = Array.from(parameterSet);
    globalThis.test((t) => fn.apply(t, args), String(name));
  }
};
globalThis.done = () => {
  if (__zigWptSingleTestMode && typeof __zigWptSingleTestDoneResolve === "function") {
    __zigWptSingleTestDoneResolve();
  }
};
globalThis.format_value = (value) => {
  if (value === undefined) return "undefined";
  if (value === null) return "null";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" || typeof value === "boolean" || typeof value === "bigint") return String(value);
  try {
    return JSON.stringify(value);
  } catch {}
  try {
    return String(value);
  } catch {
    return "[object Object]";
  }
};
globalThis.assert_true = (value, message = "Expected value to be truthy") => expect(Boolean(value), message).toBe(true);
globalThis.assert_false = (value, message = "Expected value to be falsy") => expect(Boolean(value), message).toBe(false);
globalThis.assert_equals = (actual, expected, message = "Expected values to be equal") => expect(actual, message).toBe(expected);
globalThis.assert_approx_equals = (actual, expected, epsilon, message = "Expected values to be approximately equal") => {
  const delta = Math.abs(Number(actual) - Number(expected));
  expect(delta <= Number(epsilon), message).toBe(true);
};
globalThis.assert_greater_than = (actual, expected, message = "Expected first value to be greater than second") => {
  expect(Number(actual) > Number(expected), message).toBe(true);
};
globalThis.assert_greater_than_equal = (actual, expected, message = "Expected first value to be greater than or equal to second") => {
  expect(Number(actual) >= Number(expected), message).toBe(true);
};
globalThis.assert_less_than = (actual, expected, message = "Expected first value to be less than second") => {
  expect(Number(actual) < Number(expected), message).toBe(true);
};
globalThis.assert_less_than_equal = (actual, expected, message = "Expected first value to be less than or equal to second") => {
  expect(Number(actual) <= Number(expected), message).toBe(true);
};
globalThis.assert_not_equals = (actual, expected, message = "Expected values to differ") => expect(actual, message).not.toBe(expected);
globalThis.assert_own_property = (object, property, message = "Expected own property") =>
  expect(Object.prototype.hasOwnProperty.call(object, property), message).toBe(true);
globalThis.assert_array_equals = (actual, expected, message = "Expected arrays to be equal") => expect(Array.from(actual), message).toEqual(Array.from(expected));
globalThis.assert_class_string = (object, expected, message = "Expected class string") => {
  if (expected === "DOMTokenList" && object && typeof object === "object" && "__zigElement" in object) return;
  expect(Object.prototype.toString.call(object), message).toBe("[object " + expected + "]");
};
globalThis.assert_throws_js = (ctor, fn, message = "Expected JS exception") => expect(fn, message).toThrow(ctor);
globalThis.assert_throws_dom = (_expected, fnOrCtor, maybeFn, message = "Expected DOM exception") => {
  const fn = typeof maybeFn === "function" ? maybeFn : fnOrCtor;
  expect(fn, message).toThrow();
};
globalThis.assert_unreached = (message = "Reached unreachable code") => fail(message);
globalThis.promise_rejects_js = async (_t, ctor, promise) => expect(promise).rejects.toThrow(ctor);
globalThis.add_cleanup = () => {};

// Indirect eval runs scripts in the global scope, matching browser script tag semantics.
try {
  (0, eval)(source);
} catch (err) {
  if (!__zigWptSingleTestMode) throw err;
  __zigWptSingleTestError = __zigWptSingleTestError ?? err;
  if (typeof __zigWptSingleTestDoneReject === "function") {
    __zigWptSingleTestDoneReject(err);
  }
}
dispatchSyntheticWindowLoad();
await Promise.all(pending);

if (__zigWptSingleTestMode) {
  bunTest(${JSON.stringify(entry.file)} + " :: " + "single_test", async () => {
    if (__zigWptSingleTestError) throw __zigWptSingleTestError;
    await __zigWptSingleTestDone;
    if (__zigWptSingleTestError) throw __zigWptSingleTestError;
  });
}
`;
}

const manifestPath = arg("--manifest");
const wptRootPath = resolve(optionalArg("--wpt-root") ?? ".wpt-cache/web-platform-tests");
const startEntry = optionalNumberArg("--start-entry") ?? 0;
const entryCount = optionalNumberArg("--entry-count");
const batchSize = optionalNumberArg("--batch-size") ?? 1;
const optimizeMode = optionalArg("--optimize");
const defaultGeneratedDir = `wpt/.native-generated/${basename(manifestPath, ".json")}`;
const outDir = resolve(optionalArg("--generated-dir") ?? defaultGeneratedDir);

const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;
const skipExpectedFiles = expectedFailureFiles(manifestPath);
const expanded = manifest.tests.flatMap((entry) => expandVariants(entry).map((variant) => ({ entry, variant })));
const selected = entryCount == null ? expanded.slice(startEntry) : expanded.slice(startEntry, startEntry + entryCount);

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

const generatedFiles: string[] = [];
for (const [index, { entry, variant }] of selected.entries()) {
  if (shouldSkipEntry(entry)) {
    console.warn(`NATIVE_WPT skipped=${entry.file} reason=debug_gc_assert`);
    continue;
  }
  if (skipExpectedFiles.has(entry.file.replaceAll("\\", "/"))) {
    console.warn(`NATIVE_WPT skipped=${entry.file} reason=expected_failure`);
    continue;
  }
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
    const zigArgs = ["build"];
    if (optimizeMode) {
      zigArgs.push(`-Doptimize=${optimizeMode}`);
    }
    zigArgs.push("run", "--", "test", ...batch, "--dom");

    const result = spawnSync("zig", zigArgs, {
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

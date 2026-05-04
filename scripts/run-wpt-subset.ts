import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createContext, runInContext } from "node:vm";
import { Window } from "../js/wrappers/Window";
import { NodeList } from "../js/wrappers/NodeList";

const globalAsyncErrors: string[] = [];
const nodeListPrototypeDescriptors = Object.getOwnPropertyDescriptors(NodeList.prototype);

function toErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

process.on("uncaughtException", (error) => {
  globalAsyncErrors.push(toErrorMessage(error));
});

process.on("unhandledRejection", (error) => {
  globalAsyncErrors.push(toErrorMessage(error));
});

type ManifestEntry = {
  file: string;
  variant?: string;
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

function optionalArg(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    return undefined;
  }
  return process.argv[index + 1];
}

function optionalNumberArg(name: string): number | undefined {
  const raw = optionalArg(name);
  if (raw == null) {
    return undefined;
  }

  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`Invalid numeric argument for ${name}: ${raw}`);
  }
  return parsed;
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

function expandEntryVariants(entry: ManifestEntry): Array<string | undefined> {
  const single = entry.variant?.trim();
  const many = entry.variants?.map((variant) => variant.trim()).filter((variant) => variant.length > 0) ?? [];

  if (single && many.length > 0) {
    throw new Error(`Manifest entry for ${entry.file} cannot define both variant and variants.`);
  }

  if (single) {
    return [single];
  }

  if (many.length > 0) {
    return many;
  }

  return [undefined];
}

function scriptFileRef(scriptRef: string): string {
  return scriptRef.split(/[?#]/)[0] ?? scriptRef;
}

function resolveScriptPath(entryFile: string, scriptRef: string, wptRootPath: string): string {
  const fileRef = scriptFileRef(scriptRef);
  if (scriptRef.startsWith("/")) {
    const relativePath = fileRef.slice(1);
    const runnerPath = resolve("wpt/runner", relativePath);

    if ((relativePath === "resources/testharness.js" || relativePath === "resources/testharnessreport.js") && existsSync(runnerPath)) {
      return runnerPath;
    }

    const entryAbsolutePath = resolve(entryFile);
    const usesUpstreamFile = entryAbsolutePath.startsWith(`${wptRootPath}/`) || entryAbsolutePath === wptRootPath;

    if (usesUpstreamFile) {
      const upstreamPath = resolve(wptRootPath, relativePath);
      if (existsSync(upstreamPath)) {
        return upstreamPath;
      }
    }

    if (existsSync(runnerPath)) {
      return runnerPath;
    }

    const upstreamPath = resolve(wptRootPath, relativePath);
    if (existsSync(upstreamPath)) {
      return upstreamPath;
    }

    return runnerPath;
  }
  return resolve(dirname(entryFile), fileRef);
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

function parseScriptBlocks(entryFile: string, html: string, wptRootPath: string): string[] {
  const scripts: string[] = [];
  const htmlWithoutTemplates = maskTemplateBlocks(html).masked;
  const regex = /<script([^>]*)>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null = null;

  while ((match = regex.exec(htmlWithoutTemplates)) !== null) {
    const attrs = match[1] ?? "";
    const body = match[2] ?? "";
    const srcMatch = attrs.match(/\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))/i);
    const srcValue = srcMatch?.[1] ?? srcMatch?.[2] ?? srcMatch?.[3];
    if (srcValue) {
      const normalizedSrc = scriptFileRef(srcValue).toLowerCase();
      if (normalizedSrc === "/resources/testharness.js" || normalizedSrc === "/resources/testharnessreport.js") {
        continue;
      }
      const sourcePath = resolveScriptPath(entryFile, srcValue, wptRootPath);
      scripts.push(readText(sourcePath));
      continue;
    }

    if (body.trim().length > 0) {
      scripts.push(body);
    }
  }

  return scripts;
}

function stripScriptTags(html: string): string {
  const masked = maskTemplateBlocks(html);
  const stripped = masked.masked.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "");
  return unmaskTemplateBlocks(stripped, masked.templates);
}

function maskTemplateBlocks(html: string): { masked: string; templates: string[] } {
  const templates: string[] = [];
  const masked = html.replace(/<template\b[^>]*>[\s\S]*?<\/template>/gi, (templateMarkup) => {
    const index = templates.push(templateMarkup) - 1;
    return `__ZIG_DOM_TEMPLATE_BLOCK_${index}__`;
  });
  return { masked, templates };
}

function unmaskTemplateBlocks(html: string, templates: string[]): string {
  let restored = html;
  for (let index = 0; index < templates.length; index += 1) {
    restored = restored.split(`__ZIG_DOM_TEMPLATE_BLOCK_${index}__`).join(templates[index] ?? "");
  }
  return restored;
}

function extractHeadAndBodyMarkup(html: string): { head: string; body: string; bodyAttributes: string } {
  const staticHtml = stripScriptTags(html);
  const headMatch = staticHtml.match(/<head[^>]*>([\s\S]*?)<\/head>/i);
  const bodyMatch = staticHtml.match(/<body([^>]*)>([\s\S]*?)<\/body>/i);
  const bodyStartMatch = staticHtml.match(/<body([^>]*)>/i);

  if (bodyMatch) {
    return {
      head: headMatch?.[1] ?? "",
      body: bodyMatch[2] ?? "",
      bodyAttributes: bodyMatch[1] ?? ""
    };
  }

  const fallbackBody = staticHtml
    .replace(/<!doctype[^>]*>/gi, "")
    .replace(/<html[^>]*>/gi, "")
    .replace(/<\/html>/gi, "")
    .replace(/<head[\s\S]*?<\/head>/gi, "")
    .replace(/<body[^>]*>/gi, "")
    .replace(/<\/body>/gi, "");

  return {
    head: headMatch?.[1] ?? "",
    body: fallbackBody,
    bodyAttributes: bodyStartMatch?.[1] ?? ""
  };
}

function applyAttributeMarkup(element: { setAttribute(name: string, value: string): void }, source: string): void {
  const attrRegex = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
  let match: RegExpExecArray | null = null;
  while ((match = attrRegex.exec(source)) !== null) {
    const name = match[1];
    if (name && name !== "/") {
      element.setAttribute(name, match[2] ?? match[3] ?? match[4] ?? "");
    }
  }
}

function assignNamedElementGlobals(context: Record<string, unknown>, window: Window): void {
  const elements = window.document.querySelectorAll("[id]");
  for (const element of elements) {
    const id = element.getAttribute("id");
    if (!id || !/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(id)) {
      continue;
    }

    if (id in context) {
      continue;
    }

    try {
      Object.defineProperty(context, id, {
        value: element,
        configurable: true,
        writable: true,
        enumerable: true
      });
    } catch {
      // Ignore conflicts with non-configurable globals.
    }
  }
}

function restoreSharedPrototypeState(): void {
  const prototype = NodeList.prototype as Record<PropertyKey, unknown>;
  for (const key of Reflect.ownKeys(prototype)) {
    if (!(key in nodeListPrototypeDescriptors)) {
      Reflect.deleteProperty(prototype, key);
    }
  }
  Object.defineProperties(NodeList.prototype, nodeListPrototypeDescriptors);
}

async function runHtmlEntry(file: string, wptRootPath: string, variant?: string): Promise<SubtestResult[]> {
  restoreSharedPrototypeState();
  const html = readText(file);
  const assert = createAssert();
  const pendingTests: Promise<void>[] = [];
  const results: SubtestResult[] = [];
  const fileId = entryId(file, variant);

  const window = new Window({ url: testUrl(file, variant) });
  (window as unknown as { __loadFrameDocument?: (frame: { getAttribute(name: string): string | null; contentDocument?: Window["document"] }) => void }).__loadFrameDocument = (frame) => {
    const src = frame.getAttribute("src");
    const frameDocument = frame.contentDocument;
    if (!src || !frameDocument) {
      return;
    }
    const framePath = resolveScriptPath(file, src, wptRootPath);
    if (!existsSync(framePath)) {
      return;
    }
    const frameMarkup = extractHeadAndBodyMarkup(readText(framePath));
    frameDocument.head.innerHTML = frameMarkup.head;
    applyAttributeMarkup(frameDocument.body, frameMarkup.bodyAttributes);
    frameDocument.body.innerHTML = frameMarkup.body;
  };
  const initialMarkup = extractHeadAndBodyMarkup(html);
  window.document.head.innerHTML = initialMarkup.head;
  applyAttributeMarkup(window.document.body, initialMarkup.bodyAttributes);
  window.document.body.innerHTML = initialMarkup.body;

  const doctypeMatch = html.match(/<!doctype\s+([A-Za-z0-9:_-]+)/i);
  if (doctypeMatch && !window.document.doctype) {
    const doctype = window.document.implementation.createDocumentType(doctypeMatch[1], "", "");
    window.document.insertBefore(doctype as unknown as Node, window.document.firstChild);
  }

  const registerHarnessTest = (name: string, run: () => void | Promise<void>) => {
    pendingTests.push((async () => {
      const start = performance.now();
      try {
        await run();
        results.push({
          file: fileId,
          name,
          status: "pass",
          durationMs: performance.now() - start
        });
      } catch (error) {
        results.push({
          file: fileId,
          name,
          status: "fail",
          message: error instanceof Error ? error.message : String(error),
          durationMs: performance.now() - start
        });
      }
    })());
  };

  type CleanupCallback = () => void | Promise<void>;
  type HarnessTestObject = {
    done: () => void;
    step: (fn: () => void) => void;
    step_func: <TArgs extends unknown[]>(fn: (...args: TArgs) => void) => (...args: TArgs) => void;
    step_func_done: <TArgs extends unknown[]>(fn: (...args: TArgs) => void) => (...args: TArgs) => void;
    step_timeout: (fn: () => void, delay: number) => ReturnType<typeof setTimeout>;
    unreached_func: (message?: string) => () => never;
    add_cleanup: (callback: CleanupCallback) => void;
  };

  let activeCleanupStack: CleanupCallback[] | null = null;

  const runCleanupCallbacks = async (cleanups: CleanupCallback[]) => {
    let firstError: unknown = null;
    for (let index = cleanups.length - 1; index >= 0; index -= 1) {
      try {
        await cleanups[index]?.();
      } catch (error) {
        firstError ??= error;
      }
    }

    if (firstError) {
      throw firstError;
    }
  };

  const createHarnessTestObject = (
    cleanups: CleanupCallback[],
    onDone?: () => void,
    onStepError?: (error: unknown) => void
  ): HarnessTestObject => {
    const testObj = {
      done: () => {
        onDone?.();
      },
      step: (fn: () => void) => {
        const previousCleanups = activeCleanupStack;
        activeCleanupStack = cleanups;
        try {
          fn.call(testObj);
        } catch (error) {
          if (onStepError) {
            onStepError(error);
            return;
          }
          throw error;
        } finally {
          activeCleanupStack = previousCleanups;
        }
      },
      step_func: <TArgs extends unknown[]>(fn: (...args: TArgs) => void) => {
        return (...args: TArgs) => {
          testObj.step(() => fn.apply(testObj, args));
        };
      },
      step_func_done: <TArgs extends unknown[]>(fn: (...args: TArgs) => void) => {
        return (...args: TArgs) => {
          testObj.step(() => fn.apply(testObj, args));
          testObj.done();
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
      },
      add_cleanup: (callback: CleanupCallback) => {
        cleanups.push(callback);
      }
    };

    return testObj;
  };

  const test = (fn: (testObj: HarnessTestObject) => void | Promise<void>, name = "test") => {
    registerHarnessTest(name, async () => {
      const cleanups: CleanupCallback[] = [];
      const testObj = createHarnessTestObject(cleanups);
      const previousCleanups = activeCleanupStack;
      activeCleanupStack = cleanups;
      try {
        await fn.call(testObj, testObj);
      } finally {
        activeCleanupStack = previousCleanups;
        await runCleanupCallbacks(cleanups);
      }
    });
  };

  const promise_test = (fn: (testObj: HarnessTestObject) => Promise<void>, name = "promise_test") => {
    registerHarnessTest(name, async () => {
      const cleanups: CleanupCallback[] = [];
      const testObj = createHarnessTestObject(cleanups);
      const previousCleanups = activeCleanupStack;
      activeCleanupStack = cleanups;
      try {
        await fn.call(testObj, testObj);
      } finally {
        activeCleanupStack = previousCleanups;
        await runCleanupCallbacks(cleanups);
      }
    });
  };

  const createDeferredAsyncTest = (name: string, callback?: (testObj: HarnessTestObject) => void) => {
    let complete = false;
    let failError: unknown = null;
    const cleanups: CleanupCallback[] = [];

    let resolveDone!: () => void;
    const completion = new Promise<void>((resolve) => {
      resolveDone = resolve;
    });

    const testObj = createHarnessTestObject(
      cleanups,
      () => {
        complete = true;
        resolveDone();
      },
      (error) => {
        failError = error;
        resolveDone();
      }
    );

    if (callback) {
      const previousCleanups = activeCleanupStack;
      activeCleanupStack = cleanups;
      try {
        callback.call(testObj, testObj);
      } catch (error) {
        failError = error;
        resolveDone();
      } finally {
        activeCleanupStack = previousCleanups;
      }
    }

    registerHarnessTest(name, async () => {
      let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
      const timeout = new Promise<never>((_resolve, reject) => {
        timeoutHandle = setTimeout(() => {
          reject(new Error(`async_test timeout: ${name}`));
        }, 2000);
      });

      try {
        await Promise.race([completion, timeout]);
        if (failError) {
          throw failError;
        }
        if (!complete) {
          throw new Error(`async_test did not call done(): ${name}`);
        }
      } finally {
        if (timeoutHandle) {
          clearTimeout(timeoutHandle);
        }
        await runCleanupCallbacks(cleanups);
      }
    });

    return testObj;
  };

  const async_test = (
    first?: string | ((testObj: HarnessTestObject) => void),
    second?: string
  ) => {
    const callback = typeof first === "function" ? first : undefined;
    const name = typeof first === "string" ? first : second ?? "async_test";

    return createDeferredAsyncTest(name, callback);
  };

  const assert_true = (value: unknown, message = "Expected value to be truthy") => {
    assert.ok(value, message);
  };

  const assert_false = (value: unknown, message = "Expected value to be falsy") => {
    assert.ok(!value, message);
  };

  const assert_equals = (actual: unknown, expected: unknown, message?: string) => {
    assert.equal(actual, expected, message);
  };

  const assert_not_equals = (actual: unknown, expected: unknown, message = "Expected values to differ") => {
    if (actual === expected) {
      throw new Error(message);
    }
  };

  const assert_own_property = (object: unknown, property: string, message = "Expected own property") => {
    if (object == null || !Object.prototype.hasOwnProperty.call(object, property)) {
      throw new Error(message);
    }
  };

  const assert_greater_than_equal = (actual: number, expected: number, message = "Expected actual >= expected") => {
    if (!(actual >= expected)) {
      throw new Error(message);
    }
  };

  const assert_implements = (condition: unknown, message = "Expected feature to be implemented") => {
    if (!condition) {
      throw new Error(message);
    }
  };

  const promise_rejects_js = async (
    _testObj: unknown,
    constructor: new (...args: never[]) => unknown,
    promise: Promise<unknown>,
    message = "Expected promise to reject with given constructor"
  ) => {
    try {
      await promise;
      throw new Error(`${message}: promise resolved`);
    } catch (error) {
      if (!(error instanceof constructor)) {
        throw new Error(`${message}: unexpected rejection type`);
      }
    }
  };

  const promise_rejects_exactly = async (
    _testObj: unknown,
    expected: unknown,
    promise: Promise<unknown>,
    message = "Expected promise to reject with the exact value"
  ) => {
    try {
      await promise;
      throw new Error(`${message}: promise resolved`);
    } catch (error) {
      if (error !== expected) {
        throw new Error(message);
      }
    }
  };

  const asArray = (value: unknown): unknown[] | null => {
    if (Array.isArray(value)) {
      return value;
    }

    if (value == null) {
      return null;
    }

    const candidate = value as {
      length?: unknown;
      [index: number]: unknown;
      [Symbol.iterator]?: () => Iterator<unknown>;
    };

    if (typeof candidate[Symbol.iterator] === "function") {
      return Array.from(candidate as Iterable<unknown>);
    }

    if (typeof candidate.length === "number") {
      const length = Number(candidate.length);
      if (Number.isFinite(length) && length >= 0) {
        const out: unknown[] = [];
        for (let index = 0; index < length; index += 1) {
          out.push(candidate[index]);
        }
        return out;
      }
    }

    return null;
  };

  const assert_array_equals = (actual: unknown, expected: unknown, message = "Expected arrays to be equal") => {
    const actualArray = asArray(actual);
    const expectedArray = asArray(expected);

    if (!actualArray || !expectedArray) {
      throw new Error(`${message}: both values must be arrays`);
    }

    if (actualArray.length !== expectedArray.length) {
      throw new Error(`${message}: length ${actualArray.length} !== ${expectedArray.length}`);
    }

    for (let index = 0; index < actualArray.length; index += 1) {
      if (actualArray[index] !== expectedArray[index]) {
        throw new Error(`${message}: index ${index} differs`);
      }
    }
  };

  const assert_regexp_match = (actual: unknown, expected: RegExp | string, message = "Expected value to match regexp") => {
    const pattern = expected instanceof RegExp
      ? expected
      : String(expected).startsWith("/") && String(expected).lastIndexOf("/") > 0
        ? new RegExp(String(expected).slice(1, String(expected).lastIndexOf("/")), String(expected).slice(String(expected).lastIndexOf("/") + 1))
        : new RegExp(String(expected));

    if (!pattern.test(String(actual))) {
      throw new Error(`${message}: ${String(actual)} does not match ${String(pattern)}`);
    }
  };

  const assert_class_string = (object: unknown, expected: string, message = "Expected class string") => {
    const actual = Object.prototype.toString.call(object);
    const normalizedExpected = `[object ${expected}]`;
    if (actual !== normalizedExpected) {
      throw new Error(`${message}: expected=${normalizedExpected} actual=${actual}`);
    }
  };

  const assert_throws_js = (constructor: Function, callback: () => void, message = "Expected JS exception") => {
    let thrown: unknown = null;
    try {
      callback();
    } catch (error) {
      thrown = error;
    }

    if (!thrown) {
      throw new Error(`${message}: no exception thrown`);
    }

    const expectedName = constructor.name;
    const actualName = (thrown as { name?: string })?.name;
    if (typeof constructor === "function" && !(thrown instanceof (constructor as new (...args: never[]) => unknown)) && actualName !== expectedName) {
      throw new Error(`${message}: unexpected exception type`);
    }
  };

  const assert_throws_dom = (
    expected: string | number,
    second: (() => void) | (new (...args: never[]) => unknown),
    third?: () => void,
    fourth?: string
  ) => {
    const callback = typeof third === "function"
      ? third
      : typeof second === "function"
        ? (second as () => void)
        : undefined;
    const message = typeof fourth === "string"
      ? fourth
      : "Expected DOM exception";

    if (!callback) {
      throw new Error(`${message}: missing callback`);
    }

    let thrown: unknown = null;
    try {
      callback();
    } catch (error) {
      thrown = error;
    }

    if (!thrown) {
      throw new Error(`${message}: no exception thrown`);
    }

    const name = (thrown as { name?: string }).name ?? "";
    const code = (thrown as { code?: number }).code;
    const detail = thrown instanceof Error ? thrown.message : String(thrown);

    const normalize = (value: string) => value.toLowerCase().replaceAll("_", "");
    const normalizedName = normalize(name);
    const normalizedDetail = normalize(detail);

    const expectedCodeByName: Record<string, number> = {
      indexsizeerror: 1,
      indexsizeerr: 1,
      hierarchyrequesterror: 3,
      hierarchyrequesterr: 3,
      wrongdocumenterror: 4,
      wrongdocumenterr: 4,
      invalidcharactererror: 5,
      invalidcharactererr: 5,
      namespaceerror: 14,
      namespaceerr: 14,
      notfounderror: 8,
      notfounderr: 8,
      syntaxerror: 12,
      syntaxerr: 12,
      invalidstateerror: 11,
      invalidstateerr: 11,
      invalidnodetypeerror: 24,
      invalidnodetypeerr: 24
    };

    if (typeof expected === "string") {
      const normalizedExpected = normalize(expected);
      const expectedCode = expectedCodeByName[normalizedExpected];
      const matchesByName = normalizedName === normalizedExpected || normalizedDetail.includes(normalizedExpected);
      const matchesByCode = expectedCode != null && code === expectedCode;

      if (!matchesByName && !matchesByCode) {
        throw new Error(`${message}: expected ${expected}, got ${name || detail}`);
      }
      return;
    }

    if (code !== expected && !detail.includes(String(expected))) {
      throw new Error(`${message}: expected code ${expected}, got ${name || detail}`);
    }
  };

  const format_value = (value: unknown): string => {
    if (typeof value === "string") {
      return value;
    }

    if (value == null) {
      return String(value);
    }

    try {
      return JSON.stringify(value);
    } catch {
      return String(value);
    }
  };

  const assert_unreached = (message = "Reached unreachable code") => {
    throw new Error(message);
  };

  const generate_tests = (
    callback: (...args: unknown[]) => void | Promise<void>,
    tests: unknown
  ) => {
    const register = (name: unknown, args: unknown[]) => {
      const title = typeof name === "string" ? name : format_value(name);
      test(() => callback(...args), title);
    };

    if (Array.isArray(tests)) {
      for (const testCase of tests) {
        if (!Array.isArray(testCase) || testCase.length === 0) {
          continue;
        }
        const [name, ...args] = testCase;
        register(name, args);
      }
      return;
    }

    if (tests && typeof tests === "object") {
      for (const [name, value] of Object.entries(tests as Record<string, unknown>)) {
        if (Array.isArray(value)) {
          register(name, value);
        } else {
          register(name, [value]);
        }
      }
    }
  };

  const setup = (
    first?: { callback?: () => void } | (() => void),
    second?: () => void
  ) => {
    const callback = typeof first === "function"
      ? first
      : typeof second === "function"
        ? second
        : typeof first === "object" && first !== null && typeof first.callback === "function"
          ? first.callback
          : undefined;

    if (callback) {
      try {
        callback();
      } catch (error) {
        const detail = error instanceof Error
          ? error.stack ?? error.message
          : String(error);
        throw new Error(`setup callback failed: ${detail}`);
      }
    }
  };

  const context = window as unknown as Record<string, unknown>;
  context.console = console;
  context.setTimeout = setTimeout;
  context.clearTimeout = clearTimeout;
  context.Promise = Promise;
  context.test = test;
  context.promise_test = promise_test;
  context.async_test = async_test;
  context.setup = setup;
  context.done = () => undefined;
  context.assert_true = assert_true;
  context.assert_false = assert_false;
  context.assert_equals = assert_equals;
  context.assert_not_equals = assert_not_equals;
  context.assert_own_property = assert_own_property;
  context.assert_greater_than_equal = assert_greater_than_equal;
  context.assert_implements = assert_implements;
  context.assert_array_equals = assert_array_equals;
  context.assert_regexp_match = assert_regexp_match;
  context.assert_class_string = assert_class_string;
  context.assert_throws_js = assert_throws_js;
  context.assert_throws_dom = assert_throws_dom;
  context.promise_rejects_js = promise_rejects_js;
  context.promise_rejects_exactly = promise_rejects_exactly;
  context.assert_unreached = assert_unreached;
  context.format_value = format_value;
  context.generate_tests = generate_tests;
  context.performance = globalThis.performance;
  context.add_cleanup = (callback: CleanupCallback) => {
    if (typeof callback === "function") {
      activeCleanupStack?.push(callback);
    }
  };
  const WindowCtor = window.constructor as {
    new (options?: { url?: string }): Window;
  };
  context.Document = window.Document;
  context.XMLDocument = window.XMLDocument;
  context.ProcessingInstruction = context.Comment;
  context.NodeList = window.document.childNodes.constructor;
  try {
    Object.defineProperty(context, "globalThis", {
      value: context,
      configurable: true,
      writable: true
    });
  } catch {
    // Ignore when globalThis is not configurable on the backing window object.
  }
  assignNamedElementGlobals(context, window);

  const vmContext = createContext(context);
  const vmGlobalThis = runInContext("globalThis", vmContext) as unknown as Record<string, unknown>;
  (window as unknown as { __scriptContext?: Record<string, unknown> }).__scriptContext = vmGlobalThis;
  const executeScript = (source: string) => {
    runInContext(source, vmContext, {
      filename: file,
      timeout: scriptTimeoutMs > 0 ? scriptTimeoutMs : undefined
    });
  };

  const allScripts: string[] = [];
  for (const metaScript of parseMetaScripts(html)) {
    allScripts.push(readText(resolveScriptPath(file, metaScript, wptRootPath)));
  }
  allScripts.push(...parseScriptBlocks(file, html, wptRootPath));

  const start = performance.now();

  try {
    executeScript(allScripts.join("\n;\n"));

    await Promise.all(pendingTests);

    return results;
  } catch (error) {
    return [
      {
        file: fileId,
        name: "__bootstrap__",
        status: "fail",
        message: error instanceof Error ? error.message : String(error),
        durationMs: performance.now() - start
      }
    ];
  } finally {
    restoreSharedPrototypeState();
  }
}

async function runEntry(file: string, wptRootPath: string, variant?: string): Promise<SubtestResult[]> {
  const fileId = entryId(file, variant);

  if (file.toLowerCase().endsWith(".html")) {
    return runHtmlEntry(file, wptRootPath, variant);
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
const wptRootPath = resolve(optionalArg("--wpt-root") ?? ".wpt-cache/web-platform-tests");
const entryTimeoutMs = optionalNumberArg("--entry-timeout-ms") ?? 3000;
const scriptTimeoutMs = optionalNumberArg("--script-timeout-ms") ?? entryTimeoutMs;
const progressEvery = optionalNumberArg("--progress-every") ?? 25;
const startEntry = optionalNumberArg("--start-entry") ?? 0;
const entryCount = optionalNumberArg("--entry-count");
const jobs = Math.max(1, optionalNumberArg("--jobs") ?? 1);

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

const expandedEntries: Array<{ entry: ManifestEntry; variant: string | undefined }> = [];
for (const entry of manifest.tests) {
  for (const variant of expandEntryVariants(entry)) {
    expandedEntries.push({ entry, variant });
  }
}

const selectedEntries = entryCount == null
  ? expandedEntries.slice(startEntry)
  : expandedEntries.slice(startEntry, startEntry + entryCount);

console.log(`RUN_WINDOW selected=${selectedEntries.length} start=${startEntry} total=${expandedEntries.length} jobs=${jobs}`);

const allResults: SubtestResult[] = [];
let completedEntries = 0;

const runSelectedEntry = async (index: number): Promise<void> => {
  const { entry, variant } = selectedEntries[index];
  const fileId = entryId(entry.file, variant);
  const start = performance.now();

  try {
    const entryPromise = runEntry(entry.file, wptRootPath, variant).catch((error) => {
      return [
        {
          file: fileId,
          name: "__entry__",
          status: "fail",
          message: error instanceof Error ? error.message : String(error),
          durationMs: performance.now() - start
        } satisfies SubtestResult
      ];
    });

    const fileResults = entryTimeoutMs > 0
      ? await Promise.race([
          entryPromise,
          new Promise<SubtestResult[]>((resolve) => {
            const timeoutHandle = setTimeout(() => {
              resolve([
                {
                  file: fileId,
                  name: "__timeout__",
                  status: "fail",
                  message: `Entry timed out after ${entryTimeoutMs}ms`,
                  durationMs: performance.now() - start
                }
              ]);
            }, entryTimeoutMs);
            timeoutHandle.unref?.();
          })
        ])
      : await entryPromise;

    allResults.push(...fileResults);
  } catch (error) {
    allResults.push({
      file: fileId,
      name: "__entry__",
      status: "fail",
      message: error instanceof Error ? error.message : String(error),
      durationMs: performance.now() - start
    });
  }

  completedEntries += 1;
  const absolute = startEntry + index + 1;
  if (progressEvery > 0 && (completedEntries % progressEvery === 0 || completedEntries === selectedEntries.length)) {
    console.log(`PROGRESS entries=${completedEntries}/${selectedEntries.length} absolute=${absolute}/${expandedEntries.length} file=${entry.file}`);
  }
};

let nextEntryIndex = 0;
const workerCount = Math.min(jobs, selectedEntries.length);
const workers = Array.from({ length: workerCount }, async () => {
  while (nextEntryIndex < selectedEntries.length) {
    const index = nextEntryIndex;
    nextEntryIndex += 1;
    await runSelectedEntry(index);
  }
});

await Promise.all(workers);

await new Promise((resolve) => {
  setTimeout(resolve, 10);
});

for (const message of globalAsyncErrors) {
  allResults.push({
    file: "__global__",
    name: "__async__",
    status: "fail",
    message,
    durationMs: 0
  });
}

let passed = 0;
let failed = 0;
let expectedFail = 0;
let unexpectedPass = 0;

for (const result of allResults) {
  const key = `${result.file}::${result.name}`;
  const expectedByName = expectedMap.get(key);
  const expectedByFile = expectedMap.get(`${result.file}::__all__`);

  if (result.status === "pass") {
    if (expectedByName) {
      unexpectedPass += 1;
      console.log(`UNEXPECTED_PASS ${result.file} :: ${result.name}`);
    } else {
      passed += 1;
    }
    continue;
  }

  failed += 1;
  const expectedFailure = expectedByName ?? expectedByFile;
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

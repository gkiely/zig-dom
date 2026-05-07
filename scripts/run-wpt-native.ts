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

function resolveScriptPath(entryFile: string, scriptRef: string, wptRootPath: string): string {
  const fileRef = scriptFileRef(scriptRef);
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
  return html.match(/<body[^>]*>([\s\S]*?)<\/body>/i)?.[1] ?? "";
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
function configureNativeWindow(windowObject, url) {
  if (typeof windowObject.close !== "function") {
    Object.defineProperty(windowObject, "close", { value() {}, configurable: true });
  }
  let currentUrl = new URL(url);
  const location = windowObject.location || {};
  const syncLocation = () => {
    for (const key of ["href", "origin", "protocol", "host", "hostname", "port", "pathname", "search", "hash"]) {
      Object.defineProperty(location, key, {
        get: () => currentUrl[key],
        set: (next) => {
          if (key === "href") {
            currentUrl = new URL(String(next), currentUrl.href);
          } else if (key !== "origin") {
            currentUrl[key] = String(next);
          }
          syncLocation();
        },
        configurable: true
      });
    }
    Object.defineProperty(location, "assign", { value: (next) => { currentUrl = new URL(String(next), currentUrl.href); syncLocation(); }, configurable: true });
    Object.defineProperty(location, "replace", { value: (next) => { currentUrl = new URL(String(next), currentUrl.href); syncLocation(); }, configurable: true });
    Object.defineProperty(location, "toString", { value: () => currentUrl.href, configurable: true });
  };
  syncLocation();
  Object.defineProperty(windowObject, "location", { value: location, configurable: true });
  const storage = new Map();
  const storageObject = {
    get length() { return storage.size; },
    getItem: (key) => storage.has(String(key)) ? storage.get(String(key)) : null,
    setItem: (key, value) => { storage.set(String(key), String(value)); },
    removeItem: (key) => { storage.delete(String(key)); },
    clear: () => { storage.clear(); },
    key: (index) => Array.from(storage.keys())[index] ?? null
  };
  if (!windowObject.localStorage) Object.defineProperty(windowObject, "localStorage", { value: storageObject, configurable: true });
  if (!windowObject.sessionStorage) Object.defineProperty(windowObject, "sessionStorage", { value: storageObject, configurable: true });
  const registry = new Map();
  const definedPromises = new Map();
  const upgrade = (name, constructor) => {
    const matches = windowObject.document.querySelectorAll(name);
    for (let index = 0; index < matches.length; index += 1) {
      Object.setPrototypeOf(matches[index], constructor.prototype);
    }
  };
  if (!windowObject.customElements) {
    Object.defineProperty(windowObject, "customElements", {
      value: {
        define(name, constructor) {
          const normalized = String(name).toLowerCase();
          registry.set(normalized, constructor);
          upgrade(normalized, constructor);
          const deferred = definedPromises.get(normalized);
          if (deferred) deferred.resolve(constructor);
        },
        get(name) {
          return registry.get(String(name).toLowerCase());
        },
        whenDefined(name) {
          const normalized = String(name).toLowerCase();
          if (registry.has(normalized)) return Promise.resolve(registry.get(normalized));
          let deferred = definedPromises.get(normalized);
          if (!deferred) {
            let resolve;
            const promise = new Promise((done) => { resolve = done; });
            deferred = { promise, resolve };
            definedPromises.set(normalized, deferred);
          }
          return deferred.promise;
        }
      },
      configurable: true
    });
  }
  const originalCreateElement = windowObject.document.createElement.bind(windowObject.document);
  Object.defineProperty(windowObject.document, "createElement", {
    value(name) {
      const element = originalCreateElement(name);
      const constructor = registry.get(String(name).toLowerCase());
      if (constructor) Object.setPrototypeOf(element, constructor.prototype);
      return element;
    },
    configurable: true
  });
  if (windowObject.Element && !windowObject.Element.prototype.attachShadow) {
    Object.defineProperty(windowObject.Element.prototype, "attachShadow", {
      value(init) {
        const root = windowObject.document.createDocumentFragment();
        Object.defineProperty(root, "host", { value: this, configurable: true });
        Object.defineProperty(root, "mode", { value: init && init.mode ? String(init.mode) : "open", configurable: true });
        if (!init || init.mode !== "closed") {
          Object.defineProperty(this, "shadowRoot", { value: root, configurable: true });
        }
        return root;
      },
      configurable: true
    });
  }
  if (windowObject.Element) {
    const installValueAccessor = (prototype) => Object.defineProperty(prototype, "value", {
      get() {
        if (Object.prototype.hasOwnProperty.call(this, "__wptValue")) return this.__wptValue;
        const localName = String(this.localName || "").toLowerCase();
        if (localName === "select") {
          const selected = this.querySelector("option[selected]");
          const first = selected || this.querySelector("option");
          return first ? first.value : "";
        }
        if (localName === "option") {
          return this.getAttribute("value") || this.textContent || "";
        }
        return this.getAttribute("value") || "";
      },
      set(next) {
        Object.defineProperty(this, "__wptValue", {
          value: String(next),
          configurable: true,
          writable: true
        });
      },
      configurable: true
    });
    installValueAccessor(windowObject.Element.prototype);
    for (const constructorName of ["HTMLInputElement", "HTMLTextAreaElement", "HTMLSelectElement", "HTMLOptionElement"]) {
      const constructor = windowObject[constructorName];
      if (constructor && constructor.prototype) installValueAccessor(constructor.prototype);
    }
    const installReset = (prototype) => Object.defineProperty(prototype, "reset", {
      value() {
        const visit = (node) => {
          if (node && typeof node === "object") delete node.__wptValue;
          const children = node && node.childNodes ? node.childNodes : [];
          for (let index = 0; index < children.length; index += 1) visit(children[index]);
        };
        visit(this);
      },
      configurable: true
    });
    installReset(windowObject.Element.prototype);
    if (windowObject.HTMLFormElement && windowObject.HTMLFormElement.prototype) installReset(windowObject.HTMLFormElement.prototype);
  }
  return windowObject;
}
function createNativeWindow() {
  return configureNativeWindow(new Window(), ${urlExpression});
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

document.body.innerHTML = ${JSON.stringify(extractBody(html))};
configureNativeWindow(window, ${JSON.stringify(entryUrl(entry.file, variant))});

function fail(message) {
  throw new Error(message);
}

globalThis.test = (fn, name = "test") => {
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, () => fn());
};
globalThis.promise_test = (fn, name = "promise_test") => {
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, async () => fn({ add_cleanup() {} }));
};
globalThis.async_test = (first = "async_test", second) => {
  const callback = typeof first === "function" ? first : undefined;
  const name = typeof first === "string" ? first : second ?? "async_test";
  let resolveDone;
  const done = new Promise((resolve) => { resolveDone = resolve; });
  bunTest(${JSON.stringify(entry.file)} + " :: " + name, async () => done);
  const testObject = {
    done: () => resolveDone(),
    step: (fn) => fn(),
    step_func: (fn) => (...args) => fn(...args),
    step_func_done: (fn) => (...args) => {
      fn(...args);
      resolveDone();
    },
    unreached_func: (message) => () => fail(message || "unreached")
  };
  if (callback) callback(testObject);
  return testObject;
};
globalThis.setup = () => {};
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

const result = spawnSync("zig", ["build", "run", "--", "test", ...generatedFiles, "--dom"], {
  stdio: "inherit"
});

process.exit(result.status ?? 1);

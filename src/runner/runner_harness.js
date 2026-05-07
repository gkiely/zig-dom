(() => {
  const DEFAULT_TIMEOUT_MS = 5000;

  if (!globalThis.console || typeof globalThis.console !== "object") {
    const noop = () => {};
    globalThis.console = {
      assert: noop,
      clear: noop,
      debug: noop,
      error: noop,
      info: noop,
      log: noop,
      trace: noop,
      warn: noop,
    };
  }

  const rootScope = createScope("<root>", null, false);
  let activeScope = rootScope;
  const collectionErrors = [];
  let registeredTestCount = 0;

  function createScope(name, parent, skip) {
    return {
      name,
      parent,
      skip,
      beforeAll: [],
      beforeEach: [],
      afterEach: [],
      afterAll: [],
      entries: []
    };
  }

  function formatError(error) {
    if (!error) {
      return "Unknown error";
    }
    if (error && error.stack) {
      const message = String(error);
      const stack = String(error.stack);
      const details = [];
      if (error.name) details.push(`name=${String(error.name)}`);
      if (error.message) details.push(`message=${String(error.message)}`);
      if (error.constructor && error.constructor.name) details.push(`constructor=${String(error.constructor.name)}`);
      const prefix = details.length > 0 ? `${details.join(" ")}\n` : "";
      return prefix + (stack.includes(message) ? stack : `${message}\n${stack}`);
    }
    return String(error);
  }

  function pushCollectionError(context, error) {
    collectionErrors.push(`${context}: ${formatError(error)}`);
  }

  function currentScopeName() {
    return scopePath(activeScope).join(" > ") || "<root>";
  }

  function scopePath(scope) {
    const names = [];
    let cursor = scope;
    while (cursor && cursor.parent) {
      names.push(cursor.name);
      cursor = cursor.parent;
    }
    names.reverse();
    return names;
  }

  function testPath(test) {
    return [...scopePath(test.scope), test.name].join(" > ");
  }

  function registerHook(kind, fn) {
    if (typeof fn !== "function") {
      pushCollectionError(`${currentScopeName()} ${kind}`, new Error("Hook callback must be a function"));
      return;
    }

    activeScope[kind].push({ fn, timeoutMs: DEFAULT_TIMEOUT_MS });
  }

  function registerTest(name, fn, options, flags) {
    if (typeof name !== "string" || name.length === 0) {
      pushCollectionError(currentScopeName(), new Error("Test name must be a non-empty string"));
      return;
    }

    const effectiveSkip = Boolean(activeScope.skip || flags.skip || flags.todo);
    const timeoutMs =
      options && typeof options === "object" && typeof options.timeout === "number" && options.timeout > 0
        ? options.timeout
        : DEFAULT_TIMEOUT_MS;

    if (!flags.todo && typeof fn !== "function") {
      pushCollectionError(testPath({ scope: activeScope, name }), new Error("Test callback must be a function"));
      return;
    }

    const testEntry = {
      name,
      fn,
      scope: activeScope,
      skip: effectiveSkip,
      only: Boolean(flags.only),
      todo: Boolean(flags.todo),
      timeoutMs
    };

    activeScope.entries.push({ kind: "test", value: testEntry });
    registeredTestCount += 1;
  }

  function registerDescribe(name, fn, flags) {
    if (typeof name !== "string" || name.length === 0) {
      pushCollectionError(currentScopeName(), new Error("Describe name must be a non-empty string"));
      return;
    }

    if (typeof fn !== "function") {
      pushCollectionError(name, new Error("Describe callback must be a function"));
      return;
    }

    const childScope = createScope(name, activeScope, Boolean(activeScope.skip || flags.skip));
    activeScope.entries.push({ kind: "scope", value: childScope });

    const previousScope = activeScope;
    activeScope = childScope;
    try {
      fn();
    } catch (error) {
      pushCollectionError(scopePath(childScope).join(" > "), error);
    } finally {
      activeScope = previousScope;
    }
  }

  function test(name, fn, options) {
    registerTest(name, fn, options, { skip: false, only: false, todo: false });
  }

  test.skip = function testSkip(name, fn, options) {
    registerTest(name, fn, options, { skip: true, only: false, todo: false });
  };

  test.only = function testOnly(name, fn, options) {
    registerTest(name, fn, options, { skip: false, only: true, todo: false });
  };

  test.todo = function testTodo(name) {
    registerTest(name, null, null, { skip: false, only: false, todo: true });
  };

  test.each = function testEach(cases) {
    return function testEachRegister(name, fn, options) {
      for (const item of cases || []) {
        const label = String(name).replace(/%[sipdj]/g, () => String(item && item.title ? item.title : item));
        registerTest(label, () => fn(item), options, { skip: false, only: false, todo: false });
      }
    };
  };

  function describe(name, fn) {
    registerDescribe(name, fn, { skip: false });
  }

  describe.skip = function describeSkip(name, fn) {
    registerDescribe(name, fn, { skip: true });
  };

  function beforeAll(fn) {
    registerHook("beforeAll", fn);
  }

  function beforeEach(fn) {
    registerHook("beforeEach", fn);
  }

  function afterEach(fn) {
    registerHook("afterEach", fn);
  }

  function afterAll(fn) {
    registerHook("afterAll", fn);
  }

  function deepEqual(left, right) {
    if (Object.is(left, right)) {
      return true;
    }

    if (left && right && typeof left === "object" && typeof right === "object") {
      if (Array.isArray(left) !== Array.isArray(right)) {
        return false;
      }

      if (Array.isArray(left)) {
        if (left.length !== right.length) {
          return false;
        }
        for (let index = 0; index < left.length; index += 1) {
          if (!deepEqual(left[index], right[index])) {
            return false;
          }
        }
        return true;
      }

      const leftKeys = Object.keys(left);
      const rightKeys = Object.keys(right);
      if (leftKeys.length !== rightKeys.length) {
        return false;
      }

      for (const key of leftKeys) {
        if (!Object.prototype.hasOwnProperty.call(right, key)) {
          return false;
        }
        if (!deepEqual(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }

    return false;
  }

  const expectExtensions = Object.create(null);

  function runExtendedMatcher(name, matcher, received, args) {
    const context = {
      equals: deepEqual,
      isNot: false,
      promise: ""
    };

    const outcome = matcher.call(context, received, ...args);
    if (!outcome || typeof outcome !== "object" || typeof outcome.pass !== "boolean") {
      throw new Error(`Extended matcher ${name} must return { pass, message }`);
    }

    if (outcome.pass) {
      return;
    }

    if (typeof outcome.message === "function") {
      throw new Error(String(outcome.message()));
    }

    throw new Error(`Extended matcher ${name} failed`);
  }

  function expect(received) {
    const matchers = {
      toBe(expected) {
        if (!Object.is(received, expected)) {
          throw new Error(`Expected ${String(received)} to be ${String(expected)}`);
        }
      },
      toEqual(expected) {
        if (!deepEqual(received, expected)) {
          throw new Error("Expected values to be deeply equal");
        }
      },
      toThrow() {
        if (typeof received !== "function") {
          throw new Error("toThrow expects a function");
        }

        let didThrow = false;
        try {
          received();
        } catch {
          didThrow = true;
        }

        if (!didThrow) {
          throw new Error("Expected function to throw");
        }
      },
      toBeInTheDocument() {
        if (!received || typeof received !== "object") {
          throw new Error("toBeInTheDocument expects a DOM node");
        }

        if (!document || typeof document.contains !== "function" || !document.contains(received)) {
          throw new Error("Expected node to be in the document");
        }
      },
      toHaveAttribute(name, value) {
        if (!received || typeof received.getAttribute !== "function") {
          throw new Error("toHaveAttribute expects an Element");
        }

        const actual = received.getAttribute(String(name));
        if (actual == null) {
          throw new Error(`Expected attribute ${String(name)} to exist`);
        }

        if (arguments.length > 1 && String(actual) !== String(value)) {
          throw new Error(`Expected attribute ${String(name)} to be ${String(value)} but received ${String(actual)}`);
        }
      },
      toHaveBeenCalled() {
        const calls = received && received.mock && received.mock.calls;
        if (!Array.isArray(calls) || calls.length === 0) {
          throw new Error("Expected mock function to have been called");
        }
      }
    };

    for (const [name, matcher] of Object.entries(expectExtensions)) {
      matchers[name] = (...args) => {
        runExtendedMatcher(name, matcher, received, args);
      };
    }

    matchers.not = {};
    for (const [name, matcher] of Object.entries(matchers)) {
      if (name === "not" || typeof matcher !== "function") {
        continue;
      }
      matchers.not[name] = (...args) => {
        try {
          matcher(...args);
        } catch {
          return;
        }
        throw new Error(`Expected matcher ${name} not to pass`);
      };
    }

    return matchers;
  }

  expect.extend = function extend(matchers) {
    if (!matchers || typeof matchers !== "object") {
      throw new Error("expect.extend() requires a matcher object");
    }

    for (const [name, matcher] of Object.entries(matchers)) {
      if (typeof matcher === "function") {
        expectExtensions[name] = matcher;
      }
    }
  };

  const moduleMockExports = new Map();
  const moduleMockSources = new Map();

  function isIdentifierName(name) {
    return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name);
  }

  function updateMockManifest() {
    globalThis.__zigMockModuleManifestJson = JSON.stringify(
      Array.from(moduleMockSources.entries(), ([specifier, source]) => ({ specifier, source }))
    );
  }

  function buildMockModuleSource(specifier, exportsValue) {
    const namedKeys = [];
    if (exportsValue && (typeof exportsValue === "object" || typeof exportsValue === "function")) {
      for (const key of Object.keys(exportsValue)) {
        if (key !== "default" && isIdentifierName(key)) {
          namedKeys.push(key);
        }
      }
    }

    const lines = [
      `const value = globalThis.__zigRunnerMockExports.get(${JSON.stringify(specifier)});`,
      "const moduleExports = value && (typeof value === 'object' || typeof value === 'function') ? value : { default: value };"
    ];

    for (const key of namedKeys) {
      lines.push(`export const ${key} = moduleExports[${JSON.stringify(key)}];`);
    }

    lines.push("export default Object.prototype.hasOwnProperty.call(moduleExports, 'default') ? moduleExports.default : moduleExports;");
    return `${lines.join("\n")}\n`;
  }

  function createMockFunction(initialImplementation, options = {}) {
    const state = {
      calls: [],
      implementation: typeof initialImplementation === "function" ? initialImplementation : undefined,
      originalImplementation: typeof options.originalImplementation === "function" ? options.originalImplementation : undefined,
      restore: typeof options.restore === "function" ? options.restore : null,
      hasReturnValue: false,
      returnValue: undefined,
      hasResolvedValue: false,
      resolvedValue: undefined,
      hasRejectedValue: false,
      rejectedValue: undefined
    };

    function mocked(...args) {
      state.calls.push(args);

      if (state.implementation) {
        return state.implementation.apply(this, args);
      }

      if (state.hasReturnValue) {
        return state.returnValue;
      }

      if (state.hasResolvedValue) {
        return Promise.resolve(state.resolvedValue);
      }

      if (state.hasRejectedValue) {
        return Promise.reject(state.rejectedValue);
      }

      return undefined;
    }

    mocked.mock = {
      calls: state.calls
    };

    mocked.mockImplementation = (nextImplementation) => {
      if (typeof nextImplementation !== "function") {
        throw new Error("mockImplementation() requires a function");
      }
      state.implementation = nextImplementation;
      state.hasReturnValue = false;
      state.hasResolvedValue = false;
      state.hasRejectedValue = false;
      return mocked;
    };

    mocked.mockReturnValue = (value) => {
      state.implementation = undefined;
      state.hasReturnValue = true;
      state.returnValue = value;
      state.hasResolvedValue = false;
      state.hasRejectedValue = false;
      return mocked;
    };

    mocked.mockResolvedValue = (value) => {
      state.implementation = undefined;
      state.hasResolvedValue = true;
      state.resolvedValue = value;
      state.hasReturnValue = false;
      state.hasRejectedValue = false;
      return mocked;
    };

    mocked.mockRejectedValue = (error) => {
      state.implementation = undefined;
      state.hasRejectedValue = true;
      state.rejectedValue = error;
      state.hasReturnValue = false;
      state.hasResolvedValue = false;
      return mocked;
    };

    mocked.mockClear = () => {
      state.calls.length = 0;
      return mocked;
    };

    mocked.mockReset = () => {
      state.calls.length = 0;
      state.implementation = state.originalImplementation;
      state.hasReturnValue = false;
      state.returnValue = undefined;
      state.hasResolvedValue = false;
      state.resolvedValue = undefined;
      state.hasRejectedValue = false;
      state.rejectedValue = undefined;
      return mocked;
    };

    mocked.mockRestore = () => {
      if (state.restore) {
        state.restore();
      }
      return mocked.mockReset();
    };

    return mocked;
  }

  function mock(fn) {
    return createMockFunction(fn, { originalImplementation: typeof fn === "function" ? fn : undefined });
  }

  mock.module = async function mockModule(specifier, factory) {
    if (typeof specifier !== "string" || specifier.length === 0) {
      throw new Error("mock.module() requires a non-empty module specifier");
    }

    let produced;
    if (typeof factory === "function") {
      produced = factory();
    } else {
      produced = factory;
    }

    const exportsValue = await Promise.resolve(produced);
    const source = buildMockModuleSource(specifier, exportsValue);
    moduleMockExports.set(specifier, exportsValue);
    moduleMockSources.set(specifier, source);
    updateMockManifest();
    return exportsValue;
  };

  function spyOn(target, property) {
    if (!target || (typeof target !== "object" && typeof target !== "function")) {
      throw new Error("spyOn() requires an object target");
    }

    const propertyName = String(property);
    let owner = target;
    let descriptor;
    while (owner && !descriptor) {
      descriptor = Object.getOwnPropertyDescriptor(owner, propertyName);
      if (!descriptor) {
        owner = Object.getPrototypeOf(owner);
      }
    }

    if (!descriptor || !owner) {
      owner = target;
      descriptor = {
        configurable: true,
        enumerable: true,
        writable: true,
        value: function noopSpyTarget() {}
      };
      Object.defineProperty(owner, propertyName, descriptor);
    }

    const restoreDescriptor = () => {
      Object.defineProperty(owner, propertyName, descriptor);
    };

    if (typeof descriptor.value === "function") {
      const original = descriptor.value;
      const originalImpl = function originalImpl(...args) {
        return original.apply(this, args);
      };

      const wrapped = createMockFunction(originalImpl, {
        originalImplementation: originalImpl,
        restore: restoreDescriptor
      });

      Object.defineProperty(owner, propertyName, {
        ...descriptor,
        value: wrapped
      });

      return wrapped;
    }

    if (typeof descriptor.get === "function") {
      const originalGet = descriptor.get;
      const getterImpl = function getterImpl() {
        return originalGet.call(this);
      };

      const wrapped = createMockFunction(getterImpl, {
        originalImplementation: getterImpl,
        restore: restoreDescriptor
      });

      Object.defineProperty(owner, propertyName, {
        ...descriptor,
        get() {
          return wrapped.call(this);
        }
      });

      return wrapped;
    }

    throw new Error(`spyOn() only supports function values and getters: ${propertyName}`);
  }

  const onLoadHooks = [];

  function plugin(definition) {
    if (!definition || typeof definition !== "object") {
      throw new Error("plugin() requires a plugin definition object");
    }

    const build = {
      onLoad(options, callback) {
        if (!options || !(options.filter instanceof RegExp)) {
          throw new Error("build.onLoad() requires an options object with a RegExp filter");
        }

        if (typeof callback !== "function") {
          throw new Error("build.onLoad() callback must be a function");
        }

        onLoadHooks.push({
          filter: options.filter,
          callback
        });
      }
    };

    if (typeof definition.setup === "function") {
      definition.setup(build);
    }

    return definition;
  }

  async function applyOnLoad(path) {
    for (const hook of onLoadHooks) {
      hook.filter.lastIndex = 0;
      if (!hook.filter.test(path)) {
        continue;
      }

      const result = await Promise.resolve(hook.callback({ path }));
      if (result && typeof result === "object" && Object.prototype.hasOwnProperty.call(result, "contents")) {
        return result;
      }
    }

    return null;
  }

  function bunShellTag() {
    throw new Error("bun.$ shell execution is not implemented in this runner");
  }

  function bunFile(pathLike) {
    const normalizedPath = String(pathLike ?? "");
    return {
      async text() {
        throw new Error(`bun.file(${normalizedPath}).text() is not implemented in this runner`);
      },
      async json() {
        const text = await this.text();
        return JSON.parse(text);
      }
    };
  }

  const bunApi = Object.freeze({
    plugin,
    $: bunShellTag,
    file: bunFile
  });

  globalThis.__zigRunnerMockExports = moduleMockExports;
  globalThis.__zigRunnerApplyOnLoad = applyOnLoad;
  globalThis.__zigBunApi = bunApi;
  globalThis.Bun = bunApi;
  updateMockManifest();

  if (typeof globalThis.KeyboardEvent !== "function") {
    globalThis.KeyboardEvent = class KeyboardEvent extends Event {
      constructor(type, init = {}) {
        super(type, init);
        Object.assign(this, init);
      }
    };
    if (globalThis.window && typeof globalThis.window === "object") {
      globalThis.window.KeyboardEvent = globalThis.KeyboardEvent;
    }
  }

  if (typeof globalThis.URL !== "function") {
    if (typeof globalThis.URLSearchParams !== "function") {
      globalThis.URLSearchParams = class URLSearchParams {
        constructor(input) {
          const text = String(input || "");
          const raw = text.startsWith("?") ? text.slice(1) : text;
          this._pairs = [];
          if (!raw) {
            return;
          }

          const parts = raw.split("&");
          for (const part of parts) {
            if (!part) {
              continue;
            }

            const eqIndex = part.indexOf("=");
            const key = eqIndex >= 0 ? part.slice(0, eqIndex) : part;
            const value = eqIndex >= 0 ? part.slice(eqIndex + 1) : "";
            this._pairs.push([
              decodeURIComponent(key.replace(/\+/g, " ")),
              decodeURIComponent(value.replace(/\+/g, " "))
            ]);
          }
        }

        get(name) {
          const expected = String(name);
          for (const [key, value] of this._pairs) {
            if (key === expected) {
              return value;
            }
          }
          return null;
        }

        delete(name) {
          const expected = String(name);
          this._pairs = this._pairs.filter(([key]) => key !== expected);
        }

        toString() {
          return this._pairs
            .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
            .join("&");
        }
      };
    }

    globalThis.URL = class URL {
      constructor(input) {
        const href = String(input || "");
        const match = href.match(/^([a-zA-Z][a-zA-Z0-9+.-]*:)?\/\/([^\/?#]+)([^?#]*)(\?[^#]*)?(#.*)?$/);
        if (!match) {
          throw new TypeError("Invalid URL");
        }

        this.href = href;
        this.protocol = match[1] || "";
        this.host = match[2] || "";
        this.hostname = this.host.split(":")[0] || "";
        this.pathname = match[3] || "/";
        this.search = match[4] || "";
        this.hash = match[5] || "";
        this.origin = this.protocol && this.host ? `${this.protocol}//${this.host}` : "";
          this.searchParams = new globalThis.URLSearchParams(this.search);
      }

      toString() {
        const query = this.searchParams && typeof this.searchParams.toString === "function" ? this.searchParams.toString() : "";
        const search = query ? `?${query}` : "";
        return `${this.origin}${this.pathname}${search}${this.hash}`;
      }
    };
  }

  if (!globalThis.location || typeof globalThis.location !== "object") {
    globalThis.location = {
      href: "http://localhost/",
      protocol: "http:",
      host: "localhost",
      hostname: "localhost",
      port: "",
      pathname: "/",
      search: "",
      hash: ""
    };
  }

  if (typeof globalThis.location.hostname !== "string") {
    globalThis.location.hostname = "localhost";
  }
  if (typeof globalThis.location.protocol !== "string") {
    globalThis.location.protocol = "http:";
  }
  if (typeof globalThis.location.port !== "string") {
    globalThis.location.port = "";
  }
  if (typeof globalThis.location.pathname !== "string") {
    globalThis.location.pathname = "/";
  }
  if (typeof globalThis.location.search !== "string") {
    globalThis.location.search = "";
  }
  if (typeof globalThis.location.hash !== "string") {
    globalThis.location.hash = "";
  }

  if (!globalThis.navigator || typeof globalThis.navigator !== "object") {
    globalThis.navigator = { userAgent: "zig-dom" };
  } else if (typeof globalThis.navigator.userAgent !== "string") {
    globalThis.navigator.userAgent = "zig-dom";
  }

  if (!globalThis.process || typeof globalThis.process !== "object") {
    globalThis.process = {
      env: {
        ZIG_DOM_SKIP_TESTING_LIBRARY: "1"
      },
      argv: [],
      platform: "darwin",
      arch: "arm64",
      cwd() {
        return "/";
      },
      nextTick(callback, ...args) {
        globalThis.queueMicrotask(() => {
          if (typeof callback === "function") {
            callback(...args);
          }
        });
      }
    };
  } else {
    if (!globalThis.process.env || typeof globalThis.process.env !== "object") {
      globalThis.process.env = {};
    }

    if (globalThis.process.env.ZIG_DOM_SKIP_TESTING_LIBRARY == null) {
      globalThis.process.env.ZIG_DOM_SKIP_TESTING_LIBRARY = "1";
    }

    if (!Array.isArray(globalThis.process.argv)) {
      globalThis.process.argv = [];
    }

    if (typeof globalThis.process.platform !== "string") {
      globalThis.process.platform = "darwin";
    }

    if (typeof globalThis.process.arch !== "string") {
      globalThis.process.arch = "arm64";
    }

    if (typeof globalThis.process.cwd !== "function") {
      globalThis.process.cwd = function cwd() {
        return "/";
      };
    }

    if (typeof globalThis.process.nextTick !== "function") {
      globalThis.process.nextTick = function nextTick(callback, ...args) {
        globalThis.queueMicrotask(() => {
          if (typeof callback === "function") {
            callback(...args);
          }
        });
      };
    }
  }

  if (typeof globalThis.global === "undefined") {
    globalThis.global = globalThis;
  }

  if (globalThis.window && typeof globalThis.window === "object") {
    if (!globalThis.window.location) {
      globalThis.window.location = globalThis.location;
    }
    if (!globalThis.window.navigator) {
      globalThis.window.navigator = globalThis.navigator;
    }
  }

  if (!globalThis.__zigImportMetaEnv || typeof globalThis.__zigImportMetaEnv !== "object") {
    globalThis.__zigImportMetaEnv = {
      DEV: false,
      PROD: false,
      VITE_LEGACY: "false",
      VITE_PLAYWRIGHT_TEST: "false"
    };
  }

  if (typeof globalThis.queueMicrotask !== "function") {
    globalThis.queueMicrotask = function queueMicrotask(callback) {
      Promise.resolve().then(() => {
        if (typeof callback === "function") {
          callback();
        }
      });
    };
  }

  if (typeof globalThis.TextEncoder !== "function") {
    globalThis.TextEncoder = class TextEncoder {
      encode(input = "") {
        const text = String(input);
        const encoded = unescape(encodeURIComponent(text));
        const bytes = new Uint8Array(encoded.length);
        for (let index = 0; index < encoded.length; index += 1) {
          bytes[index] = encoded.charCodeAt(index);
        }
        return bytes;
      }
    };
  }

  if (typeof globalThis.TextDecoder !== "function") {
    globalThis.TextDecoder = class TextDecoder {
      decode(input) {
        if (!input) {
          return "";
        }

        const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
        let encoded = "";
        for (let index = 0; index < bytes.length; index += 1) {
          encoded += String.fromCharCode(bytes[index]);
        }
        try {
          return decodeURIComponent(escape(encoded));
        } catch {
          return encoded;
        }
      }
    };
  }

  if (typeof globalThis.Buffer !== "function") {
    function decodeBase64(input) {
      const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      const cleaned = String(input || "").replace(/=+$/, "").replace(/\s+/g, "");
      const output = [];
      let bits = 0;
      let value = 0;

      for (let index = 0; index < cleaned.length; index += 1) {
        const code = alphabet.indexOf(cleaned[index]);
        if (code < 0) {
          continue;
        }
        value = (value << 6) | code;
        bits += 6;
        if (bits >= 8) {
          bits -= 8;
          output.push((value >> bits) & 0xff);
        }
      }

      return new Uint8Array(output);
    }

    class BufferImpl extends Uint8Array {
      static from(input, encoding) {
        if (typeof input === "string") {
          if (encoding === "base64") {
            return new BufferImpl(decodeBase64(input));
          }
          return new BufferImpl(new globalThis.TextEncoder().encode(input));
        }

        if (input instanceof ArrayBuffer) {
          return new BufferImpl(new Uint8Array(input));
        }

        if (ArrayBuffer.isView(input) || Array.isArray(input)) {
          return new BufferImpl(input);
        }

        return new BufferImpl(0);
      }

      static alloc(size, fill = 0) {
        const next = new BufferImpl(Number(size) || 0);
        next.fill(fill);
        return next;
      }

      static allocUnsafe(size) {
        return new BufferImpl(Number(size) || 0);
      }

      static isBuffer(value) {
        return value instanceof Uint8Array;
      }

      static get [Symbol.species]() {
        return BufferImpl;
      }

      toString(encoding) {
        if (encoding === "base64") {
          const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
          let output = "";
          for (let index = 0; index < this.length; index += 3) {
            const b0 = this[index] ?? 0;
            const b1 = this[index + 1] ?? 0;
            const b2 = this[index + 2] ?? 0;
            const chunk = (b0 << 16) | (b1 << 8) | b2;
            output += alphabet[(chunk >> 18) & 63];
            output += alphabet[(chunk >> 12) & 63];
            output += index + 1 < this.length ? alphabet[(chunk >> 6) & 63] : "=";
            output += index + 2 < this.length ? alphabet[chunk & 63] : "=";
          }
          return output;
        }

        return new globalThis.TextDecoder().decode(this);
      }
    }

    globalThis.Buffer = BufferImpl;
  }

  function createEventEmitterClass() {
    return class EventEmitter {
      constructor() {
        this._listeners = new Map();
      }

      on(eventName, listener) {
        const key = String(eventName);
        const list = this._listeners.get(key) || [];
        list.push(listener);
        this._listeners.set(key, list);
        return this;
      }

      once(eventName, listener) {
        const wrapped = (...args) => {
          this.removeListener(eventName, wrapped);
          listener(...args);
        };
        return this.on(eventName, wrapped);
      }

      emit(eventName, ...args) {
        const key = String(eventName);
        const list = this._listeners.get(key);
        if (!list || list.length === 0) {
          return false;
        }
        for (const listener of [...list]) {
          listener(...args);
        }
        return true;
      }

      removeListener(eventName, listener) {
        const key = String(eventName);
        const list = this._listeners.get(key);
        if (!list) {
          return this;
        }
        this._listeners.set(
          key,
          list.filter((entry) => entry !== listener)
        );
        return this;
      }

      listenerCount(eventName) {
        const key = String(eventName);
        const list = this._listeners.get(key);
        return list ? list.length : 0;
      }
    };
  }

  const EventEmitter = createEventEmitterClass();
  EventEmitter.EventEmitter = EventEmitter;

  function makeUnsupportedBuiltin(name) {
    return () => {
      throw new Error(`Builtin module ${name} is not implemented in this runner`);
    };
  }

  const importMetaRequireBuiltins = {
    events: EventEmitter,
    fs: {
      readFileSync: makeUnsupportedBuiltin("fs.readFileSync"),
      writeFileSync: makeUnsupportedBuiltin("fs.writeFileSync"),
      existsSync: () => false
    },
    path: {
      join: (...parts) => parts.filter(Boolean).join("/"),
      resolve: (...parts) => parts.filter(Boolean).join("/"),
      dirname: (value) => {
        const input = String(value || "");
        const index = input.lastIndexOf("/");
        return index <= 0 ? "." : input.slice(0, index);
      }
    },
    util: {
      TextEncoder: globalThis.TextEncoder,
      TextDecoder: globalThis.TextDecoder,
      inspect(value) {
        try {
          return JSON.stringify(value);
        } catch {
          return String(value);
        }
      }
    },
    buffer: {
      Buffer: globalThis.Buffer,
      Blob: globalThis.Blob
    },
    stream: {
      Duplex: class Duplex extends EventEmitter {},
      Readable: class Readable extends EventEmitter {},
      Writable: class Writable extends EventEmitter {},
      Transform: class Transform extends EventEmitter {}
    },
    url: {
      URL: globalThis.URL,
      URLSearchParams: globalThis.URLSearchParams
    },
    http: {
      request: makeUnsupportedBuiltin("http.request"),
      get: makeUnsupportedBuiltin("http.get")
    },
    https: {
      request: makeUnsupportedBuiltin("https.request"),
      get: makeUnsupportedBuiltin("https.get")
    },
    net: {
      isIP: () => 0,
      createConnection: makeUnsupportedBuiltin("net.createConnection")
    },
    tls: {
      connect: makeUnsupportedBuiltin("tls.connect")
    },
    crypto: {
      randomBytes(size) {
        const bytes = new Uint8Array(Number(size) || 0);
        return globalThis.Buffer.from(bytes);
      },
      createHash() {
        return {
          update() {
            return this;
          },
          digest() {
            return globalThis.Buffer.from("");
          }
        };
      }
    },
    zlib: {
      createDeflateRaw: makeUnsupportedBuiltin("zlib.createDeflateRaw"),
      createInflateRaw: makeUnsupportedBuiltin("zlib.createInflateRaw")
    }
  };

  function importMetaRequire(specifier) {
    const key = String(specifier || "");
    const normalized = key.startsWith("node:") ? key.slice(5) : key;
    const builtin = importMetaRequireBuiltins[normalized];
    if (builtin) {
      return builtin;
    }
    throw new Error(`import.meta.require() unsupported module: ${key}`);
  }

  globalThis.__zigImportMetaRequire = importMetaRequire;

  if (typeof globalThis.setTimeout !== "function") {
    let timeoutIdCounter = 1;
    const cancelledTimeouts = new Set();

    globalThis.setTimeout = function setTimeout(callback, _delay, ...args) {
      const id = timeoutIdCounter;
      timeoutIdCounter += 1;

      Promise.resolve().then(() => {
        if (cancelledTimeouts.has(id)) {
          cancelledTimeouts.delete(id);
          return;
        }

        if (typeof callback === "function") {
          callback(...args);
          return;
        }

        if (typeof callback === "string") {
          Function(callback)();
        }
      });

      return id;
    };

    globalThis.clearTimeout = function clearTimeout(id) {
      cancelledTimeouts.add(Number(id));
    };
  }

  if (typeof globalThis.setInterval !== "function") {
    globalThis.setInterval = function setInterval(callback, delay, ...args) {
      const schedule = () => {
        const timeoutId = globalThis.setTimeout(() => {
          if (typeof callback === "function") {
            callback(...args);
          }
          schedule();
        }, delay);
        return timeoutId;
      };

      return schedule();
    };
  }

  if (typeof globalThis.clearInterval !== "function") {
    globalThis.clearInterval = function clearInterval(id) {
      globalThis.clearTimeout(id);
    };
  }

  if (typeof globalThis.setImmediate !== "function") {
    let immediateIdCounter = 1;
    const cancelledImmediates = new Set();

    globalThis.setImmediate = function setImmediate(callback, ...args) {
      const id = immediateIdCounter;
      immediateIdCounter += 1;

      Promise.resolve().then(() => {
        if (cancelledImmediates.has(id)) {
          cancelledImmediates.delete(id);
          return;
        }

        if (typeof callback === "function") {
          callback(...args);
        }
      });

      return id;
    };

    globalThis.clearImmediate = function clearImmediate(id) {
      cancelledImmediates.add(Number(id));
    };
  }

  if (globalThis.window && typeof globalThis.window === "object") {
    if (!globalThis.window.queueMicrotask) {
      globalThis.window.queueMicrotask = globalThis.queueMicrotask;
    }
    if (!globalThis.window.setTimeout) {
      globalThis.window.setTimeout = globalThis.setTimeout;
    }
    if (!globalThis.window.clearTimeout) {
      globalThis.window.clearTimeout = globalThis.clearTimeout;
    }
    if (!globalThis.window.setInterval) {
      globalThis.window.setInterval = globalThis.setInterval;
    }
    if (!globalThis.window.clearInterval) {
      globalThis.window.clearInterval = globalThis.clearInterval;
    }
    if (!globalThis.window.setImmediate) {
      globalThis.window.setImmediate = globalThis.setImmediate;
    }
    if (!globalThis.window.clearImmediate) {
      globalThis.window.clearImmediate = globalThis.clearImmediate;
    }
    if (!globalThis.window.Buffer) {
      globalThis.window.Buffer = globalThis.Buffer;
    }
  }

  if (!globalThis.Intl || typeof globalThis.Intl !== "object") {
    globalThis.Intl = {};
  }

  if (typeof globalThis.Intl.Collator !== "function") {
    globalThis.Intl.Collator = class Collator {
      compare(left, right) {
        return String(left).localeCompare(String(right));
      }
    };
  }

  if (globalThis.window && typeof globalThis.window === "object" && !globalThis.window.Intl) {
    globalThis.window.Intl = globalThis.Intl;
  }

  if (typeof globalThis.DOMParser !== "function") {
    globalThis.DOMParser = class DOMParser {
      parseFromString(input) {
        const html = String(input ?? "");
        return {
          body: {
            innerHTML: html,
            textContent: html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim()
          }
        };
      }
    };
  }

  if (globalThis.window && typeof globalThis.window === "object" && !globalThis.window.DOMParser) {
    globalThis.window.DOMParser = globalThis.DOMParser;
  }

  function createStorageFallback() {
    const store = new Map();
    return {
      getItem(key) {
        const lookup = String(key);
        return store.has(lookup) ? store.get(lookup) : null;
      },
      setItem(key, value) {
        store.set(String(key), String(value));
      },
      removeItem(key) {
        store.delete(String(key));
      },
      clear() {
        store.clear();
      },
      key(index) {
        const keys = Array.from(store.keys());
        return index >= 0 && index < keys.length ? keys[index] : null;
      },
      get length() {
        return store.size;
      }
    };
  }

  if (!globalThis.localStorage || typeof globalThis.localStorage !== "object") {
    globalThis.localStorage = createStorageFallback();
  }

  if (!globalThis.sessionStorage || typeof globalThis.sessionStorage !== "object") {
    globalThis.sessionStorage = createStorageFallback();
  }

  if (globalThis.window && typeof globalThis.window === "object") {
    if (!globalThis.window.localStorage) {
      globalThis.window.localStorage = globalThis.localStorage;
    }
    if (!globalThis.window.sessionStorage) {
      globalThis.window.sessionStorage = globalThis.sessionStorage;
    }
  }

  if (typeof globalThis.matchMedia !== "function") {
    globalThis.matchMedia = function matchMedia(query) {
      return {
        media: String(query ?? ""),
        matches: false,
        onchange: null,
        addListener() {},
        removeListener() {},
        addEventListener() {},
        removeEventListener() {},
        dispatchEvent() {
          return false;
        }
      };
    };
  }

  if (globalThis.window && typeof globalThis.window === "object" && !globalThis.window.matchMedia) {
    globalThis.window.matchMedia = globalThis.matchMedia;
  }

  function ensureStyleObject(node) {
    if (!node || typeof node !== "object") {
      return;
    }

    if (!node.style || typeof node.style.setProperty !== "function") {
      node.style = {
        setProperty() {},
        removeProperty() {},
        getPropertyValue() {
          return "";
        }
      };
    }
  }

  if (globalThis.document && typeof globalThis.document === "object") {
    ensureStyleObject(globalThis.document.documentElement);
    ensureStyleObject(globalThis.document.body);
  }

  function gatherScopeChain(scope) {
    const chain = [];
    let cursor = scope;
    while (cursor) {
      chain.push(cursor);
      cursor = cursor.parent;
    }
    chain.reverse();
    return chain;
  }

  function hasOnly(scope) {
    for (const entry of scope.entries) {
      if (entry.kind === "test") {
        if (entry.value.only) {
          return true;
        }
      } else if (hasOnly(entry.value)) {
        return true;
      }
    }
    return false;
  }

  function hasRunnableTest(scope, onlyMode) {
    for (const entry of scope.entries) {
      if (entry.kind === "test") {
        const testEntry = entry.value;
        if (testEntry.todo || testEntry.skip) {
          continue;
        }
        if (onlyMode && !testEntry.only) {
          continue;
        }
        return true;
      }

      if (hasRunnableTest(entry.value, onlyMode)) {
        return true;
      }
    }

    return false;
  }

  async function invokeCallback(fn, timeoutMs) {
    const startedAt = Date.now();

    if (fn.length > 0) {
      let doneCalled = false;
      let doneError = null;

      const done = (error) => {
        doneCalled = true;
        doneError = error || null;
      };

      const maybePromise = fn(done);
      if (maybePromise && typeof maybePromise.then === "function") {
        await maybePromise;
      }

      if (!doneCalled) {
        return {
          ok: false,
          timeout: true,
          elapsedMs: Date.now() - startedAt,
          error: new Error("done() callback was not called")
        };
      }

      if (doneError) {
        return {
          ok: false,
          timeout: false,
          elapsedMs: Date.now() - startedAt,
          error: doneError
        };
      }

      const elapsedMs = Date.now() - startedAt;
      if (elapsedMs > timeoutMs) {
        return {
          ok: false,
          timeout: true,
          elapsedMs,
          error: new Error(`Exceeded timeout of ${timeoutMs}ms`)
        };
      }

      return { ok: true, elapsedMs, timeout: false };
    }

    const maybePromise = fn();
    if (maybePromise && typeof maybePromise.then === "function") {
      await maybePromise;
    }

    const elapsedMs = Date.now() - startedAt;
    if (elapsedMs > timeoutMs) {
      return {
        ok: false,
        timeout: true,
        elapsedMs,
        error: new Error(`Exceeded timeout of ${timeoutMs}ms`)
      };
    }

    return { ok: true, elapsedMs, timeout: false };
  }

  async function runHookList(hooks, timeoutMs) {
    for (const hook of hooks) {
      const hookTimeout = hook.timeoutMs || timeoutMs;
      const outcome = await invokeCallback(hook.fn, hookTimeout);
      if (!outcome.ok) {
        return outcome;
      }
    }

    return { ok: true, elapsedMs: 0, timeout: false };
  }

  function addFailure(result, name, error, timeout) {
    result.failures.push({
      name,
      error: formatError(error),
      timeout: Boolean(timeout)
    });
    result.failed += 1;
    if (timeout) {
      result.timedOut += 1;
    }
  }

  async function runTestEntry(testEntry, result, onlyMode) {
    const fullName = testPath(testEntry);

    if (testEntry.todo || testEntry.skip || (onlyMode && !testEntry.only)) {
      result.skipped += 1;
      return;
    }

    const scopeChain = gatherScopeChain(testEntry.scope);
    const beforeEachHooks = [];
    const afterEachHooks = [];

    for (const scope of scopeChain) {
      beforeEachHooks.push(...scope.beforeEach);
    }

    for (let index = scopeChain.length - 1; index >= 0; index -= 1) {
      afterEachHooks.push(...scopeChain[index].afterEach);
    }

    const beforeEachOutcome = await runHookList(beforeEachHooks, testEntry.timeoutMs);
    if (!beforeEachOutcome.ok) {
      addFailure(result, `${fullName} (beforeEach)`, beforeEachOutcome.error, beforeEachOutcome.timeout);
      await runHookList(afterEachHooks, testEntry.timeoutMs);
      return;
    }

    let testOutcome;
    try {
      testOutcome = await invokeCallback(testEntry.fn, testEntry.timeoutMs);
    } catch (error) {
      testOutcome = {
        ok: false,
        timeout: false,
        error,
        elapsedMs: 0
      };
    }

    const afterEachOutcome = await runHookList(afterEachHooks, testEntry.timeoutMs);

    if (!testOutcome.ok) {
      addFailure(result, fullName, testOutcome.error, testOutcome.timeout);
      if (!afterEachOutcome.ok) {
        addFailure(result, `${fullName} (afterEach)`, afterEachOutcome.error, afterEachOutcome.timeout);
      }
      return;
    }

    if (!afterEachOutcome.ok) {
      addFailure(result, `${fullName} (afterEach)`, afterEachOutcome.error, afterEachOutcome.timeout);
      return;
    }

    result.passed += 1;
  }

  function failScopeTree(scope, result, onlyMode, message) {
    for (const entry of scope.entries) {
      if (entry.kind === "test") {
        const testEntry = entry.value;
        if (testEntry.todo || testEntry.skip || (onlyMode && !testEntry.only)) {
          continue;
        }
        addFailure(result, `${testPath(testEntry)} (beforeAll)`, message, false);
        continue;
      }

      failScopeTree(entry.value, result, onlyMode, message);
    }
  }

  async function runScope(scope, result, onlyMode) {
    if (!hasRunnableTest(scope, onlyMode)) {
      return;
    }

    const beforeAllOutcome = await runHookList(scope.beforeAll, DEFAULT_TIMEOUT_MS);
    if (!beforeAllOutcome.ok) {
      failScopeTree(scope, result, onlyMode, beforeAllOutcome.error);
      const afterAllOutcome = await runHookList(scope.afterAll, DEFAULT_TIMEOUT_MS);
      if (!afterAllOutcome.ok) {
        addFailure(result, `${scopePath(scope).join(" > ")} (afterAll)`, afterAllOutcome.error, afterAllOutcome.timeout);
      }
      return;
    }

    for (const entry of scope.entries) {
      if (entry.kind === "test") {
        await runTestEntry(entry.value, result, onlyMode);
      } else {
        await runScope(entry.value, result, onlyMode);
      }
    }

    const afterAllOutcome = await runHookList(scope.afterAll, DEFAULT_TIMEOUT_MS);
    if (!afterAllOutcome.ok) {
      addFailure(result, `${scopePath(scope).join(" > ")} (afterAll)`, afterAllOutcome.error, afterAllOutcome.timeout);
    }
  }

  function buildReportLines(items) {
    return items.map((item) => `${item.name}\n${item.error}`).join("\n\n");
  }

  async function runCollectedTests() {
    const result = {
      passed: 0,
      failed: 0,
      skipped: 0,
      timedOut: 0,
      collectionErrors: collectionErrors.slice(),
      failures: []
    };

    const onlyMode = hasOnly(rootScope);
    const hasRunnable = hasRunnableTest(rootScope, onlyMode);
    await runScope(rootScope, result, onlyMode);

    globalThis.__zigPassed = result.passed;
    globalThis.__zigFailed = result.failed;
    globalThis.__zigSkipped = result.skipped;
    globalThis.__zigTimedOut = result.timedOut;
    globalThis.__zigCollectionErrors = result.collectionErrors.length;
    globalThis.__zigFailuresText = buildReportLines(result.failures);
    globalThis.__zigCollectionText = result.collectionErrors.join("\n\n");
    globalThis.__zigRegisteredTests = registeredTestCount;
    globalThis.__zigOnlyMode = onlyMode;
    globalThis.__zigHasRunnable = hasRunnable;

    return result;
  }

  const bunTestApi = Object.freeze({
    test,
    it: test,
    describe,
    expect,
    mock,
    spyOn,
    beforeAll,
    beforeEach,
    afterEach,
    afterAll
  });

  Object.defineProperty(globalThis, "__zigBunTestApi", {
    value: bunTestApi,
    configurable: false,
    enumerable: false,
    writable: false
  });

  globalThis.expect = bunTestApi.expect;
  globalThis.test = bunTestApi.test;
  globalThis.it = bunTestApi.it;
  globalThis.describe = bunTestApi.describe;
  globalThis.mock = bunTestApi.mock;
  globalThis.spyOn = bunTestApi.spyOn;
  globalThis.beforeAll = bunTestApi.beforeAll;
  globalThis.beforeEach = bunTestApi.beforeEach;
  globalThis.afterEach = bunTestApi.afterEach;
  globalThis.afterAll = bunTestApi.afterAll;

  globalThis.__zigRunner = {
    run: runCollectedTests
  };
})();

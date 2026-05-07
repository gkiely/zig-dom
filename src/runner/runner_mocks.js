(() => {
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



  globalThis.__zigMock = mock;
  globalThis.__zigSpyOn = spyOn;
})();

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

  const expect = globalThis.__zigExpect;
  const mock = globalThis.__zigMock;
  const spyOn = globalThis.__zigSpyOn;

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

  globalThis.expect = expect;
  globalThis.test = test;
  globalThis.it = test;
  globalThis.describe = describe;
  globalThis.mock = mock;
  globalThis.spyOn = spyOn;
  globalThis.beforeAll = beforeAll;
  globalThis.beforeEach = beforeEach;
  globalThis.afterEach = afterEach;
  globalThis.afterAll = afterAll;
  globalThis.__zigInstallBunTestApi();

  globalThis.__zigRunner = {
    run: runCollectedTests
  };
})();

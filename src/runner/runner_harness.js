(() => {
  const DEFAULT_TIMEOUT_MS = 5000;

  const rootScope = createScope("<root>", null, false);
  let activeScope = rootScope;
  const collectionErrors = [];

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
      return String(error.stack);
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

  function expect(received) {
    return {
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
      }
    };
  }

  const React = {
    Fragment: Symbol.for("react.fragment"),
    createElement(type, props, ...children) {
      const finalProps = props ? { ...props } : {};
      if (children.length === 1) {
        finalProps.children = children[0];
      } else if (children.length > 1) {
        finalProps.children = children;
      }
      return {
        $$typeof: Symbol.for("react.element"),
        type,
        props: finalProps
      };
    }
  };

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
    await runScope(rootScope, result, onlyMode);

    globalThis.__zigPassed = result.passed;
    globalThis.__zigFailed = result.failed;
    globalThis.__zigSkipped = result.skipped;
    globalThis.__zigTimedOut = result.timedOut;
    globalThis.__zigCollectionErrors = result.collectionErrors.length;
    globalThis.__zigFailuresText = buildReportLines(result.failures);
    globalThis.__zigCollectionText = result.collectionErrors.join("\n\n");

    return result;
  }

  globalThis.React = React;
  globalThis.expect = expect;
  globalThis.test = test;
  globalThis.it = test;
  globalThis.describe = describe;
  globalThis.beforeAll = beforeAll;
  globalThis.beforeEach = beforeEach;
  globalThis.afterEach = afterEach;
  globalThis.afterAll = afterAll;

  globalThis.__zigRunner = {
    run: runCollectedTests
  };
})();

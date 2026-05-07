const setupGlobal = globalThis as typeof globalThis & {
  expect: (received: unknown) => Record<string, unknown>;
  __zigSetupExpectExtended?: boolean;
};

const baseExpect = setupGlobal.expect;

setupGlobal.expect = (received: unknown) => {
  const matchers = baseExpect(received);
  return {
    ...matchers,
    toBeUppercase() {
      if (typeof received !== "string" || received !== received.toUpperCase()) {
        throw new Error("Expected value to be an uppercase string");
      }
    }
  };
};

setupGlobal.__zigSetupExpectExtended = true;

import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test } from "bun:test";

const calls = [];

beforeAll(() => {
  calls.push("root beforeAll");
});

afterAll(() => {
  calls.push("root afterAll");
});

describe("outer", () => {
  beforeAll(() => {
    calls.push("outer beforeAll");
  });

  beforeEach(() => {
    calls.push("outer beforeEach");
  });

  afterEach(() => {
    calls.push("outer afterEach");
  });

  afterAll(() => {
    calls.push("outer afterAll");
  });

  test("first", () => {
    calls.push("first test");
  });

  describe("inner", () => {
    beforeAll(() => {
      calls.push("inner beforeAll");
    });

    beforeEach(() => {
      calls.push("inner beforeEach");
    });

    afterEach(() => {
      calls.push("inner afterEach");
    });

    afterAll(() => {
      calls.push("inner afterAll");
    });

    test("second", () => {
      calls.push("inner test");
      expect(calls[0]).toBe("root beforeAll");
    });
  });
});

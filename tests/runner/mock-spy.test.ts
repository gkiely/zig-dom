import { expect, mock, spyOn, test } from "bun:test";

test("mock tracks calls and supports return/resolve/reject controls", async () => {
  const adder = mock((left: number, right: number) => left + right);

  expect(adder(2, 3)).toBe(5);
  expect(adder.mock.calls.length).toBe(1);

  adder.mockImplementation((left: number, right: number) => left * right);
  expect(adder(2, 3)).toBe(6);

  adder.mockReturnValue(99);
  expect(adder(4, 5)).toBe(99);

  adder.mockResolvedValue("ok");
  expect(await adder()).toBe("ok");

  adder.mockRejectedValue(new Error("boom"));
  let rejectionMessage = "";
  try {
    await adder();
  } catch (error) {
    rejectionMessage = error instanceof Error ? error.message : String(error);
  }
  expect(rejectionMessage).toBe("boom");

  adder.mockClear();
  expect(adder.mock.calls.length).toBe(0);

  adder.mockReset();
  expect(adder(1, 2)).toBe(3);
});

test("mock supports once return/resolve/reject helpers", async () => {
  const fn = mock(() => "base");

  fn.mockReturnValueOnce("first");
  fn.mockResolvedValueOnce("second");
  fn.mockRejectedValueOnce(new Error("third"));

  expect(fn()).toBe("first");
  expect(await fn()).toBe("second");

  let rejectionMessage = "";
  try {
    await fn();
  } catch (error) {
    rejectionMessage = error instanceof Error ? error.message : String(error);
  }
  expect(rejectionMessage).toBe("third");
  expect(fn()).toBe("base");
});

test("spyOn wraps method calls and restores original descriptor", () => {
  const calculator = {
    add(left: number, right: number) {
      return left + right;
    }
  };

  const methodSpy = spyOn(calculator, "add");
  expect(calculator.add(10, 1)).toBe(11);
  expect(methodSpy.mock.calls.length).toBe(1);

  methodSpy.mockReturnValue(77);
  expect(calculator.add(10, 1)).toBe(77);

  methodSpy.mockRestore();
  expect(calculator.add(10, 1)).toBe(11);
});

test("spyOn supports getter replacement and reset", () => {
  const state = {
    value: 12,
    get computed() {
      return this.value + 1;
    }
  };

  const getterSpy = spyOn(state, "computed");
  expect(state.computed).toBe(13);

  getterSpy.mockReturnValue(42);
  expect(state.computed).toBe(42);

  getterSpy.mockReset();
  expect(state.computed).toBe(13);

  getterSpy.mockRestore();
  expect(state.computed).toBe(13);
});

test("stacked spyOn with once values preserves sequential fetch results", async () => {
  const first = spyOn(window, "fetch").mockResolvedValueOnce(new Response("one"));
  const second = spyOn(window, "fetch").mockResolvedValueOnce(new Response("two"));

  const a = await fetch("/a");
  const b = await fetch("/b");

  expect(await a.text()).toBe("one");
  expect(await b.text()).toBe("two");
  expect(first).toBe(second);
  expect(second.mock.calls.length).toBe(2);

  second.mockRestore();
  first.mockRestore();
});

test("spyOn works for non-configurable writable methods", () => {
  const target = {
    request(args: unknown) {
      return args;
    }
  } as { request: (args: unknown) => unknown };

  const original = target.request;
  Object.defineProperty(target, "request", {
    value: original,
    writable: true,
    configurable: false,
    enumerable: true
  });

  const first = spyOn(target, "request");
  target.request({ kind: "first" });
  const second = spyOn(target, "request");
  target.request({ kind: "second" });

  expect(first).toBe(second);
  expect(second.mock.calls.length).toBe(2);
  expect(second).toHaveBeenNthCalledWith(2, expect.objectContaining({ kind: "second" }));

  second.mockRestore();
});


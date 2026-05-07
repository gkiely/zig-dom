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

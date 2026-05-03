import { fireEvent, render } from "@testing-library/react";
import { expect, test } from "bun:test";
import { useState } from "react";

function Counter(): JSX.Element {
  const [count, setCount] = useState(0);
  return (
    <section>
      <button onClick={() => setCount((value) => value + 1)}>Increment</button>
      <p>Count: {count}</p>
    </section>
  );
}

test("click updates UI", () => {
  const { getByText } = render(<Counter />);
  fireEvent.click(getByText("Increment"));
  expect(getByText("Count: 1")).toBeDefined();
});

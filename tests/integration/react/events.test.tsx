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

test("composition handlers receive event data payloads", () => {
  function CompositionHarness(): JSX.Element {
    const [log, setLog] = useState<string[]>([]);

    return (
      <section>
        <input
          aria-label="ime-input"
          onCompositionStart={(event) => {
            setLog((entries) => [...entries, `start:${event.data ?? ""}`]);
          }}
          onCompositionUpdate={(event) => {
            setLog((entries) => [...entries, `update:${event.data ?? ""}`]);
          }}
          onCompositionEnd={(event) => {
            setLog((entries) => [...entries, `end:${event.data ?? ""}`]);
          }}
        />
        <output>{log.join("|")}</output>
      </section>
    );
  }

  const { getByLabelText, getByText } = render(<CompositionHarness />);
  const input = getByLabelText("ime-input") as HTMLInputElement;

  fireEvent.compositionStart(input, { data: "" });
  fireEvent.compositionUpdate(input, { data: "に" });
  fireEvent.compositionEnd(input, { data: "に" });

  expect(getByText("start:|update:に|end:に")).toBeDefined();
});

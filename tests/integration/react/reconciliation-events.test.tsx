import { fireEvent, render } from "@testing-library/react";
import { describe, expect, test } from "bun:test";
import { useState } from "react";

describe("react reconciliation and event interop", () => {
  test("keyed list reorder preserves item-local state", () => {
    function Item({ id }: { id: string }): JSX.Element {
      const [count, setCount] = useState(0);
      return <button onClick={() => setCount((value) => value + 1)}>{`${id}:${count}`}</button>;
    }

    function ListHarness(): JSX.Element {
      const [order, setOrder] = useState(["A", "B"]);

      return (
        <section>
          <button onClick={() => setOrder((items) => [...items].reverse())}>Reorder</button>
          <ul>
            {order.map((id) => (
              <li key={id}>
                <Item id={id} />
              </li>
            ))}
          </ul>
        </section>
      );
    }

    const { getAllByRole, getByText } = render(<ListHarness />);

    fireEvent.click(getByText("A:0"));
    expect(getByText("A:1")).toBeDefined();

    fireEvent.click(getByText("Reorder"));

    expect(getByText("A:1")).toBeDefined();

    const orderAfterReorder = getAllByRole("listitem").map((node) => node.textContent ?? "");
    expect(orderAfterReorder[0]?.includes("B:0")).toBe(true);
    expect(orderAfterReorder[1]?.includes("A:1")).toBe(true);
  });

  test("stopPropagation blocks parent click handlers", () => {
    function BubbleHarness(): JSX.Element {
      const [parentClicks, setParentClicks] = useState(0);
      const [childClicks, setChildClicks] = useState(0);

      return (
        <div data-testid="parent" onClick={() => setParentClicks((value) => value + 1)}>
          <button
            onClick={(event) => {
              event.stopPropagation();
              setChildClicks((value) => value + 1);
            }}
          >
            Child
          </button>
          <output>{`parent:${parentClicks};child:${childClicks}`}</output>
        </div>
      );
    }

    const { getByTestId, getByText } = render(<BubbleHarness />);

    fireEvent.click(getByText("Child"));
    expect(getByText("parent:0;child:1")).toBeDefined();

    fireEvent.click(getByTestId("parent"));
    expect(getByText("parent:1;child:1")).toBeDefined();
  });

  test("controlled checkbox state and label stay synchronized", () => {
    function CheckboxHarness(): JSX.Element {
      const [checked, setChecked] = useState(false);

      return (
        <section>
          <label>
            Receive updates
            <input
              type="checkbox"
              checked={checked}
              onChange={() => {}}
              onInput={(event) => setChecked((event.target as HTMLInputElement).checked)}
            />
          </label>
          <p>{checked ? "enabled" : "disabled"}</p>
        </section>
      );
    }

    const { getByRole, getByText } = render(<CheckboxHarness />);
    const checkbox = getByRole("checkbox") as HTMLInputElement;

    expect(checkbox.checked).toBe(false);
    expect(getByText("disabled")).toBeDefined();

    fireEvent.click(checkbox);

    expect(checkbox.checked).toBe(true);
    expect(getByText("enabled")).toBeDefined();
  });

  test("rerender updates host attributes and text nodes", () => {
    function ButtonHarness({ disabled, label }: { disabled: boolean; label: string }): JSX.Element {
      return <button disabled={disabled}>{label}</button>;
    }

    const { getByRole, rerender } = render(<ButtonHarness disabled={false} label="Save" />);
    const buttonBefore = getByRole("button", { name: "Save" }) as HTMLButtonElement;

    expect(buttonBefore.disabled).toBe(false);

    rerender(<ButtonHarness disabled label="Saving" />);

    const buttonAfter = getByRole("button", { name: "Saving" }) as HTMLButtonElement;
    expect(buttonAfter.disabled).toBe(true);
  });
});
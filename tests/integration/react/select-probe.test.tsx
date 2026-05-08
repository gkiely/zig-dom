import { fireEvent, render } from "@testing-library/react";
import { expect, test } from "bun:test";
import { useRef } from "react";

function AdvancedFormHarness(): JSX.Element {
  return (
    <form>
      <label htmlFor="name-field">Name</label>
      <input id="name-field" defaultValue="Grace" />

      <label>
        Notes
        <textarea defaultValue="Initial note" />
      </label>

      <select defaultValue="b">
        <option value="a">A</option>
        <option value="b">B</option>
      </select>

      <button type="reset">Reset</button>
    </form>
  );
}

function SelectValueHarness(): JSX.Element {
  const selectRef = useRef<HTMLSelectElement | null>(null);

  return (
    <section>
      <select ref={selectRef} aria-label="single-select" defaultValue="a">
        <option value="a">A</option>
        <option value="b">B</option>
      </select>
      <button
        type="button"
        onClick={() => {
          if (selectRef.current) {
            selectRef.current.value = "missing";
          }
        }}
      >
        Select missing
      </button>
    </section>
  );
}

test("advanced form reset probe", () => {
  const { getByLabelText, getByRole, getByText } = render(<AdvancedFormHarness />);

  const input = getByLabelText("Name") as HTMLInputElement;
  const textarea = getByLabelText("Notes") as HTMLTextAreaElement;
  const select = getByRole("combobox") as HTMLSelectElement;

  input.value = "Updated";
  textarea.value = "Changed note";
  select.value = "a";

  fireEvent.click(getByText("Reset"));

  expect(input.value).toBe("Grace");
  expect(textarea.value).toBe("Initial note");
  expect(select.value).toBe("b");
  expect(select.options[0].selected).toBe(false);
  expect(select.options[1].selected).toBe(true);
});

test("missing select value probe", () => {
  const { getByLabelText, getByText } = render(<SelectValueHarness />);
  const select = getByLabelText("single-select") as HTMLSelectElement;
  const before = select.value;

  fireEvent.click(getByText("Select missing"));

  expect(before).toBe("a");
  expect(select.value).toBe("");
  expect(select.options[0].selected).toBe(false);
  expect(select.options[1].selected).toBe(false);
});

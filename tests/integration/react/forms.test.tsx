import { fireEvent, render } from "@testing-library/react";
import { expect, test } from "bun:test";
import { useState } from "react";

function FormHarness(): JSX.Element {
  const [value, setValue] = useState("");
  const [submitted, setSubmitted] = useState(false);

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        setSubmitted(true);
      }}
    >
      <input
        aria-label="name"
        value={value}
        onInput={(event) => setValue((event.target as HTMLInputElement).value)}
        onChange={(event) => setValue((event.target as HTMLInputElement).value)}
      />
      <button type="submit">Submit</button>
      <output>{submitted ? `submitted:${value}` : "idle"}</output>
    </form>
  );
}

test("input and submit behavior (cold)", () => {
  const { getByLabelText, getByText } = render(<FormHarness />);
  const input = getByLabelText("name") as HTMLInputElement;

  fireEvent.input(input, { target: { value: "Ada" } });
  fireEvent.change(input, { target: { value: "Ada" } });
  fireEvent.click(getByText("Submit"));

  expect((input as unknown as { value: string }).value).toBe("Ada");
  expect(getByText("submitted:Ada")).toBeDefined();
});

test("input and submit behavior (warm)", () => {
  const { getByLabelText, getByText } = render(<FormHarness />);
  const input = getByLabelText("name") as HTMLInputElement;

  fireEvent.input(input, { target: { value: "Ada" } });
  fireEvent.change(input, { target: { value: "Ada" } });
  fireEvent.click(getByText("Submit"));

  expect((input as unknown as { value: string }).value).toBe("Ada");
  expect(getByText("submitted:Ada")).toBeDefined();
});

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

test("form controls support default values and reset", () => {
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
});


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

test("label htmlFor click toggles controlled checkbox", () => {
  function LabelForCheckboxHarness(): JSX.Element {
    const [checked, setChecked] = useState(false);

    return (
      <section>
        <label htmlFor="opt-in">Opt in</label>
        <input
          id="opt-in"
          type="checkbox"
          checked={checked}
          onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
        />
        <output>{checked ? "enabled" : "disabled"}</output>
      </section>
    );
  }

  const { getByRole, getByText } = render(<LabelForCheckboxHarness />);
  const checkbox = getByRole("checkbox") as HTMLInputElement;

  expect(checkbox.checked).toBe(false);
  expect(getByText("disabled")).toBeDefined();

  fireEvent.click(getByText("Opt in"));

  expect(checkbox.checked).toBe(true);
  expect(getByText("enabled")).toBeDefined();
});

test("wrapping label click toggles nested controlled checkbox", () => {
  function NestedLabelCheckboxHarness(): JSX.Element {
    const [checked, setChecked] = useState(false);

    return (
      <label>
        Receive updates
        <input
          type="checkbox"
          checked={checked}
          onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
        />
        <output>{checked ? "enabled" : "disabled"}</output>
      </label>
    );
  }

  const { getByRole, getByText } = render(<NestedLabelCheckboxHarness />);
  const checkbox = getByRole("checkbox") as HTMLInputElement;

  expect(checkbox.checked).toBe(false);
  expect(getByText("disabled")).toBeDefined();

  fireEvent.click(getByText("Receive updates"));

  expect(checkbox.checked).toBe(true);
  expect(getByText("enabled")).toBeDefined();
});

test("child element click inside htmlFor label toggles controlled checkbox", () => {
  function HtmlForLabelChildHarness(): JSX.Element {
    const [checked, setChecked] = useState(false);

    return (
      <section>
        <label htmlFor="alerts-checkbox">
          <span>Enable alerts</span>
        </label>
        <input
          id="alerts-checkbox"
          type="checkbox"
          checked={checked}
          onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
        />
      </section>
    );
  }

  const { getByRole, getByText } = render(<HtmlForLabelChildHarness />);
  const checkbox = getByRole("checkbox") as HTMLInputElement;

  expect(checkbox.checked).toBe(false);

  fireEvent.click(getByText("Enable alerts"));

  expect(checkbox.checked).toBe(true);
});

test("child element click inside wrapping label toggles nested checkbox", () => {
  function NestedLabelChildHarness(): JSX.Element {
    const [checked, setChecked] = useState(false);

    return (
      <label>
        <span>Receive alerts</span>
        <input
          type="checkbox"
          checked={checked}
          onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
        />
      </label>
    );
  }

  const { getByRole, getByText } = render(<NestedLabelChildHarness />);
  const checkbox = getByRole("checkbox") as HTMLInputElement;

  expect(checkbox.checked).toBe(false);

  fireEvent.click(getByText("Receive alerts"));

  expect(checkbox.checked).toBe(true);
});

test("interactive link click inside htmlFor label does not toggle checkbox", () => {
  function HtmlForInteractiveChildHarness(): JSX.Element {
    const [checked, setChecked] = useState(false);

    return (
      <section>
        <label htmlFor="news-checkbox">
          <a href="#help">Help</a>
        </label>
        <input
          id="news-checkbox"
          type="checkbox"
          checked={checked}
          onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
        />
      </section>
    );
  }

  const { getByRole, getByText } = render(<HtmlForInteractiveChildHarness />);
  const checkbox = getByRole("checkbox") as HTMLInputElement;

  expect(checkbox.checked).toBe(false);

  fireEvent.click(getByText("Help"));

  expect(checkbox.checked).toBe(false);
});

test("uncontrolled radios keep single checked value in same group", () => {
  function UncontrolledRadiosHarness(): JSX.Element {
    return (
      <section>
        <input type="radio" name="pet" value="cat" defaultChecked aria-label="cat" />
        <input type="radio" name="pet" value="dog" aria-label="dog" />
      </section>
    );
  }

  const { getByLabelText } = render(<UncontrolledRadiosHarness />);
  const cat = getByLabelText("cat") as HTMLInputElement;
  const dog = getByLabelText("dog") as HTMLInputElement;

  expect(cat.checked).toBe(true);
  expect(dog.checked).toBe(false);

  fireEvent.click(dog);

  expect(cat.checked).toBe(false);
  expect(dog.checked).toBe(true);
});

test("jsdom parity: multiple defaultChecked radios can both appear checked", () => {
  function DefaultCheckedRadioHarness(): JSX.Element {
    return (
      <section>
        <input type="radio" name="size" defaultChecked aria-label="small" />
        <input type="radio" name="size" defaultChecked aria-label="large" />
      </section>
    );
  }

  const { getByLabelText } = render(<DefaultCheckedRadioHarness />);
  const small = getByLabelText("small") as HTMLInputElement;
  const large = getByLabelText("large") as HTMLInputElement;

  expect(small.checked).toBe(true);
  expect(large.checked).toBe(true);
});

test("clicking already checked radio does not fire onInput", () => {
  function CheckedRadioInputHarness(): JSX.Element {
    const [inputs, setInputs] = useState(0);

    return (
      <section>
        <input
          type="radio"
          name="mode"
          defaultChecked
          aria-label="mode"
          onInput={() => setInputs((value) => value + 1)}
        />
        <output>{inputs}</output>
      </section>
    );
  }

  const { getByLabelText, getByText } = render(<CheckedRadioInputHarness />);

  fireEvent.click(getByLabelText("mode"));

  expect(getByText("0")).toBeDefined();
});


import { fireEvent, render } from "@testing-library/react";
import { describe, expect, test } from "bun:test";
import { useRef, useState } from "react";

describe("react experiments", () => {
  test("text input onChange reacts to input event", () => {
    function Harness(): JSX.Element {
      const [value, setValue] = useState("");
      return (
        <>
          <input aria-label="name" value={value} onChange={(event) => setValue((event.target as HTMLInputElement).value)} />
          <output>{value}</output>
        </>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const input = getByLabelText("name") as HTMLInputElement;

    fireEvent.input(input, { target: { value: "Ada" } });

    expect(getByText("Ada")).toBeDefined();
  });

  test("child click inside htmlFor label toggles checkbox", () => {
    function Harness(): JSX.Element {
      const [checked, setChecked] = useState(false);

      return (
        <section>
          <label htmlFor="alerts-box">
            <span>Enable alerts</span>
          </label>
          <input
            id="alerts-box"
            type="checkbox"
            checked={checked}
            onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
          />
        </section>
      );
    }

    const { getByRole, getByText } = render(<Harness />);
    const checkbox = getByRole("checkbox") as HTMLInputElement;

    expect(checkbox.checked).toBe(false);

    fireEvent.click(getByText("Enable alerts"));

    expect(checkbox.checked).toBe(true);
  });

  test("child click inside wrapping label toggles checkbox", () => {
    function Harness(): JSX.Element {
      const [checked, setChecked] = useState(false);

      return (
        <label>
          <span>Receive updates</span>
          <input
            type="checkbox"
            checked={checked}
            onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
          />
        </label>
      );
    }

    const { getByRole, getByText } = render(<Harness />);
    const checkbox = getByRole("checkbox") as HTMLInputElement;

    expect(checkbox.checked).toBe(false);

    fireEvent.click(getByText("Receive updates"));

    expect(checkbox.checked).toBe(true);
  });

  test("disabled control is not toggled by label click", () => {
    function Harness(): JSX.Element {
      const [checked, setChecked] = useState(false);

      return (
        <label htmlFor="disabled-box">
          Disabled option
          <input
            id="disabled-box"
            type="checkbox"
            disabled
            checked={checked}
            onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
          />
        </label>
      );
    }

    const { getByText, getByRole } = render(<Harness />);
    const checkbox = getByRole("checkbox") as HTMLInputElement;

    fireEvent.click(getByText("Disabled option"));

    expect(checkbox.checked).toBe(false);
  });

  test("uncontrolled radios keep one checked in same group", () => {
    function Harness(): JSX.Element {
      return (
        <section>
          <input type="radio" name="pet" value="cat" defaultChecked aria-label="cat" />
          <input type="radio" name="pet" value="dog" aria-label="dog" />
        </section>
      );
    }

    const { getByLabelText } = render(<Harness />);
    const cat = getByLabelText("cat") as HTMLInputElement;
    const dog = getByLabelText("dog") as HTMLInputElement;

    fireEvent.click(dog);

    expect(cat.checked).toBe(false);
    expect(dog.checked).toBe(true);
  });

  test("clicking already checked radio does not trigger onChange", () => {
    function Harness(): JSX.Element {
      const [changes, setChanges] = useState(0);

      return (
        <>
          <input
            type="radio"
            name="plan"
            defaultChecked
            aria-label="plan"
            onChange={() => setChanges((value) => value + 1)}
          />
          <output>{changes}</output>
        </>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const plan = getByLabelText("plan") as HTMLInputElement;

    fireEvent.click(plan);

    expect(getByText("0")).toBeDefined();
  });

  test("same radio name in different forms remains isolated", () => {
    function Harness(): JSX.Element {
      return (
        <>
          <form>
            <input type="radio" name="group" defaultChecked aria-label="form-a" />
          </form>
          <form>
            <input type="radio" name="group" defaultChecked aria-label="form-b" />
          </form>
        </>
      );
    }

    const { getByLabelText } = render(<Harness />);
    const formA = getByLabelText("form-a") as HTMLInputElement;
    const formB = getByLabelText("form-b") as HTMLInputElement;

    fireEvent.click(formA);

    expect(formA.checked).toBe(true);
    expect(formB.checked).toBe(true);
  });

  test("button type button does not submit a form", () => {
    function Harness(): JSX.Element {
      const [submitted, setSubmitted] = useState(false);

      return (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            setSubmitted(true);
          }}
        >
          <button type="button">No submit</button>
          <output>{submitted ? "submitted" : "idle"}</output>
        </form>
      );
    }

    const { getByText } = render(<Harness />);

    fireEvent.click(getByText("No submit"));

    expect(getByText("idle")).toBeDefined();
  });

  test("preventDefault on checkbox click preserves checked state", () => {
    function Harness(): JSX.Element {
      const [checked, setChecked] = useState(false);

      return (
        <input
          type="checkbox"
          aria-label="terms"
          checked={checked}
          onClick={(event) => event.preventDefault()}
          onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
        />
      );
    }

    const { getByLabelText } = render(<Harness />);
    const checkbox = getByLabelText("terms") as HTMLInputElement;

    fireEvent.click(checkbox);

    expect(checkbox.checked).toBe(false);
  });

  test("label-based checkbox activation dispatches one change", () => {
    function Harness(): JSX.Element {
      const [changes, setChanges] = useState(0);
      const [checked, setChecked] = useState(false);

      return (
        <section>
          <label htmlFor="notify">Notify me</label>
          <input
            id="notify"
            type="checkbox"
            checked={checked}
            onChange={(event) => {
              setChecked((event.target as HTMLInputElement).checked);
              setChanges((value) => value + 1);
            }}
          />
          <output>{changes}</output>
        </section>
      );
    }

    const { getByText } = render(<Harness />);

    fireEvent.click(getByText("Notify me"));

    expect(getByText("1")).toBeDefined();
  });

  test("controlled select onChange updates value", () => {
    function Harness(): JSX.Element {
      const [value, setValue] = useState("a");
      return (
        <>
          <select aria-label="choice" value={value} onChange={(event) => setValue((event.target as HTMLSelectElement).value)}>
            <option value="a">A</option>
            <option value="b">B</option>
          </select>
          <output>{value}</output>
        </>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const select = getByLabelText("choice") as HTMLSelectElement;

    fireEvent.change(select, { target: { value: "b" } });

    expect(getByText("b")).toBeDefined();
    expect(select.value).toBe("b");
  });

  test("imperative radio checked assignment clears same-name sibling", () => {
    function Harness(): JSX.Element {
      const firstRef = useRef<HTMLInputElement | null>(null);
      const secondRef = useRef<HTMLInputElement | null>(null);

      return (
        <section>
          <input ref={firstRef} type="radio" name="tone" defaultChecked aria-label="first-tone" />
          <input ref={secondRef} type="radio" name="tone" aria-label="second-tone" />
          <button
            type="button"
            onClick={() => {
              if (secondRef.current) {
                secondRef.current.checked = true;
              }
            }}
          >
            Select second
          </button>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const first = getByLabelText("first-tone") as HTMLInputElement;
    const second = getByLabelText("second-tone") as HTMLInputElement;

    expect(first.checked).toBe(true);
    expect(second.checked).toBe(false);

    fireEvent.click(getByText("Select second"));

    expect(first.checked).toBe(false);
    expect(second.checked).toBe(true);
  });

  test("imperative option selected assignment updates single-select state", () => {
    function Harness(): JSX.Element {
      const optionARef = useRef<HTMLOptionElement | null>(null);
      const optionBRef = useRef<HTMLOptionElement | null>(null);

      return (
        <section>
          <select aria-label="letters" defaultValue="a">
            <option ref={optionARef} value="a">
              A
            </option>
            <option ref={optionBRef} value="b">
              B
            </option>
          </select>
          <button
            type="button"
            onClick={() => {
              if (optionBRef.current) {
                optionBRef.current.selected = true;
              }
            }}
          >
            Select B
          </button>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const select = getByLabelText("letters") as HTMLSelectElement;

    expect(select.value).toBe("a");

    fireEvent.click(getByText("Select B"));

    expect(select.value).toBe("b");
  });

  test("interactive button inside label does not toggle nested checkbox", () => {
    function Harness(): JSX.Element {
      const [checked, setChecked] = useState(false);

      return (
        <label>
          <button type="button">Help</button>
          <input
            type="checkbox"
            checked={checked}
            onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
          />
        </label>
      );
    }

    const { getByRole, getByText } = render(<Harness />);
    const checkbox = getByRole("checkbox") as HTMLInputElement;

    expect(checkbox.checked).toBe(false);

    fireEvent.click(getByText("Help"));

    expect(checkbox.checked).toBe(false);
  });

  test("interactive link inside htmlFor label does not toggle checkbox", () => {
    function Harness(): JSX.Element {
      const [checked, setChecked] = useState(false);

      return (
        <section>
          <label htmlFor="news-box">
            <a href="#help">Help</a>
          </label>
          <input
            id="news-box"
            type="checkbox"
            checked={checked}
            onChange={(event) => setChecked((event.target as HTMLInputElement).checked)}
          />
        </section>
      );
    }

    const { getByRole, getByText } = render(<Harness />);
    const checkbox = getByRole("checkbox") as HTMLInputElement;

    expect(checkbox.checked).toBe(false);

    fireEvent.click(getByText("Help"));

    expect(checkbox.checked).toBe(false);
  });

  test("imperative option selection in multiple select keeps other selections", () => {
    function Harness(): JSX.Element {
      const optionARef = useRef<HTMLOptionElement | null>(null);
      const optionBRef = useRef<HTMLOptionElement | null>(null);

      return (
        <section>
          <select aria-label="letters-multi" multiple>
            <option ref={optionARef} value="a">
              A
            </option>
            <option ref={optionBRef} value="b">
              B
            </option>
          </select>
          <button
            type="button"
            onClick={() => {
              if (optionARef.current) {
                optionARef.current.selected = true;
              }
              if (optionBRef.current) {
                optionBRef.current.selected = true;
              }
            }}
          >
            Select A and B
          </button>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const select = getByLabelText("letters-multi") as HTMLSelectElement;

    fireEvent.click(getByText("Select A and B"));

    const selectedValues = [...select.options].filter((option) => option.selected).map((option) => option.value).sort();
    expect(selectedValues).toEqual(["a", "b"]);
  });

  test("single select value set to unknown option yields empty value", () => {
    function Harness(): JSX.Element {
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

    const { getByLabelText, getByText } = render(<Harness />);
    const select = getByLabelText("single-select") as HTMLSelectElement;

    expect(select.value).toBe("a");

    fireEvent.click(getByText("Select missing"));

    expect(select.value).toBe("");
  });

  test("controlled multiple select accepts value arrays", () => {
    function Harness(): JSX.Element {
      const [value, setValue] = useState<string[]>(["a"]);

      return (
        <section>
          <select multiple aria-label="controlled-multi" value={value} onChange={() => {}}>
            <option value="a">A</option>
            <option value="b">B</option>
            <option value="c">C</option>
          </select>
          <button type="button" onClick={() => setValue(["a", "b"])}>
            Select A and B
          </button>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const select = getByLabelText("controlled-multi") as HTMLSelectElement;

    fireEvent.click(getByText("Select A and B"));

    const selectedValues = [...select.options]
      .filter((option) => option.selected)
      .map((option) => option.value)
      .sort();
    expect(selectedValues).toEqual(["a", "b"]);
  });

  test("form reset restores checkbox defaultChecked state", () => {
    function Harness(): JSX.Element {
      return (
        <form>
          <input aria-label="updates" type="checkbox" defaultChecked />
          <button type="reset">Reset</button>
        </form>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const checkbox = getByLabelText("updates") as HTMLInputElement;

    checkbox.checked = false;
    expect(checkbox.checked).toBe(false);

    fireEvent.click(getByText("Reset"));

    expect(checkbox.checked).toBe(true);
  });
});
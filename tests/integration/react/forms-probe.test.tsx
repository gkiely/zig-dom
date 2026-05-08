import { fireEvent, render } from "@testing-library/react";
import { expect, test } from "bun:test";
import { useState } from "react";

function FormHarness(): JSX.Element {
  const [value, setValue] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [changes, setChanges] = useState(0);

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
        onChange={(event) => {
          setValue((event.target as HTMLInputElement).value);
          setChanges((count) => count + 1);
        }}
      />
      <button type="submit">Submit</button>
      <output>{submitted ? `submitted:${value}` : "idle"}</output>
      <small>{`changes:${changes}`}</small>
    </form>
  );
}

test("probe", () => {
  let docInput = 0;
  let docChange = 0;
  let docInputCapture = 0;
  document.addEventListener("input", () => {
    docInput += 1;
  });
  document.addEventListener(
    "input",
    () => {
      docInputCapture += 1;
    },
    true
  );
  document.addEventListener("change", () => {
    docChange += 1;
  });

  const { getByLabelText, getByText, container } = render(<FormHarness />);
  const input = getByLabelText("name") as HTMLInputElement;
  const ownValueDescriptorBefore = Object.getOwnPropertyDescriptor(input, "value");
  const protoValueDescriptorBefore = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(input), "value");

  fireEvent.input(input, { target: { value: "Ada" } });
  const afterInput = input.value;
  fireEvent.change(input, { target: { value: "Ada" } });
  const afterChange = input.value;
  fireEvent.click(getByText("Submit"));

  expect(afterInput).toBe("Ada");
  expect(afterChange).toBe("Ada");
  expect(input.value).toBe("Ada");
  expect(container.querySelector("output")?.textContent ?? null).toBe("submitted:Ada");
  expect(container.querySelector("small")?.textContent ?? null).toBe("changes:1");
  expect(docInput).toBe(1);
  expect(docInputCapture).toBe(1);
  expect(docChange).toBe(1);
  expect(!!ownValueDescriptorBefore).toBe(true);
  expect(!!protoValueDescriptorBefore).toBe(true);
  expect(
    ownValueDescriptorBefore?.set != null &&
      protoValueDescriptorBefore?.set != null &&
      ownValueDescriptorBefore.set === protoValueDescriptorBefore.set
  ).toBe(false);
});

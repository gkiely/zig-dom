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

test("input and submit behavior", () => {
  const { getByLabelText, getByText } = render(<FormHarness />);
  const input = getByLabelText("name") as HTMLInputElement;

  fireEvent.input(input, { target: { value: "Ada" } });
  fireEvent.change(input, { target: { value: "Ada" } });
  fireEvent.click(getByText("Submit"));

  expect((input as unknown as { value: string }).value).toBe("Ada");
  expect(getByText("submitted:Ada")).toBeDefined();
});

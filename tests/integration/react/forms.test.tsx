import { expect, test } from "bun:test";
import { fireEvent, render, screen } from "@testing-library/react";
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
  render(<FormHarness />);
  const input = screen.getByLabelText("name") as HTMLInputElement;

  fireEvent.input(input, { target: { value: "Ada" } });
  fireEvent.change(input, { target: { value: "Ada" } });
  fireEvent.click(screen.getByText("Submit"));

  expect((input as unknown as { value: string }).value).toBe("Ada");
  expect(screen.getByText("submitted:Ada")).toBeDefined();
});

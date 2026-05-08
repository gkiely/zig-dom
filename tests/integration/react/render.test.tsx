import { render } from "@testing-library/react";
import { expect, test } from "bun:test";
import App from "./App";

test("renders app root", () => {
  const { container, getByTestId } = render(<App />);

  expect(container.firstChild).not.toBeNull();
  expect(getByTestId("app-root").textContent).toBe("Hello from Zig DOM");
});

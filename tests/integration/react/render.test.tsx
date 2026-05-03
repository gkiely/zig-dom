import "../../setup/register-dom";
import { expect, test } from "bun:test";
import { render, screen } from "@testing-library/react";
import App from "./App";

test("renders app root", () => {
  const { container } = render(<App />);

  expect(container.firstChild).not.toBeNull();
  expect(screen.getByTestId("app-root").textContent).toBe("Hello from Zig DOM");
});

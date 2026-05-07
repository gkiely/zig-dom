import React from "react";
import { fireEvent, render, screen } from "@testing-library/react";
import { expect, test } from "bun:test";

test("testing-library render smoke", () => {
  let clicks = 0;

  function App() {
    return React.createElement(
      "button",
      {
        onClick: () => {
          clicks += 1;
        }
      },
      "Tap"
    );
  }

  const view = render(React.createElement(App));
  const button = screen.getByText("Tap");
  fireEvent.click(button);

  expect(clicks).toBe(1);
  view.unmount();
});

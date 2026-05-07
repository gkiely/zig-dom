import React from "react";
import * as ReactDOMClient from "react-dom/client";
import { expect, test } from "bun:test";

test("react 18 createRoot render smoke", () => {
  const container = document.createElement("div");
  document.body.appendChild(container);

  const root = ReactDOMClient.createRoot(container);
  root.render(React.createElement("button", { id: "save" }, "Save"));

  const button = container.querySelector("button");
  expect(button.textContent).toBe("Save");

  root.unmount();
  expect(container.textContent).toBe("");
});

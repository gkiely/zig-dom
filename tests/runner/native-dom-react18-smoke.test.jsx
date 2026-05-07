import React from "react";
import { flushSync } from "react-dom";
import * as ReactDOMClient from "react-dom/client";
import { expect, test } from "bun:test";

test("react 18 createRoot render smoke", async () => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const container = document.createElement("div");
  document.body.appendChild(container);

  const root = ReactDOMClient.createRoot(container);
  flushSync(() => {
    root.render(React.createElement("button", { id: "save" }, "Save"));
  });
  await new Promise((resolve) => setTimeout(resolve, 0));

  expect(container.textContent).toBe("Save");

  flushSync(() => {
    root.unmount();
  });
  expect(container.textContent).toBe("");
});

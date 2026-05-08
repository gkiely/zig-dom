import { render } from "@testing-library/react";
import { expect, test } from "bun:test";
import { useEffect, useState } from "react";

function AsyncHarness(): JSX.Element {
  const [status, setStatus] = useState("loading");

  useEffect(() => {
    queueMicrotask(() => {
      setStatus("ready");
    });
  }, []);

  return <p>{status}</p>;
}

test("probe async effect", async () => {
  const { queryByText } = render(<AsyncHarness />);
  await Promise.resolve();
  await Promise.resolve();
  await new Promise<void>((resolve) => {
    setTimeout(resolve, 0);
  });
  expect(!!queryByText("loading")).toBe(false);
  expect(!!queryByText("ready")).toBe(true);
});

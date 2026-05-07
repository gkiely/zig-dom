import { expect, spyOn, test } from "bun:test";
import { render, screen } from "@testing-library/react";
import { useEffect, useState } from "react";

const delay = (ms = 0) => new Promise((resolve) => setTimeout(resolve, ms));

function FetchWidget() {
  const [name, setName] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;
    fetch("/api/user/me")
      .then((res) => res.json<{ name: string }>())
      .then((value) => {
        if (mounted) setName(value.name);
      });
    return () => {
      mounted = false;
    };
  }, []);

  if (!name) return null;
  return <div>{name}</div>;
}

test("async fetch updates rendered output", async () => {
  const fetchSpy = spyOn(window, "fetch").mockResolvedValueOnce(
    new Response(JSON.stringify({ name: "ok" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    })
  );

  render(<FetchWidget />);
  await delay();
  await delay();

  expect(fetchSpy.mock.calls.length).toBe(1);
  expect(screen.getByText("ok")).toBeInTheDocument();
});

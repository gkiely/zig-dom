import { fireEvent, render } from "@testing-library/react";
import { describe, expect, test } from "bun:test";
import { createContext, useContext, useEffect, useMemo, useState } from "react";

describe("react hooks and context integration", () => {
  test("useEffect runs setup and cleanup in dependency order", () => {
    const lifecycleLog: string[] = [];

    function EffectHarness({ value }: { value: number }): JSX.Element {
      useEffect(() => {
        lifecycleLog.push(`effect:${value}`);
        return () => {
          lifecycleLog.push(`cleanup:${value}`);
        };
      }, [value]);

      return <p>{value}</p>;
    }

    const { rerender, unmount } = render(<EffectHarness value={1} />);
    rerender(<EffectHarness value={2} />);
    unmount();

    expect(lifecycleLog).toEqual(["effect:1", "cleanup:1", "effect:2", "cleanup:2"]);
  });

  test("context consumers update when provider value changes", () => {
    const ThemeContext = createContext("light");

    function ThemeLabel(): JSX.Element {
      const theme = useContext(ThemeContext);
      return <p>theme:{theme}</p>;
    }

    function ThemeHarness(): JSX.Element {
      const [theme, setTheme] = useState("light");

      return (
        <ThemeContext.Provider value={theme}>
          <button onClick={() => setTheme("dark")}>Switch Theme</button>
          <ThemeLabel />
        </ThemeContext.Provider>
      );
    }

    const { getByText } = render(<ThemeHarness />);

    expect(getByText("theme:light")).toBeDefined();
    fireEvent.click(getByText("Switch Theme"));
    expect(getByText("theme:dark")).toBeDefined();
  });

  test("useMemo skips recomputation on unrelated state updates", () => {
    let memoComputations = 0;

    function MemoHarness(): JSX.Element {
      const [multiplier, setMultiplier] = useState(2);
      const [unrelated, setUnrelated] = useState(0);

      const computed = useMemo(() => {
        memoComputations += 1;
        return multiplier * 10;
      }, [multiplier]);

      return (
        <section>
          <button onClick={() => setUnrelated((value) => value + 1)}>Tick</button>
          <button onClick={() => setMultiplier((value) => value + 1)}>Scale</button>
          <p>{`value:${computed};tick:${unrelated}`}</p>
        </section>
      );
    }

    const { getByText } = render(<MemoHarness />);

    expect(getByText("value:20;tick:0")).toBeDefined();
    expect(memoComputations).toBe(1);

    fireEvent.click(getByText("Tick"));
    expect(getByText("value:20;tick:1")).toBeDefined();
    expect(memoComputations).toBe(1);

    fireEvent.click(getByText("Scale"));
    expect(getByText("value:30;tick:1")).toBeDefined();
    expect(memoComputations).toBe(2);
  });

  test("findByText resolves microtask-driven effect updates", async () => {
    function AsyncHarness(): JSX.Element {
      const [status, setStatus] = useState("loading");

      useEffect(() => {
        queueMicrotask(() => {
          setStatus("ready");
        });
      }, []);

      return <p>{status}</p>;
    }

    const { findByText } = render(<AsyncHarness />);
    expect(await findByText("ready")).toBeDefined();
  });
});
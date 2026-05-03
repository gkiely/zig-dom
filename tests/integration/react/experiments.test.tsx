import { fireEvent, render, waitFor } from "@testing-library/react";
import { describe, expect, test } from "bun:test";
import { createPortal } from "react-dom";
import { useState } from "react";

describe("react experiments: portals", () => {
  test("unmounting portal subtree clears host container", () => {
    function Harness({ visible, host }: { visible: boolean; host: HTMLElement }): JSX.Element {
      return <section>{visible ? createPortal(<p data-testid="portal-child">portal text</p>, host) : null}</section>;
    }

    const host = document.createElement("div");
    host.setAttribute("data-testid", "portal-host");
    document.body.appendChild(host);

    const { rerender } = render(<Harness visible host={host} />);
    expect(host.textContent).toBe("portal text");

    rerender(<Harness visible={false} host={host} />);
    expect(host.childNodes.length).toBe(0);

    document.body.removeChild(host);
  });

  test("retargeting a portal moves content between hosts", () => {
    function Harness({ host }: { host: HTMLElement }): JSX.Element {
      return <section>{createPortal(<p data-testid="portal-child">teleport</p>, host)}</section>;
    }

    const firstHost = document.createElement("div");
    const secondHost = document.createElement("div");
    document.body.appendChild(firstHost);
    document.body.appendChild(secondHost);

    const { rerender } = render(<Harness host={firstHost} />);
    expect(firstHost.textContent).toBe("teleport");
    expect(secondHost.textContent).toBe("");

    rerender(<Harness host={secondHost} />);
    expect(firstHost.textContent).toBe("");
    expect(secondHost.textContent).toBe("teleport");

    document.body.removeChild(firstHost);
    document.body.removeChild(secondHost);
  });

  test("clicking portal children bubbles through the React tree", () => {
    function Harness({ host }: { host: HTMLElement }): JSX.Element {
      const [count, setCount] = useState(0);
      return (
        <div onClick={() => setCount((value) => value + 1)}>
          <p>{`count:${count}`}</p>
          {createPortal(
            <button type="button">Portal Button</button>,
            host
          )}
        </div>
      );
    }

    const host = document.createElement("div");
    document.body.appendChild(host);

    const { getByText } = render(<Harness host={host} />);
    fireEvent.click(getByText("Portal Button"));

    expect(getByText("count:1")).toBeDefined();

    document.body.removeChild(host);
  });
});

describe("react experiments: composition and ime", () => {
  test("window exposes CompositionEvent constructor", () => {
    expect(typeof (window as unknown as { CompositionEvent?: unknown }).CompositionEvent).toBe("function");
  });

  test("composition handlers receive expected data payloads", () => {
    function Harness(): JSX.Element {
      const [log, setLog] = useState<string[]>([]);

      return (
        <section>
          <input
            aria-label="ime-input"
            onCompositionStart={(event) => {
              setLog((entries) => [...entries, `start:${event.data ?? ""}`]);
            }}
            onCompositionUpdate={(event) => {
              setLog((entries) => [...entries, `update:${event.data ?? ""}`]);
            }}
            onCompositionEnd={(event) => {
              setLog((entries) => [...entries, `end:${event.data ?? ""}`]);
            }}
          />
          <output>{log.join("|")}</output>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const input = getByLabelText("ime-input") as HTMLInputElement;

    fireEvent.compositionStart(input, { data: "" });
    fireEvent.compositionUpdate(input, { data: "に" });
    fireEvent.compositionEnd(input, { data: "に" });

    expect(getByText("start:|update:に|end:に")).toBeDefined();
  });
});

describe("react experiments: async update ordering", () => {
  test("promise-microtask updates preserve update order", async () => {
    function Harness(): JSX.Element {
      const [status, setStatus] = useState("idle");

      return (
        <section>
          <button
            onClick={() => {
              setStatus("sync");
              queueMicrotask(() => {
                setStatus((value) => `${value}|micro`);
              });
              setTimeout(() => {
                setStatus((value) => `${value}|macro`);
              }, 0);
            }}
          >
            Start
          </button>
          <p>{status}</p>
        </section>
      );
    }

    const { getByText } = render(<Harness />);
    fireEvent.click(getByText("Start"));

    await waitFor(() => {
      expect(getByText("sync|micro|macro")).toBeDefined();
    });
  });

  test("functional setState in separate microtasks accumulates correctly", async () => {
    function Harness(): JSX.Element {
      const [count, setCount] = useState(0);

      return (
        <section>
          <button
            onClick={() => {
              queueMicrotask(() => setCount((value) => value + 1));
              queueMicrotask(() => setCount((value) => value + 1));
            }}
          >
            Tick
          </button>
          <p>{`count:${count}`}</p>
        </section>
      );
    }

    const { getByText } = render(<Harness />);
    fireEvent.click(getByText("Tick"));

    await waitFor(() => {
      expect(getByText("count:2")).toBeDefined();
    });
  });
});

describe("react experiments: contenteditable", () => {
  test("jsdom parity: contentEditable accessors are currently unset", () => {
    function Harness({ editable }: { editable: boolean }): JSX.Element {
      return (
        <div
          data-testid="editable"
          contentEditable={editable}
          suppressContentEditableWarning
        >
          draft
        </div>
      );
    }

    const { getByTestId, rerender } = render(<Harness editable />);
    const target = getByTestId("editable") as HTMLDivElement;

    expect((target as unknown as { contentEditable?: unknown }).contentEditable).toBeUndefined();
    expect((target as unknown as { isContentEditable?: unknown }).isContentEditable).toBeUndefined();

    rerender(<Harness editable={false} />);

    expect((target as unknown as { contentEditable?: unknown }).contentEditable).toBeUndefined();
    expect((target as unknown as { isContentEditable?: unknown }).isContentEditable).toBeUndefined();
  });
});

describe("react experiments: focus transitions", () => {
  test("jsdom parity: switching focus does not trigger blur handlers in this harness", () => {
    function Harness(): JSX.Element {
      const [blurCount, setBlurCount] = useState(0);

      return (
        <section>
          <input aria-label="first" onBlur={() => setBlurCount((value) => value + 1)} />
          <input aria-label="second" />
          <output>{`blur:${blurCount}`}</output>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<Harness />);
    const first = getByLabelText("first") as HTMLInputElement;
    const second = getByLabelText("second") as HTMLInputElement;

    first.focus();
    second.focus();

    expect(document.activeElement).toBe(second);
    expect(getByText("blur:0")).toBeDefined();
  });
});

describe("react experiments: selection", () => {
  test("selection toString returns selected text after selectNodeContents", () => {
    function Harness(): JSX.Element {
      return <div data-testid="selection-target">hello world</div>;
    }

    const { getByTestId } = render(<Harness />);
    const target = getByTestId("selection-target");

    const range = document.createRange();
    range.selectNodeContents(target);

    const selection = document.getSelection();
    selection?.removeAllRanges();
    selection?.addRange(range);

    expect(selection?.rangeCount).toBe(1);
    expect(selection?.toString()).toBe("hello world");
  });

  test("selection toString handles ranges across sibling text nodes", () => {
    function Harness(): JSX.Element {
      return (
        <div data-testid="selection-target">
          <span>hello </span>
          <span>world</span>
        </div>
      );
    }

    const { getByTestId } = render(<Harness />);
    const target = getByTestId("selection-target");
    const firstText = target.firstChild?.firstChild as Text;
    const secondText = target.lastChild?.firstChild as Text;

    const range = document.createRange();
    range.setStart(firstText, 2);
    range.setEnd(secondText, 3);

    const selection = document.getSelection();
    selection?.removeAllRanges();
    selection?.addRange(range);

    expect(selection?.toString()).toBe("llo wor");
  });
});

import { fireEvent, render } from "@testing-library/react";
import { describe, expect, test } from "bun:test";
import { useRef, useState } from "react";

describe("react refs and dom interop", () => {
  test("refs can drive focus and observe activeElement", () => {
    function FocusHarness(): JSX.Element {
      const inputRef = useRef<HTMLInputElement | null>(null);
      const [activeTagName, setActiveTagName] = useState("none");

      return (
        <section>
          <input aria-label="focus-target" ref={inputRef} />
          <button
            onClick={() => {
              inputRef.current?.focus();
              setActiveTagName(document.activeElement?.tagName ?? "none");
            }}
          >
            Focus Input
          </button>
          <p>{activeTagName}</p>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<FocusHarness />);
    const input = getByLabelText("focus-target") as HTMLInputElement;

    fireEvent.click(getByText("Focus Input"));

    expect(document.activeElement).toBe(input);
    expect(getByText("INPUT")).toBeDefined();
  });

  test("dangerouslySetInnerHTML updates when props change", () => {
    function HtmlHarness({ html }: { html: string }): JSX.Element {
      return <div data-testid="html-root" dangerouslySetInnerHTML={{ __html: html }} />;
    }

    const { getByTestId, rerender } = render(<HtmlHarness html="<span>One</span>" />);
    const root = getByTestId("html-root");

    expect(root.innerHTML).toBe("<span>One</span>");

    rerender(<HtmlHarness html="<strong>Two</strong>" />);

    expect(root.innerHTML).toBe("<strong>Two</strong>");
  });

  test("className and style props remain reflected through updates", () => {
    function StyledHarness({ active }: { active: boolean }): JSX.Element {
      return (
        <div
          data-testid="styled"
          className={active ? "card card-active" : "card"}
          style={{ marginTop: active ? "8px" : "0px" }}
        >
          content
        </div>
      );
    }

    const { getByTestId, rerender } = render(<StyledHarness active={false} />);
    const element = getByTestId("styled") as HTMLDivElement;

    expect(element.className).toBe("card");
    expect(element.style.marginTop).toBe("0px");

    rerender(<StyledHarness active />);

    expect(element.className).toBe("card card-active");
    expect(element.style.marginTop).toBe("8px");
  });
});
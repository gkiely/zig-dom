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

  test("multiple select keeps existing selections when selecting additional options via refs", () => {
    function MultiSelectHarness(): JSX.Element {
      const optionARef = useRef<HTMLOptionElement | null>(null);
      const optionBRef = useRef<HTMLOptionElement | null>(null);

      return (
        <section>
          <select aria-label="letters" multiple>
            <option ref={optionARef} value="a">
              A
            </option>
            <option ref={optionBRef} value="b">
              B
            </option>
          </select>
          <button
            type="button"
            onClick={() => {
              if (optionARef.current) {
                optionARef.current.selected = true;
              }
              if (optionBRef.current) {
                optionBRef.current.selected = true;
              }
            }}
          >
            Select Both
          </button>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<MultiSelectHarness />);
    const select = getByLabelText("letters") as HTMLSelectElement;

    fireEvent.click(getByText("Select Both"));

    const selectedValues = [...select.options]
      .filter((option) => option.selected)
      .map((option) => option.value)
      .sort();

    expect(selectedValues).toEqual(["a", "b"]);
  });

  test("imperative select value assignment to missing option clears value", () => {
    function SelectValueHarness(): JSX.Element {
      const selectRef = useRef<HTMLSelectElement | null>(null);

      return (
        <section>
          <select ref={selectRef} aria-label="single-select" defaultValue="a">
            <option value="a">A</option>
            <option value="b">B</option>
          </select>
          <button
            type="button"
            onClick={() => {
              if (selectRef.current) {
                selectRef.current.value = "missing";
              }
            }}
          >
            Select missing
          </button>
        </section>
      );
    }

    const { getByLabelText, getByText } = render(<SelectValueHarness />);
    const select = getByLabelText("single-select") as HTMLSelectElement;

    expect(select.value).toBe("a");

    fireEvent.click(getByText("Select missing"));

    expect(select.value).toBe("");
  });

  test("title prop reflects to HTMLElement.title and clears on rerender", () => {
    function TitleHarness({ withTitle }: { withTitle: boolean }): JSX.Element {
      return <div data-testid="title-target" title={withTitle ? "Tooltip" : undefined}>content</div>;
    }

    const { getByTestId, rerender } = render(<TitleHarness withTitle />);
    const target = getByTestId("title-target") as HTMLDivElement;

    expect(target.title).toBe("Tooltip");

    rerender(<TitleHarness withTitle={false} />);

    expect(target.title).toBe("");
  });
});
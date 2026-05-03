import { describe, expect, test } from "bun:test";

describe("node core APIs", () => {
  test("compareDocumentPosition and getRootNode return stable relationships", () => {
    const host = document.createElement("div");
    const first = document.createElement("span");
    const second = document.createElement("span");
    document.body.appendChild(host);
    host.appendChild(first);
    host.appendChild(second);

    expect(first.getRootNode()).toBe(document);

    const siblingRelation = first.compareDocumentPosition(second);
    expect((siblingRelation & Node.DOCUMENT_POSITION_FOLLOWING) !== 0).toBe(true);

    const containsRelation = host.compareDocumentPosition(first);
    expect((containsRelation & Node.DOCUMENT_POSITION_CONTAINS) !== 0).toBe(true);
    expect((containsRelation & Node.DOCUMENT_POSITION_PRECEDING) !== 0).toBe(true);
  });

  test("cloneNode and isEqualNode preserve structure", () => {
    const card = document.createElement("article");
    card.setAttribute("data-kind", "card");
    card.innerHTML = "<h2>Title</h2><p>Body</p>";

    const deepClone = card.cloneNode(true) as HTMLElement;
    const shallowClone = card.cloneNode(false) as HTMLElement;

    expect(deepClone.isEqualNode(card)).toBeTrue();
    expect(deepClone.childNodes.length).toBe(2);
    expect(shallowClone.childNodes.length).toBe(0);
  });

  test("normalize merges adjacent text nodes and removes empty text", () => {
    const root = document.createElement("div");
    root.appendChild(document.createTextNode("Hello"));
    root.appendChild(document.createTextNode(" "));
    root.appendChild(document.createTextNode("World"));
    root.appendChild(document.createTextNode(""));

    root.normalize();

    expect(root.childNodes.length).toBe(1);
    expect(root.firstChild?.textContent?.includes("Hello World")).toBe(true);
  });

  test("dataset and style stay reflected with attributes", () => {
    const element = document.createElement("div") as HTMLElement;

    element.dataset.userId = "42";
    expect(element.getAttribute("data-user-id")).toBe("42");

    element.setAttribute("data-display-name", "Ada");
    expect(element.dataset.displayName).toBe("Ada");

    delete element.dataset.userId;
    expect(element.getAttribute("data-user-id")).toBeNull();

    element.style.setProperty("color", "red");
    expect(element.getAttribute("style")).toContain("color: red;");

    element.setAttribute("style", "margin: 2px;");
    expect(element.style.getPropertyValue("margin")).toBe("2px");
  });

  test("input and keyboard events expose expected init fields", () => {
    const input = document.createElement("input") as HTMLInputElement;
    let inputHandled = false;
    input.oninput = (event: Event) => {
      inputHandled = event.type === "input";
    };

    const inputEvent = new window.InputEvent("input", {
      bubbles: true,
      data: "A",
      inputType: "insertText"
    });
    expect(inputEvent.data).toBe("A");
    expect(inputEvent.inputType).toBe("insertText");

    input.dispatchEvent(inputEvent);
    expect(inputHandled).toBe(true);

    const keyboardEvent = new window.KeyboardEvent("keydown", {
      bubbles: true,
      key: "Enter",
      code: "Enter",
      ctrlKey: true
    });
    expect(keyboardEvent.key).toBe("Enter");
    expect(keyboardEvent.ctrlKey).toBe(true);
  });

  test("focus and blur update activeElement", () => {
    const input = document.createElement("input") as HTMLInputElement;
    document.body.appendChild(input);

    let focused = false;
    let blurred = false;
    input.addEventListener("focus", () => {
      focused = true;
    });
    input.addEventListener("blur", () => {
      blurred = true;
    });

    input.focus();
    expect(document.activeElement).toBe(input);
    expect(focused).toBe(true);

    input.blur();
    expect(document.activeElement).toBe(document.body);
    expect(blurred).toBe(true);
  });
});

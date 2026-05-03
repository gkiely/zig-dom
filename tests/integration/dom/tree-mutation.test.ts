import { describe, expect, test } from "bun:test";
import { Window } from "../../../js/wrappers/Window";

describe("native-backed tree mutation", () => {
  test("append, insert, replace, and remove maintain stable relationships", () => {
    const root = document.createElement("section");
    const first = document.createElement("div");
    const second = document.createElement("div");
    const replacement = document.createElement("article");

    root.appendChild(first);
    root.appendChild(second);
    root.insertBefore(replacement, second);

    expect(root.firstChild).toBe(first);
    expect(first.nextSibling).toBe(replacement);
    expect(replacement.nextSibling).toBe(second);

    root.replaceChild(document.createElement("span"), replacement);
    expect(root.childNodes.length).toBe(3);

    root.removeChild(second);
    expect(root.childNodes.length).toBe(2);
  });

  test("querySelector can find simple selectors", () => {
    const container = document.createElement("div");
    container.innerHTML = '<button class="primary" id="save">Save</button>';
    document.body.appendChild(container);

    const button = document.querySelector("button.primary");
    expect(button?.textContent).toBe("Save");
    expect(document.getElementById("save")).toBe(button);
  });

  test("adoptNode detaches nodes and importNode clones into the target document", () => {
    const externalWindow = new Window();
    const source = externalWindow.document.createElement("article");
    source.setAttribute("data-kind", "source");
    source.appendChild(externalWindow.document.createTextNode("external"));

    const imported = document.importNode(source, true);
    expect(imported).not.toBe(source);
    expect(imported.ownerDocument).toBe(document);
    expect((imported as Element).getAttribute("data-kind")).toBe("source");

    const localNode = document.createElement("section");
    document.body.appendChild(localNode);
    const adopted = document.adoptNode(localNode);
    expect(adopted).toBe(localNode);
    expect(adopted.parentNode).toBeNull();

    externalWindow.close();
  });

  test("cross-window insertion throws DOMException-compatible names", () => {
    const externalWindow = new Window();
    const foreignNode = externalWindow.document.createElement("div");

    let thrown: unknown;
    try {
      document.body.appendChild(foreignNode);
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeDefined();
    expect((thrown as Error).name).toBe("HierarchyRequestError");

    externalWindow.close();
  });
});

import type { Element } from "./Element.ts";
import { parseHtmlInto } from "./html-parser.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { querySelectorAllInSubtree } from "./selector-engine.ts";
import type { Window } from "./Window.ts";

export class DocumentFragment extends Node {
  constructor(window: Window, handle: number, nodeType = Node.DOCUMENT_FRAGMENT_NODE) {
    super(window, handle, nodeType);
  }

  get children(): HTMLCollection {
    return new HTMLCollection(() => this.childNodes.toArray().filter((node) => node.nodeType === Node.ELEMENT_NODE) as Element[]);
  }

  get innerHTML(): string {
    return this.childNodes
      .toArray()
      .map((child) => child.outerHTML)
      .join("");
  }

  set innerHTML(value: string) {
    this.replaceChildren();
    parseHtmlInto(this, value);
  }

  querySelector(selector: string): Element | null {
    if (arguments.length === 0) {
      throw new TypeError("Failed to execute 'querySelector': 1 argument required, but only 0 present.");
    }
    return this.querySelectorAll(String(selector))[0] ?? null;
  }

  querySelectorAll(selector: string): Element[] {
    if (arguments.length === 0) {
      throw new TypeError("Failed to execute 'querySelectorAll': 1 argument required, but only 0 present.");
    }
    const snapshot = querySelectorAllInSubtree(this, String(selector));
    return new NodeList(() => snapshot as unknown as Node[]) as unknown as Element[];
  }

  getElementById(id: string): Element | null {
    const expected = String(id);
    if (expected === "") {
      return null;
    }
    return Array.from(this.querySelectorAll("*") as unknown as Iterable<Element>).find((element) => element.id === expected) ?? null;
  }
}

import type { Element } from "./Element.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import { Node } from "./Node.ts";
import { querySelectorAllInSubtree } from "./selector-engine.ts";
import type { Window } from "./Window.ts";

export class DocumentFragment extends Node {
  constructor(window: Window, handle: number, nodeType = Node.DOCUMENT_FRAGMENT_NODE) {
    super(window, handle, nodeType);
  }

  get children(): HTMLCollection {
    return new HTMLCollection(() => this.childNodes.toArray().filter((node) => node.nodeType === Node.ELEMENT_NODE) as Element[]);
  }

  querySelector(selector: string): Element | null {
    return this.querySelectorAll(selector)[0] ?? null;
  }

  querySelectorAll(selector: string): Element[] {
    return querySelectorAllInSubtree(this, selector);
  }
}

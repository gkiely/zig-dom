import { native } from "../ffi.ts";
import type { Element } from "./Element.ts";
import { parseHtmlInto } from "./html-parser.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { canUseNativeSelector, querySelectorAllInSubtree } from "./selector-engine.ts";
import type { Window } from "./Window.ts";

export class DocumentFragment extends Node {
  constructor(window: Window, handle: number, nodeType = Node.DOCUMENT_FRAGMENT_NODE) {
    super(window, handle, nodeType);
  }

  get children(): HTMLCollection {
    return new HTMLCollection(() => this.childNodes.toArray().filter((node) => node.nodeType === Node.ELEMENT_NODE) as Element[]);
  }

  get firstElementChild(): Element | null {
    return this.children.item(0);
  }

  get lastElementChild(): Element | null {
    const children = this.children;
    if (children.length === 0) {
      return null;
    }
    return children.item(children.length - 1);
  }

  get childElementCount(): number {
    return this.children.length;
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
    const normalizedSelector = String(selector);
    if (canUseNativeSelector(normalizedSelector)) {
      const handle = native.nodeQuerySelector(this._handle, normalizedSelector);
      return this._window.getNode(handle) as Element | null;
    }
    return this.querySelectorAll(normalizedSelector)[0] ?? null;
  }

  querySelectorAll(selector: string): Element[] {
    if (arguments.length === 0) {
      throw new TypeError("Failed to execute 'querySelectorAll': 1 argument required, but only 0 present.");
    }
    const normalizedSelector = String(selector);
    const snapshot = canUseNativeSelector(normalizedSelector)
      ? native.nodeQuerySelectorAll(this._handle, normalizedSelector)
        .map((handle) => this._window.getNode(handle))
        .filter((node): node is Element => Boolean(node && node.nodeType === Node.ELEMENT_NODE))
      : querySelectorAllInSubtree(this, normalizedSelector);
    return new NodeList(() => snapshot as unknown as Node[], { static: true }) as unknown as Element[];
  }

  getElementById(id: string): Element | null {
    const expected = String(id);
    if (expected === "") {
      return null;
    }
    return Array.from(this.querySelectorAll("*") as unknown as Iterable<Element>).find((element) => element.id === expected) ?? null;
  }
}

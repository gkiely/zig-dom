import { native } from "../ffi.ts";
import type { Document } from "./Document.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { parseHtmlInto } from "./html-parser.ts";

type AttributeEntry = { name: string; value: string };
type DatasetShape = Record<string, string>;

function dataAttributeToProperty(name: string): string {
  return name
    .slice(5)
    .replace(/-([a-z])/g, (_match, letter: string) => letter.toUpperCase());
}

function propertyToDataAttribute(name: string): string {
  return `data-${name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}`;
}

class DOMTokenList {
  constructor(private readonly element: Element, private readonly attributeName: string) {}

  #tokens(): string[] {
    const raw = this.element.getAttribute(this.attributeName) ?? "";
    return raw.split(/\s+/).map((token) => token.trim()).filter(Boolean);
  }

  #set(tokens: string[]): void {
    this.element.setAttribute(this.attributeName, tokens.join(" "));
  }

  add(...tokens: string[]): void {
    const next = new Set(this.#tokens());
    for (const token of tokens) next.add(token);
    this.#set([...next]);
  }

  remove(...tokens: string[]): void {
    const toRemove = new Set(tokens);
    this.#set(this.#tokens().filter((token) => !toRemove.has(token)));
  }

  contains(token: string): boolean {
    return this.#tokens().includes(token);
  }

  toggle(token: string, force?: boolean): boolean {
    const has = this.contains(token);
    if (force === true || (!has && force !== false)) {
      this.add(token);
      return true;
    }
    if (has) {
      this.remove(token);
    }
    return false;
  }

  toString(): string {
    return this.#tokens().join(" ");
  }
}

export class Element extends Node {
  #classList: DOMTokenList | null = null;
  #datasetProxy: DatasetShape | null = null;
  #attributeCache: Map<string, string | null> | null = null;

  constructor(window: Node["_window"], handle: number, nodeType = Node.ELEMENT_NODE) {
    super(window, handle, nodeType);
  }

  get classList(): DOMTokenList {
    if (!this.#classList) {
      this.#classList = new DOMTokenList(this, "class");
    }
    return this.#classList;
  }

  get tagName(): string {
    return this.nodeName.toUpperCase();
  }

  get id(): string {
    return this.getAttribute("id") ?? "";
  }

  set id(value: string) {
    this.setAttribute("id", value);
  }

  get className(): string {
    return this.getAttribute("class") ?? "";
  }

  set className(value: string) {
    this.setAttribute("class", value);
  }

  get children(): HTMLCollection {
    return new HTMLCollection(() => this.childNodes.toArray().filter((node) => node.nodeType === Node.ELEMENT_NODE) as Element[]);
  }

  get attributes(): Array<{ name: string; value: string }> {
    const attrs = native.elementAttributes(this._handle) as AttributeEntry[];
    const cache = new Map<string, string | null>();
    for (const attr of attrs) {
      cache.set(attr.name.toLowerCase(), attr.value);
    }
    this.#attributeCache = cache;
    return attrs;
  }

  get dataset(): DatasetShape {
    if (this.#datasetProxy) {
      return this.#datasetProxy;
    }

    this.#datasetProxy = new Proxy({} as DatasetShape, {
      get: (_target, property) => {
        if (typeof property !== "string") {
          return undefined;
        }
        return this.getAttribute(propertyToDataAttribute(property)) ?? undefined;
      },
      set: (_target, property, value) => {
        if (typeof property !== "string") {
          return false;
        }
        this.setAttribute(propertyToDataAttribute(property), String(value));
        return true;
      },
      deleteProperty: (_target, property) => {
        if (typeof property !== "string") {
          return false;
        }
        this.removeAttribute(propertyToDataAttribute(property));
        return true;
      },
      ownKeys: () => {
        return this.attributes
          .filter((attribute) => attribute.name.startsWith("data-"))
          .map((attribute) => dataAttributeToProperty(attribute.name));
      },
      getOwnPropertyDescriptor: (_target, property) => {
        if (typeof property !== "string") {
          return undefined;
        }

        const value = this.getAttribute(propertyToDataAttribute(property));
        if (value == null) {
          return undefined;
        }

        return {
          configurable: true,
          enumerable: true,
          value,
          writable: true
        };
      }
    });

    return this.#datasetProxy;
  }

  get childNodes(): NodeList {
    return super.childNodes;
  }

  get textContent(): string {
    return super.textContent;
  }

  set textContent(value: string | null) {
    super.textContent = value;
  }

  get innerHTML(): string {
    return this.childNodes
      .toArray()
      .map((child) => native.nodeOuterHtml(child._handle))
      .join("");
  }

  set innerHTML(value: string) {
    while (this.firstChild) {
      this.removeChild(this.firstChild);
    }
    parseHtmlInto(this, value);
  }

  get outerHTML(): string {
    return native.nodeOuterHtml(this._handle);
  }

  getAttribute(name: string): string | null {
    const key = name.toLowerCase();
    if (this.#attributeCache?.has(key)) {
      return this.#attributeCache.get(key) ?? null;
    }

    const value = native.getAttribute(this._handle, key);
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, value);
    return value;
  }

  setAttribute(name: string, value: string): void {
    const key = name.toLowerCase();
    const previousValue = this.getAttribute(key);
    native.setAttribute(this._handle, key, value);
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, value);
    this._window.notifyAttributeChanged(this, key, previousValue, value);
  }

  removeAttribute(name: string): void {
    const key = name.toLowerCase();
    const previousValue = this.getAttribute(key);
    native.removeAttribute(this._handle, key);
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, null);
    this._window.notifyAttributeChanged(this, key, previousValue, null);
  }

  hasAttribute(name: string): boolean {
    const key = name.toLowerCase();
    if (this.#attributeCache?.has(key)) {
      return this.#attributeCache.get(key) != null;
    }

    const has = native.hasAttribute(this._handle, key);
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    if (!has) {
      this.#attributeCache.set(key, null);
    }
    return has;
  }

  matches(selector: string): boolean {
    const document = this.ownerDocument as Document;
    return document.querySelectorAll(selector).some((candidate) => candidate === this);
  }

  querySelector(selector: string): Element | null {
    return this.querySelectorAll(selector)[0] ?? null;
  }

  querySelectorAll(selector: string): Element[] {
    const document = this.ownerDocument as Document;
    return document.querySelectorAll(selector).filter((candidate) => this.contains(candidate));
  }
}

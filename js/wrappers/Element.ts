import { native } from "../ffi.ts";
import type { Document } from "./Document.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { parseHtmlInto } from "./html-parser.ts";
import { elementMatchesSelector, querySelectorAllInElement } from "./selector-engine.ts";

type AttributeEntry = { name: string; value: string };
type DatasetShape = Record<string, string>;

const XMLNS_NAMESPACE = "http://www.w3.org/2000/xmlns/";
const XLINK_NAMESPACE = "http://www.w3.org/1999/xlink";

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
  #attributeNamespaces: Map<string, string | null> = new Map();
  #nonHtmlAttributes: Map<string, string> = new Map();

  constructor(window: Node["_window"], handle: number, nodeType = Node.ELEMENT_NODE) {
    super(window, handle, nodeType);
  }

  #attributeKey(name: string): string {
    if (this.#isHtmlElement()) {
      return name.toLowerCase();
    }
    return name;
  }

  #isHtmlElement(): boolean {
    return this.namespaceURI === "http://www.w3.org/1999/xhtml";
  }

  get classList(): DOMTokenList {
    if (!this.#classList) {
      this.#classList = new DOMTokenList(this, "class");
    }
    return this.#classList;
  }

  get tagName(): string {
    const localName = this.localName;
    const qualifiedName = this.prefix ? `${this.prefix}:${localName}` : localName;
    if (this.namespaceURI === "http://www.w3.org/1999/xhtml") {
      return qualifiedName.toUpperCase();
    }
    return qualifiedName;
  }

  override get nodeName(): string {
    return this.tagName;
  }

  get namespaceURI(): string | null {
    const value = (this as unknown as { __namespaceURI?: string | null }).__namespaceURI;
    return value ?? "http://www.w3.org/1999/xhtml";
  }

  get prefix(): string | null {
    return (this as unknown as { __prefix?: string | null }).__prefix ?? null;
  }

  get localName(): string {
    return (this as unknown as { __localName?: string }).__localName ?? native.nodeName(this._handle).toLowerCase();
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

  get attributes(): Array<{ name: string; value: string }> {
    const attrs = this.#isHtmlElement() || this.#nonHtmlAttributes.size === 0
      ? (native.elementAttributes(this._handle) as AttributeEntry[])
      : Array.from(this.#nonHtmlAttributes.entries()).map(([name, value]) => ({ name, value }));
    const ownerDocument = this.ownerDocument;
    const cache = new Map<string, string | null>();
    for (const attr of attrs) {
      cache.set(this.#attributeKey(attr.name), attr.value);
    }
    this.#attributeCache = cache;
    return attrs.map((attr) => ({
      ...attr,
      ownerDocument,
      namespaceURI: this.#attributeNamespaces.get(this.#attributeKey(attr.name)) ?? attributeNamespace(attr.name),
      prefix: attributePrefix(attr.name),
      localName: attributeLocalName(attr.name)
    }));
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
    const key = this.#attributeKey(name);
    if (!this.#isHtmlElement()) {
      if (this.#nonHtmlAttributes.has(key)) {
        return this.#nonHtmlAttributes.get(key) ?? null;
      }
      if (this.#nonHtmlAttributes.size > 0) {
        return null;
      }
    }

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

  getAttributeNode(name: string): Attr | null {
    const value = this.getAttribute(name);
    if (value == null) {
      return null;
    }

    return {
      name,
      value,
      ownerElement: this,
      ownerDocument: this.ownerDocument,
      namespaceURI: this.#attributeNamespaces.get(this.#attributeKey(name)) ?? null
    } as unknown as Attr;
  }

  setAttributeNode(attribute: Attr): Attr | null {
    const previous = this.getAttributeNode(attribute.name);
    this.setAttribute(attribute.name, attribute.value ?? "");

    const mutableAttribute = attribute as unknown as { ownerElement?: Element | null };
    mutableAttribute.ownerElement = this;

    return previous;
  }

  setAttributeNodeNS(attribute: Attr): Attr | null {
    return this.setAttributeNode(attribute);
  }

  setAttribute(name: string, value: string): void {
    const key = this.#attributeKey(name);
    const previousValue = this.getAttribute(key);
    native.setAttribute(this._handle, key, value);
    if (!this.#isHtmlElement()) {
      this.#nonHtmlAttributes.set(key, value);
    }
    if (!this.#attributeNamespaces.has(key)) {
      this.#attributeNamespaces.set(key, attributeNamespace(name));
    }
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, value);
    this._window.notifyAttributeChanged(this, key, previousValue, value);
  }

  setAttributeNS(namespace: string | null, qualifiedName: string, value: string): void {
    const key = this.#attributeKey(qualifiedName);
    const previousValue = this.getAttribute(key);
    native.setAttribute(this._handle, key, value);
    if (!this.#isHtmlElement()) {
      this.#nonHtmlAttributes.set(key, value);
    }
    this.#attributeNamespaces.set(key, namespace);
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, value);
    this._window.notifyAttributeChanged(this, key, previousValue, value);
  }

  removeAttribute(name: string): void {
    const key = this.#attributeKey(name);
    const previousValue = this.getAttribute(key);
    native.removeAttribute(this._handle, key);
    if (!this.#isHtmlElement()) {
      this.#nonHtmlAttributes.delete(key);
    }
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, null);
    this.#attributeNamespaces.delete(key);
    this._window.notifyAttributeChanged(this, key, previousValue, null);
  }

  removeAttributeNS(_namespace: string | null, localName: string): void {
    this.removeAttribute(localName);
  }

  hasAttribute(name: string): boolean {
    const key = this.#attributeKey(name);
    if (!this.#isHtmlElement()) {
      if (this.#nonHtmlAttributes.has(key)) {
        return true;
      }
      if (this.#nonHtmlAttributes.size > 0) {
        return false;
      }
    }

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

  getAttributeNS(_namespace: string | null, localName: string): string | null {
    return this.getAttribute(localName);
  }

  hasAttributeNS(_namespace: string | null, localName: string): boolean {
    return this.hasAttribute(localName);
  }

  matches(selector: string): boolean {
    return elementMatchesSelector(this, selector);
  }

  querySelector(selector: string): Element | null {
    return this.querySelectorAll(selector)[0] ?? null;
  }

  querySelectorAll(selector: string): Element[] {
    const snapshot = querySelectorAllInElement(this, selector);
    return new NodeList(() => snapshot as unknown as Node[]) as unknown as Element[];
  }

  getElementsByTagName(tagName: string): Element[] {
    const selector = tagName === "*" ? "*" : tagName.toLowerCase();
    return this.querySelectorAll(selector);
  }
}

function attributePrefix(name: string): string | null {
  const separator = name.indexOf(":");
  if (separator <= 0) {
    return null;
  }
  return name.slice(0, separator);
}

function attributeLocalName(name: string): string {
  const separator = name.indexOf(":");
  if (separator <= 0) {
    return name;
  }
  return name.slice(separator + 1);
}

function attributeNamespace(name: string): string | null {
  if (name === "xmlns" || name.startsWith("xmlns:")) {
    return XMLNS_NAMESPACE;
  }

  if (name.startsWith("xlink:")) {
    return XLINK_NAMESPACE;
  }

  return null;
}

Object.defineProperty(Element.prototype, Symbol.unscopables, {
  value: {
    before: true,
    after: true,
    replaceWith: true,
    remove: true,
    prepend: true,
    append: true
  },
  configurable: true,
  writable: true
});

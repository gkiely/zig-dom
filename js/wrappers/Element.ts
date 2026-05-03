import { native } from "../ffi.ts";
import type { Document } from "./Document.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { parseHtmlInto } from "./html-parser.ts";
import { elementMatchesSelector, querySelectorAllInElement } from "./selector-engine.ts";

type AttributeEntry = { name: string; value: string };
type AttributeMetadata = { namespaceURI: string | null; prefix: string | null; localName: string };
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

function asciiLowercase(value: string): string {
  return value.replace(/[A-Z]/g, (letter) => letter.toLowerCase());
}

class DOMTokenList {
  constructor(private readonly element: Element, private readonly attributeName: string) {}

  get length(): number {
    return this.#tokens().length;
  }

  #tokens(): string[] {
    const raw = this.element.getAttribute(this.attributeName) ?? "";
    return Array.from(new Set(raw.split(/\s+/).map((token) => token.trim()).filter(Boolean)));
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

  item(index: number): string | null {
    return this.#tokens()[index] ?? null;
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
    return this.element.getAttribute(this.attributeName) ?? "";
  }

  values(): ArrayIterator<string> {
    return this.#tokens().values();
  }

  keys(): ArrayIterator<number> {
    return this.#tokens().keys();
  }

  entries(): ArrayIterator<[number, string]> {
    return this.#tokens().entries();
  }

  forEach(callback: (value: string, key: number, parent: DOMTokenList) => void, thisArg?: unknown): void {
    this.#tokens().forEach((value, key) => callback.call(thisArg, value, key, this));
  }

  [Symbol.iterator](): ArrayIterator<string> {
    return this.values();
  }

  get [Symbol.toStringTag](): string {
    return "DOMTokenList";
  }

  get value(): string {
    return this.element.getAttribute(this.attributeName) ?? "";
  }

  set value(value: string) {
    this.element.setAttribute(this.attributeName, String(value));
  }
}

export class Element extends Node {
  #classList: DOMTokenList | null = null;
  #datasetProxy: DatasetShape | null = null;
  #attributeCache: Map<string, string | null> | null = null;
  #attributeNamespaces: Map<string, string | null> = new Map();
  #attributeMetadata: Map<string, AttributeMetadata> = new Map();
  #nonHtmlAttributes: Map<string, string> = new Map();

  constructor(window: Node["_window"], handle: number, nodeType = Node.ELEMENT_NODE) {
    super(window, handle, nodeType);
  }

  #attributeKey(name: string): string {
    if (this.#isHtmlElement()) {
      return asciiLowercase(name);
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

  get relList(): DOMTokenList | undefined {
    const isSupportedHtml = this.namespaceURI === "http://www.w3.org/1999/xhtml" && ["a", "area", "link"].includes(this.localName);
    const isSupportedSvg = this.namespaceURI === "http://www.w3.org/2000/svg" && this.localName === "a";
    return isSupportedHtml || isSupportedSvg ? new DOMTokenList(this, "rel") : undefined;
  }

  get htmlFor(): DOMTokenList | undefined {
    return this.namespaceURI === "http://www.w3.org/1999/xhtml" && this.localName === "output"
      ? new DOMTokenList(this, "for")
      : undefined;
  }

  get sandbox(): DOMTokenList | undefined {
    return this.namespaceURI === "http://www.w3.org/1999/xhtml" && this.localName === "iframe"
      ? new DOMTokenList(this, "sandbox")
      : undefined;
  }

  get sizes(): DOMTokenList | undefined {
    return this.namespaceURI === "http://www.w3.org/1999/xhtml" && this.localName === "link"
      ? new DOMTokenList(this, "sizes")
      : undefined;
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
    const nativeAttrs = native.elementAttributes(this._handle) as AttributeEntry[];
    const attrs = [...nativeAttrs];
    for (const [name, value] of this.#nonHtmlAttributes) {
      const existingIndex = attrs.findIndex((attribute) => this.#attributeKey(attribute.name) === this.#attributeKey(name));
      if (existingIndex === -1) {
        attrs.push({ name, value });
      } else {
        attrs[existingIndex] = { name, value };
      }
    }
    const ownerDocument = this.ownerDocument;
    const cache = new Map<string, string | null>();
    for (const attr of attrs) {
      cache.set(this.#attributeKey(attr.name), attr.value);
    }
    this.#attributeCache = cache;
    const collection = attrs.map((attr) => {
      const metadata = this.#attributeMetadata.get(attr.name);
      const name = this.#isHtmlElement() && !this.#nonHtmlAttributes.has(attr.name) && !metadata
        ? attr.name.toLowerCase()
        : attr.name;
      return {
      ...attr,
      name,
      ownerDocument,
      namespaceURI: metadata?.namespaceURI ?? this.#attributeNamespaces.get(this.#attributeKey(attr.name)) ?? attributeNamespace(attr.name),
      prefix: metadata?.prefix ?? attributePrefix(name),
      localName: metadata?.localName ?? attributeLocalName(name)
    };
    });
    const collectionItems = Array.from(collection);
    const named = collection as unknown as Array<{ name: string; value: string }> & Record<string, unknown>;
    const namedNodeMapCtor = (this._window as unknown as { NamedNodeMap?: { prototype: Record<string, unknown> } }).NamedNodeMap;
    const namedNodeMapPrototype = namedNodeMapCtor?.prototype;
    if (namedNodeMapPrototype) {
      const definePrototypeMethod = (name: string, value: Function) => {
        if (!(name in namedNodeMapPrototype)) {
          Object.defineProperty(namedNodeMapPrototype, name, {
            value,
            configurable: true,
            writable: true
          });
        }
      };
      definePrototypeMethod("item", function(this: Array<{ name: string; value: string }>, index: number) {
        return this[index] ?? null;
      });
      definePrototypeMethod("getNamedItem", function(this: Record<string, unknown>, name: string) {
        return (this.__owner as Element).getAttributeNode(name);
      });
      definePrototypeMethod("getNamedItemNS", function(this: Record<string, unknown>, namespace: string | null, localName: string) {
        return (this.__owner as Element).getAttributeNodeNS(namespace, localName);
      });
      definePrototypeMethod("setNamedItem", function(this: Array<{ name: string; value: string }> & Record<string, unknown>, attribute: Attr) {
        const previous = (this.__owner as Element).setAttributeNode(attribute);
        if (!(attribute.name in this)) {
          this[attribute.name] = attribute;
          Array.prototype.push.call(this, attribute as unknown as { name: string; value: string });
        }
        return previous;
      });
      definePrototypeMethod("setNamedItemNS", function(this: Array<{ name: string; value: string }> & Record<string, unknown>, attribute: Attr) {
        const previous = (this.__owner as Element).setAttributeNodeNS(attribute);
        if (!(attribute.name in this)) {
          this[attribute.name] = attribute;
          Array.prototype.push.call(this, attribute as unknown as { name: string; value: string });
        }
        return previous;
      });
      definePrototypeMethod("removeNamedItem", function(this: Array<{ name: string; value: string }> & Record<string, unknown>, name: string) {
        const owner = this.__owner as Element;
        const attr = (this[name] as Attr | undefined) ?? owner.getAttributeNode(name);
        if (!attr) {
          throw new DOMException("The node was not found.", "NotFoundError");
        }
        owner.removeAttribute(name);
        delete this[name];
        const index = Array.prototype.findIndex.call(this, (candidate: { name: string }) => candidate.name === name);
        if (index >= 0) {
          Array.prototype.splice.call(this, index, 1);
        }
        return attr;
      });
      definePrototypeMethod("removeNamedItemNS", function(this: Array<{ name: string; value: string }> & Record<string, unknown>, namespace: string | null, localName: string) {
        const owner = this.__owner as Element;
        const attr = owner.getAttributeNodeNS(namespace, localName);
        if (!attr) {
          throw new DOMException("The node was not found.", "NotFoundError");
        }
        owner.removeAttributeNS(namespace, localName);
        delete this[attr.name];
        return attr;
      });
      Object.setPrototypeOf(named, namedNodeMapPrototype);
    }
    Object.defineProperty(named, "__owner", {
      value: this,
      configurable: true
    });
    for (const attr of collectionItems) {
      if (!(attr.name in named)) {
        named[attr.name] = attr;
      }
    }
    return collection;
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
    if (this.#nonHtmlAttributes.has(name)) {
      return this.#nonHtmlAttributes.get(name) ?? null;
    }
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

    const key = this.#attributeKey(name);
    const metadata = this.#attributeMetadata.get(name) ?? this.#attributeMetadata.get(key);
    const reflectedName = this.#nonHtmlAttributes.has(name) ? name : key;
    return {
      name: reflectedName,
      value,
      ownerElement: this,
      ownerDocument: this.ownerDocument,
      namespaceURI: metadata?.namespaceURI ?? this.#attributeNamespaces.get(key) ?? null,
      prefix: metadata?.prefix ?? null,
      localName: metadata?.localName ?? reflectedName
    } as unknown as Attr;
  }

  getAttributeNodeNS(namespace: string | null, localName: string): Attr | null {
    for (const [name, metadata] of this.#attributeMetadata) {
      if (metadata.namespaceURI === namespace && metadata.localName === localName) {
        return this.getAttributeNode(name);
      }
    }
    return namespace == null ? this.getAttributeNode(localName) : null;
  }

  setAttributeNode(attribute: Attr): Attr | null {
    const previous = this.getAttributeNode(attribute.name);
    this.setAttribute(attribute.name, attribute.value ?? "");

    const mutableAttribute = attribute as unknown as { ownerElement?: Element | null };
    mutableAttribute.ownerElement = this;

    return previous;
  }

  setAttributeNodeNS(attribute: Attr): Attr | null {
    const namespace = attribute.namespaceURI ?? null;
    const qualifiedName = attribute.name;
    const previous = this.getAttributeNodeNS(namespace, attribute.localName ?? attribute.name);
    this.setAttributeNS(namespace, qualifiedName, attribute.value ?? "");

    const mutableAttribute = attribute as unknown as { ownerElement?: Element | null };
    mutableAttribute.ownerElement = this;

    return previous;
  }

  setAttribute(name: string, value: string): void {
    const key = this.#attributeKey(name);
    const previousValue = this.getAttribute(key);
    native.setAttribute(this._handle, key, value);
    if (!this.#isHtmlElement()) {
      this.#nonHtmlAttributes.set(key, value);
    } else if (key !== name.toLowerCase()) {
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
    const key = qualifiedName;
    const previousValue = this.getAttributeNS(namespace, attributeLocalName(qualifiedName));
    native.setAttribute(this._handle, key, value);
    this.#nonHtmlAttributes.set(key, value);
    this.#attributeNamespaces.set(key, namespace);
    this.#attributeMetadata.set(key, {
      namespaceURI: namespace,
      prefix: attributePrefix(qualifiedName),
      localName: attributeLocalName(qualifiedName)
    });
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
    this.#attributeMetadata.delete(key);
    this.#nonHtmlAttributes.delete(name);
    this._window.notifyAttributeChanged(this, key, previousValue, null);
  }

  removeAttributeNS(namespace: string | null, localName: string): void {
    for (const [name, metadata] of this.#attributeMetadata) {
      if (metadata.namespaceURI === namespace && metadata.localName === localName) {
        this.removeAttribute(name);
        return;
      }
    }
    this.removeAttribute(localName);
  }

  removeAttributeNode(attribute: Attr): Attr {
    const namespace = attribute.namespaceURI ?? null;
    const localName = attribute.localName ?? attribute.name;
    const current = namespace == null ? this.getAttributeNode(attribute.name) : this.getAttributeNodeNS(namespace, localName);
    if (!current) {
      throw new DOMException("The node was not found.", "NotFoundError");
    }
    if (namespace == null) {
      this.removeAttribute(attribute.name);
    } else {
      this.removeAttributeNS(namespace, localName);
    }
    (attribute as unknown as { ownerElement?: Element | null }).ownerElement = null;
    return attribute;
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

  getAttributeNS(namespace: string | null, localName: string): string | null {
    for (const [name, metadata] of this.#attributeMetadata) {
      if (metadata.namespaceURI === namespace && metadata.localName === localName) {
        return this.getAttribute(name);
      }
    }
    return namespace == null ? this.getAttribute(localName) : null;
  }

  hasAttributeNS(namespace: string | null, localName: string): boolean {
    return this.getAttributeNS(namespace, localName) != null;
  }

  toggleAttribute(name: string, force?: boolean): boolean {
    const exists = this.hasAttribute(name);
    if (force === true || (!exists && force !== false)) {
      this.setAttribute(name, "");
      return true;
    }
    if (exists) {
      this.removeAttribute(name);
    }
    return false;
  }

  getAttributeNames(): string[] {
    return this.attributes.map((attribute) => attribute.name);
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

  getElementsByTagName(tagName: string): HTMLCollection {
    const expectedHtmlName = asciiLowercase(tagName);
    return new HTMLCollection(() => Array.from(this.querySelectorAll("*") as unknown as Iterable<Element>).filter((element) => {
      if (tagName === "*") {
        return true;
      }

      const qualifiedName = element.prefix ? `${element.prefix}:${element.localName}` : element.localName;
      if (element.namespaceURI === "http://www.w3.org/1999/xhtml") {
        return qualifiedName === expectedHtmlName;
      }
      return qualifiedName === tagName;
    }));
  }

  getElementsByTagNameNS(namespace: string | null, localName: string): HTMLCollection {
    const expectedLocalName = localName === "*" ? null : localName;
    return new HTMLCollection(() => Array.from(this.querySelectorAll("*") as unknown as Iterable<Element>).filter((element) => {
      const namespaceMatches = namespace === "*" || element.namespaceURI === namespace;
      const localNameMatches = expectedLocalName == null || element.localName === expectedLocalName;
      return namespaceMatches && localNameMatches;
    }));
  }

  getElementsByClassName(classNames: string): HTMLCollection {
    const tokens = classNames.trim().split(/\s+/).filter((token) => token.length > 0);
    if (tokens.length === 0) {
      return new HTMLCollection(() => []);
    }

    return new HTMLCollection(() => Array.from(this.querySelectorAll("*") as unknown as Iterable<Element>).filter((element) => {
      const classes = (element.getAttribute("class") ?? "").split(/\s+/).filter((token) => token.length > 0);
      return tokens.every((token) => classes.includes(token));
    }));
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

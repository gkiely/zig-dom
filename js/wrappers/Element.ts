import { native } from "../ffi.ts";
import type { Document } from "./Document.ts";
import { ZigDOMException } from "./DOMException.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { parseHtmlInto } from "./html-parser.ts";
import { elementMatchesSelector, querySelectorAllInElement } from "./selector-engine.ts";

type AttributeEntry = { name: string; value: string };
type AttributeMetadata = { namespaceURI: string | null; prefix: string | null; localName: string; qualifiedName: string };
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

function splitAsciiWhitespace(value: string): string[] {
  return value.match(/[^\t\n\f\r ]+/g) ?? [];
}

class DOMTokenList {
  constructor(private readonly element: Element, private readonly attributeName: string) {
    return new Proxy(this, {
      get(target, property, receiver) {
        if (typeof property === "string" && /^\d+$/.test(property)) {
          return target.item(Number(property)) ?? undefined;
        }
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
      has(target, property) {
        if (typeof property === "string" && /^\d+$/.test(property)) {
          return Number(property) < target.length;
        }
        return Reflect.has(target, property);
      },
      getOwnPropertyDescriptor(target, property) {
        if (typeof property === "string" && /^\d+$/.test(property)) {
          const value = target.item(Number(property));
          if (value != null) {
            return { configurable: true, enumerable: true, writable: false, value };
          }
        }
        return Reflect.getOwnPropertyDescriptor(target, property);
      }
    });
  }

  get length(): number {
    return this.#tokens().length;
  }

  #tokens(): string[] {
    const raw = this.element.getAttribute(this.attributeName) ?? "";
    if (raw === "\u0000") {
      return [];
    }
    return Array.from(new Set(raw.split(/[\t\n\f\r ]+/).filter(Boolean)));
  }

  #set(tokens: string[], preserveEmptyAttribute = false): void {
    if (tokens.length === 0) {
      if (preserveEmptyAttribute) {
        this.element.setAttribute(this.attributeName, "");
        return;
      }
      this.element.removeAttribute(this.attributeName);
      return;
    }
    this.element.setAttribute(this.attributeName, tokens.join(" "));
  }

  #validate(token: string): string {
    const value = String(token);
    if (value.length === 0) {
      throw new ZigDOMException("The token provided must not be empty.", "SyntaxError", 12);
    }
    if (/[\t\n\f\r ]/.test(value)) {
      throw new ZigDOMException("The token provided contains HTML space characters.", "InvalidCharacterError", 5);
    }
    return value;
  }

  add(...tokens: string[]): void {
    const hadAttribute = this.element.hasAttribute(this.attributeName);
    const next = new Set(this.#tokens());
    for (const rawToken of tokens) {
      const token = this.#validate(rawToken);
      if (!next.has(token)) {
        next.add(token);
      }
    }
    if (tokens.length > 0 || this.element.hasAttribute(this.attributeName)) {
      this.#set([...next], hadAttribute);
    }
  }

  remove(...tokens: string[]): void {
    const hadAttribute = this.element.hasAttribute(this.attributeName);
    const toRemove = new Set(tokens.map((token) => this.#validate(token)));
    const current = this.#tokens();
    const next = current.filter((token) => !toRemove.has(token));
    if (tokens.length > 0 || this.element.hasAttribute(this.attributeName)) {
      this.#set(next, hadAttribute);
    }
  }

  contains(token: string): boolean {
    return this.#tokens().includes(String(token));
  }

  item(index: number): string | null {
    return this.#tokens()[index] ?? null;
  }

  toggle(token: string, force?: boolean): boolean {
    const value = this.#validate(token);
    const has = this.contains(value);
    if (has && force === true) {
      return true;
    }
    if (force === true || (!has && force !== false)) {
      this.add(value);
      return true;
    }
    if (has) {
      this.#set(this.#tokens().filter((current) => current !== value), this.element.hasAttribute(this.attributeName));
    }
    return false;
  }

  replace(token: string, newToken: string): boolean {
    if (String(newToken).length === 0) {
      throw new ZigDOMException("The token provided must not be empty.", "SyntaxError", 12);
    }
    const oldValue = this.#validate(token);
    const newValue = this.#validate(newToken);
    const tokens = this.#tokens();
    const index = tokens.indexOf(oldValue);
    if (index === -1) {
      return false;
    }
    const hadAttribute = this.element.hasAttribute(this.attributeName);
    if (oldValue === newValue) {
      const previousAttributeValue = this.element.getAttribute(this.attributeName);
      this.#set(tokens);
      const nextAttributeValue = this.element.getAttribute(this.attributeName);
      if (previousAttributeValue === nextAttributeValue) {
        this.element._window.notifyAttributeChanged(this.element, this.attributeName, nextAttributeValue, nextAttributeValue, true);
      }
      return true;
    }
    tokens[index] = newValue;
    this.#set(tokens.filter((current, currentIndex) => tokens.indexOf(current) === currentIndex), hadAttribute);
    return true;
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

  supports(): never {
    throw new TypeError("DOMTokenList does not define supported tokens for this attribute.");
  }
}

export class Element extends Node {
  #classList: DOMTokenList | null = null;
  #datasetProxy: DatasetShape | null = null;
  #attributeCache: Map<string, string | null> | null = null;
  #attributeNamespaces: Map<string, string | null> = new Map();
  #attributeMetadata: Map<string, AttributeMetadata> = new Map();
  #nonHtmlAttributes: Map<string, string> = new Map();
  #plainAttributeNames: Set<string> = new Set();
  #attributeSerial = 0;

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

  #attributeDisplayName(internalName: string): string {
    return this.#attributeMetadata.get(internalName)?.qualifiedName ?? internalName;
  }

  #findAttributeByQualifiedName(name: string): string | null {
    const key = this.#attributeKey(name);
    for (const [internalName, metadata] of this.#attributeMetadata) {
      if (this.#attributeKey(metadata.qualifiedName) === key) {
        return internalName;
      }
    }

    if (this.#nonHtmlAttributes.has(key)) {
      return key;
    }

    return null;
  }

  #findAttributeByNamespace(namespace: string | null, localName: string): string | null {
    for (const [internalName, metadata] of this.#attributeMetadata) {
      if (metadata.namespaceURI === namespace && metadata.localName === localName) {
        return internalName;
      }
    }

    return namespace == null ? this.#findAttributeByQualifiedName(localName) : null;
  }

  get classList(): DOMTokenList {
    if (!this.#classList) {
      this.#classList = new DOMTokenList(this, "class");
    }
    return this.#classList;
  }

  set classList(_value: DOMTokenList | string) {
    // The Web IDL attribute is readonly; assignment is ignored in this runtime.
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
    const isXMLNode = (this as unknown as { __isXMLNode?: boolean }).__isXMLNode === true;
    if (this.namespaceURI === "http://www.w3.org/1999/xhtml" && !isXMLNode) {
      return qualifiedName.toUpperCase();
    }
    return qualifiedName;
  }

  get href(): string {
    const raw = this.getAttribute("href");
    if (raw == null) {
      return "";
    }
    try {
      return new URL(raw, this.ownerDocument?.URL ?? this._window.location.href).href;
    } catch {
      return raw;
    }
  }

  set href(value: string) {
    this.setAttribute("href", String(value));
  }

  override get nodeName(): string {
    return this.tagName;
  }

  get namespaceURI(): string | null {
    const metadata = this as unknown as { __namespaceURI?: string | null };
    if ("__namespaceURI" in metadata) {
      return metadata.__namespaceURI ?? null;
    }
    return "http://www.w3.org/1999/xhtml";
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

  get childElementCount(): number {
    return this.children.length;
  }

  get previousElementSibling(): Element | null {
    let sibling = this.previousSibling;
    while (sibling) {
      if (sibling.nodeType === Node.ELEMENT_NODE) {
        return sibling as Element;
      }
      sibling = sibling.previousSibling;
    }
    return null;
  }

  get nextElementSibling(): Element | null {
    let sibling = this.nextSibling;
    while (sibling) {
      if (sibling.nodeType === Node.ELEMENT_NODE) {
        return sibling as Element;
      }
      sibling = sibling.nextSibling;
    }
    return null;
  }

  get attributes(): Array<{ name: string; value: string }> {
    const syntheticNames = new Set([...this.#attributeMetadata.values()].map((metadata) => this.#attributeKey(metadata.qualifiedName)));
    const nativeAttrs = (native.elementAttributes(this._handle) as AttributeEntry[])
      .filter((attribute) => {
        const key = this.#attributeKey(attribute.name);
        return !syntheticNames.has(key) || this.#plainAttributeNames.has(key);
      });
    const attrs = [...nativeAttrs];
    for (const [name, value] of this.#nonHtmlAttributes) {
      const displayName = this.#attributeDisplayName(name);
      const existingIndex = this.#attributeMetadata.has(name)
        ? -1
        : attrs.findIndex((attribute) => this.#attributeKey(attribute.name) === this.#attributeKey(displayName));
      if (existingIndex === -1) {
        attrs.push({ name: displayName, value });
      } else {
        attrs[existingIndex] = { name: displayName, value };
      }
    }
    const ownerDocument = this.ownerDocument;
    const cache = new Map<string, string | null>();
    for (const attr of attrs) {
      cache.set(this.#attributeKey(attr.name), attr.value);
    }
    this.#attributeCache = cache;
    const collection = attrs.map((attr) => {
      const internalName = [...this.#attributeMetadata.entries()].find(([, metadata]) => metadata.qualifiedName === attr.name)?.[0] ?? attr.name;
      const metadata = this.#attributeMetadata.get(internalName);
      const name = this.#isHtmlElement() && !this.#nonHtmlAttributes.has(attr.name) && !metadata
        ? attr.name.toLowerCase()
        : attr.name;
      return {
      ...attr,
      name,
      nodeName: name,
      nodeValue: attr.value,
      textContent: attr.value,
      specified: true,
      ownerElement: this,
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
    if (this.#plainAttributeNames.has(key)) {
      const value = native.getAttribute(this._handle, key);
      if (value != null) {
        return value === "\u0000" ? "" : value;
      }
    }
    const internalName = this.#findAttributeByQualifiedName(name);
    if (internalName && this.#nonHtmlAttributes.has(internalName)) {
      return this.#nonHtmlAttributes.get(internalName) ?? null;
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
    const normalizedValue = value === "\u0000" ? "" : value;
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, normalizedValue);
    return normalizedValue;
  }

  getAttributeNode(name: string): Attr | null {
    const value = this.getAttribute(name);
    if (value == null) {
      return null;
    }

    const key = this.#attributeKey(name);
    const internalName = this.#findAttributeByQualifiedName(name) ?? key;
    const metadata = this.#attributeMetadata.get(internalName) ?? this.#attributeMetadata.get(name) ?? this.#attributeMetadata.get(key);
    const reflectedName = metadata?.qualifiedName ?? (this.#nonHtmlAttributes.has(name) ? name : key);
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
    const internalName = this.#findAttributeByNamespace(namespace, localName);
    if (internalName) {
      return this.getAttributeNode(this.#attributeDisplayName(internalName));
    }
    return null;
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
    const existingInternalName = this.#findAttributeByQualifiedName(key);
    if (existingInternalName && this.#nonHtmlAttributes.has(existingInternalName)) {
      this.#nonHtmlAttributes.set(existingInternalName, value);
      if (!this.#attributeCache) {
        this.#attributeCache = new Map();
      }
      this.#attributeCache.set(key, value);
      this._window.notifyAttributeChanged(this, key, previousValue, value);
      return;
    }
    if (!this.#isHtmlElement()) {
      this.#nonHtmlAttributes.set(key, value);
    } else if (key !== name.toLowerCase()) {
      this.#nonHtmlAttributes.set(key, value);
    }
    if (!this.#attributeNamespaces.has(key)) {
      this.#attributeNamespaces.set(key, attributeNamespace(name));
    }
    this.#plainAttributeNames.add(key);
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, value);
    this._window.notifyAttributeChanged(this, key, previousValue, value);
  }

  setAttributeNS(namespace: string | null, qualifiedName: string, value: string): void {
    const normalizedNamespace = namespace === "" ? null : namespace;
    const localName = attributeLocalName(qualifiedName);
    const previousValue = this.getAttributeNS(normalizedNamespace, localName);
    const existingInternalName = this.#findAttributeByNamespace(normalizedNamespace, localName);
    const key = existingInternalName ?? (this.#nonHtmlAttributes.has(qualifiedName) || native.hasAttribute(this._handle, qualifiedName)
      ? `${qualifiedName}\u0000${++this.#attributeSerial}`
      : qualifiedName);
    if (!this.#plainAttributeNames.has(this.#attributeKey(qualifiedName))) {
      native.setAttribute(this._handle, qualifiedName, value);
    }
    this.#nonHtmlAttributes.set(key, value);
    this.#attributeNamespaces.set(key, normalizedNamespace);
    this.#attributeMetadata.set(key, {
      qualifiedName,
      namespaceURI: normalizedNamespace,
      prefix: attributePrefix(qualifiedName),
      localName
    });
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(qualifiedName, value);
    this._window.notifyAttributeChanged(this, qualifiedName, previousValue, value);
  }

  removeAttribute(name: string): void {
    const key = this.#attributeKey(name);
    const previousValue = this.getAttribute(key);
    const removingPlainAttribute = this.#plainAttributeNames.has(key);
    const internalName = removingPlainAttribute ? key : this.#findAttributeByQualifiedName(key) ?? key;
    const displayName = this.#attributeDisplayName(internalName);
    native.removeAttribute(this._handle, displayName);
    if (!this.#isHtmlElement()) {
      this.#nonHtmlAttributes.delete(key);
    }
    if (!this.#attributeCache) {
      this.#attributeCache = new Map();
    }
    this.#attributeCache.set(key, null);
    if (!removingPlainAttribute) {
      this.#attributeNamespaces.delete(internalName);
      this.#attributeMetadata.delete(internalName);
    }
    this.#nonHtmlAttributes.delete(name);
    this.#nonHtmlAttributes.delete(internalName);
    this.#plainAttributeNames.delete(key);
    this._window.notifyAttributeChanged(this, key, previousValue, null);
  }

  removeAttributeNS(namespace: string | null, localName: string): void {
    const internalName = this.#findAttributeByNamespace(namespace === "" ? null : namespace, localName);
    if (internalName) {
      this.removeAttribute(this.#attributeDisplayName(internalName));
    }
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

  hasAttributes(): boolean {
    return this.attributes.length > 0;
  }

  getAttributeNS(namespace: string | null, localName: string): string | null {
    const normalizedNamespace = namespace === "" ? null : namespace;
    if (normalizedNamespace == null && this.#plainAttributeNames.has(this.#attributeKey(localName))) {
      const attr = this.getAttributeNode(localName);
      if (attr?.localName === localName) {
        return attr.value;
      }
    }
    for (const [name, metadata] of this.#attributeMetadata) {
      if (metadata.namespaceURI === normalizedNamespace && metadata.localName === localName) {
        return this.#nonHtmlAttributes.get(name) ?? null;
      }
    }
    if (normalizedNamespace == null) {
      const attr = this.getAttributeNode(localName);
      return attr && attr.namespaceURI == null && attr.localName === localName ? attr.value : null;
    }
    return null;
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

  webkitMatchesSelector(selector: string): boolean {
    return this.matches(selector);
  }

  closest(selector: string): Element | null {
    let current: Element | null = this;
    while (current) {
      if (elementMatchesSelector(current, selector, this)) {
        return current;
      }
      current = current.parentElement;
    }
    return null;
  }

  querySelector(selector: string): Element | null {
    return this.querySelectorAll(selector)[0] ?? null;
  }

  querySelectorAll(selector: string): Element[] {
    const snapshot = querySelectorAllInElement(this, selector);
    return new NodeList(() => snapshot as unknown as Node[]) as unknown as Element[];
  }

  insertAdjacentElement(position: string, element: Element): Element | null {
    if (!(element instanceof Node) || element.nodeType !== Node.ELEMENT_NODE) {
      throw new TypeError("The provided value is not an Element.");
    }

    const normalized = String(position).toLowerCase();
    switch (normalized) {
      case "beforebegin": {
        const parent = this.parentNode;
        if (!parent) {
          return null;
        }
        parent.insertBefore(element, this);
        return element;
      }
      case "afterbegin":
        this.insertBefore(element, this.firstChild);
        return element;
      case "beforeend":
        this.appendChild(element);
        return element;
      case "afterend": {
        const parent = this.parentNode;
        if (!parent) {
          return null;
        }
        parent.insertBefore(element, this.nextSibling);
        return element;
      }
      default:
        throw new ZigDOMException("The position is not one of the supported values.", "SyntaxError", 12);
    }
  }

  insertAdjacentText(position: string, data: string): null {
    const document = this.ownerDocument ?? this._window.document;
    const text = document.createTextNode(String(data));
    const normalized = String(position).toLowerCase();
    switch (normalized) {
      case "beforebegin": {
        const parent = this.parentNode;
        if (!parent) {
          return null;
        }
        parent.insertBefore(text, this);
        return null;
      }
      case "afterbegin":
        this.insertBefore(text, this.firstChild);
        return null;
      case "beforeend":
        this.appendChild(text);
        return null;
      case "afterend": {
        const parent = this.parentNode;
        if (!parent) {
          return null;
        }
        parent.insertBefore(text, this.nextSibling);
        return null;
      }
      default:
        throw new ZigDOMException("The position is not one of the supported values.", "SyntaxError", 12);
    }
  }

  getElementsByTagName(tagName: string): HTMLCollection {
    const expectedHtmlName = asciiLowercase(tagName);
    return new HTMLCollection(() => collectDescendantElements(this).filter((element) => {
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
    const expectedNamespace = namespace === "" ? null : namespace;
    const expectedLocalName = localName === "*" ? null : localName;
    return new HTMLCollection(() => collectDescendantElements(this).filter((element) => {
      const namespaceMatches = expectedNamespace === "*" || element.namespaceURI === expectedNamespace;
      const localNameMatches = expectedLocalName == null || element.localName === expectedLocalName;
      return namespaceMatches && localNameMatches;
    }));
  }

  getElementsByClassName(classNames: string): HTMLCollection {
    const tokens = splitAsciiWhitespace(String(classNames));
    if (tokens.length === 0) {
      return new HTMLCollection(() => []);
    }

    return new HTMLCollection(() => collectDescendantElements(this).filter((element) => {
      const classes = splitAsciiWhitespace(element.getAttribute("class") ?? "");
      return tokens.every((token) => classes.includes(token));
    }));
  }
}

function collectDescendantElements(root: Element): Element[] {
  const descendants: Element[] = [];
  const visit = (node: Node) => {
    for (const child of node.childNodes.toArray()) {
      if (child.nodeType === Node.ELEMENT_NODE) {
        descendants.push(child as Element);
        visit(child);
      }
    }
  };
  visit(root);
  return descendants;
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

import { native } from "../ffi.js";
import type { Document } from "./Document.js";
import { HTMLCollection } from "./HTMLCollection.js";
import { Node } from "./Node.js";
import { NodeList } from "./NodeList.js";
import { parseHtmlInto } from "./html-parser.js";

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
  readonly classList: DOMTokenList;

  constructor(window: Node["_window"], handle: number) {
    super(window, handle);
    this.classList = new DOMTokenList(this, "class");
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
    const marker = this.ownerDocument?.querySelectorAll("*") ?? [];
    void marker;
    const attrs: Array<{ name: string; value: string }> = [];
    const id = this.getAttribute("id");
    if (id !== null) attrs.push({ name: "id", value: id });
    const className = this.getAttribute("class");
    if (className !== null) attrs.push({ name: "class", value: className });
    return attrs;
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
    return native.getAttribute(this._handle, name);
  }

  setAttribute(name: string, value: string): void {
    native.setAttribute(this._handle, name, value);
  }

  removeAttribute(name: string): void {
    native.removeAttribute(this._handle, name);
  }

  hasAttribute(name: string): boolean {
    return native.hasAttribute(this._handle, name);
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

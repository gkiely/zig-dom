import { native } from "../ffi.ts";
import { Comment } from "./Comment.ts";
import { DocumentFragment } from "./DocumentFragment.ts";
import { Element } from "./Element.ts";
import { Node } from "./Node.ts";
import { Range, Selection } from "./Range.ts";
import { Text } from "./Text.ts";
import type { Window } from "./Window.ts";

export class Document extends Node {
  constructor(window: Window, handle: number, nodeType = Node.DOCUMENT_NODE) {
    super(window, handle, nodeType);
  }

  get defaultView(): Window {
    return this._window;
  }

  get documentElement(): Element {
    this._window.assertOpen();
    const handle = native.windowDocumentElement(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("documentElement not found");
    return node as Element;
  }

  get head(): Element {
    this._window.assertOpen();
    const handle = native.windowHead(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("head not found");
    return node as Element;
  }

  get body(): Element {
    this._window.assertOpen();
    const handle = native.windowBody(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("body not found");
    return node as Element;
  }

  get URL(): string {
    return this._window.location.href;
  }

  get cookie(): string {
    return this._window.getCookieString();
  }

  set cookie(value: string) {
    this._window.setCookie(value);
  }

  get activeElement(): Element {
    return this._window.getActiveElement() ?? this.body;
  }

  getSelection(): Selection {
    return this._window.getSelection();
  }

  createRange(): Range {
    return new Range();
  }

  createElement(tagName: string): Element {
    this._window.assertOpen();
    const normalizedTagName = tagName.toLowerCase();
    const handle = native.createElement(this._handle, normalizedTagName);
    const element = this._window.createKnownNode(handle, Node.ELEMENT_NODE, {
      tagName: normalizedTagName,
      skipInitialStyleSync: true
    }) as Element;
    this._window.upgradeElementInstance(element, normalizedTagName);
    return element;
  }

  createElementNS(_namespace: string | null, qualifiedName: string): Element {
    return this.createElement(qualifiedName);
  }

  createTextNode(data: string): Text {
    this._window.assertOpen();
    const handle = native.createTextNode(this._handle, data);
    return this._window.createKnownNode(handle, Node.TEXT_NODE) as Text;
  }

  createComment(data: string): Comment {
    this._window.assertOpen();
    const handle = native.createComment(this._handle, data);
    return this._window.createKnownNode(handle, Node.COMMENT_NODE) as Comment;
  }

  createDocumentFragment(): DocumentFragment {
    this._window.assertOpen();
    const handle = native.createDocumentFragment(this._handle);
    return this._window.createKnownNode(handle, Node.DOCUMENT_FRAGMENT_NODE) as DocumentFragment;
  }

  getElementById(id: string): Element | null {
    this._window.assertOpen();
    const handle = native.documentGetElementById(this._handle, id);
    return this._window.getNode(handle) as Element | null;
  }

  querySelector(selector: string): Element | null {
    this._window.assertOpen();
    const handle = native.documentQuerySelector(this._handle, selector);
    return this._window.getNode(handle) as Element | null;
  }

  querySelectorAll(selector: string): Element[] {
    this._window.assertOpen();
    return native.documentQuerySelectorAll(this._handle, selector)
      .map((handle) => this._window.getNode(handle))
      .filter((node): node is Element => Boolean(node && node.nodeType === Node.ELEMENT_NODE));
  }

  reset(): void {
    this._window.assertOpen();
    native.documentReset(this._handle);
    this._window.setActiveElement(null);
  }
}

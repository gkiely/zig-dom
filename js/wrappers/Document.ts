import { native } from "../ffi.js";
import { Comment } from "./Comment.js";
import { DocumentFragment } from "./DocumentFragment.js";
import { Element } from "./Element.js";
import { Node } from "./Node.js";
import { Text } from "./Text.js";
import type { Window } from "./Window.js";

export class Document extends Node {
  constructor(window: Window, handle: number) {
    super(window, handle);
  }

  get defaultView(): Window {
    return this._window;
  }

  get documentElement(): Element {
    const handle = native.windowDocumentElement(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("documentElement not found");
    return node as Element;
  }

  get head(): Element {
    const handle = native.windowHead(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("head not found");
    return node as Element;
  }

  get body(): Element {
    const handle = native.windowBody(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("body not found");
    return node as Element;
  }

  get URL(): string {
    return this._window.location.href;
  }

  createElement(tagName: string): Element {
    const handle = native.createElement(this._handle, tagName);
    return this._window.getNode(handle) as Element;
  }

  createElementNS(_namespace: string | null, qualifiedName: string): Element {
    return this.createElement(qualifiedName);
  }

  createTextNode(data: string): Text {
    const handle = native.createTextNode(this._handle, data);
    return this._window.getNode(handle) as Text;
  }

  createComment(data: string): Comment {
    const handle = native.createComment(this._handle, data);
    return this._window.getNode(handle) as Comment;
  }

  createDocumentFragment(): DocumentFragment {
    const handle = native.createDocumentFragment(this._handle);
    return this._window.getNode(handle) as DocumentFragment;
  }

  getElementById(id: string): Element | null {
    const handle = native.documentGetElementById(this._handle, id);
    return this._window.getNode(handle) as Element | null;
  }

  querySelector(selector: string): Element | null {
    const handle = native.documentQuerySelector(this._handle, selector);
    return this._window.getNode(handle) as Element | null;
  }

  querySelectorAll(selector: string): Element[] {
    return native.documentQuerySelectorAll(this._handle, selector)
      .map((handle) => this._window.getNode(handle))
      .filter((node): node is Element => Boolean(node && node.nodeType === Node.ELEMENT_NODE));
  }

  reset(): void {
    native.documentReset(this._handle);
  }
}

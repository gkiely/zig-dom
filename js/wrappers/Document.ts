import { native } from "../ffi.ts";
import { Comment } from "./Comment.ts";
import { DocumentFragment } from "./DocumentFragment.ts";
import { ZigDOMException } from "./DOMException.ts";
import { Element } from "./Element.ts";
import { Node } from "./Node.ts";
import { Range, Selection } from "./Range.ts";
import { canUseNativeSelector, querySelectorAllInDocument } from "./selector-engine.ts";
import { Text } from "./Text.ts";
import type { Window } from "./Window.ts";

export class Document extends Node {
  #documentElementCache: Element | null = null;
  #headCache: Element | null = null;
  #bodyCache: Element | null = null;

  constructor(window: Window, handle: number, nodeType = Node.DOCUMENT_NODE) {
    super(window, handle, nodeType);
  }

  get defaultView(): Window {
    return this._window;
  }

  get documentElement(): Element {
    this._window.assertOpen();
    if (this.#documentElementCache) {
      return this.#documentElementCache;
    }

    const handle = native.windowDocumentElement(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("documentElement not found");
    this.#documentElementCache = node as Element;
    return this.#documentElementCache;
  }

  get head(): Element {
    this._window.assertOpen();
    if (this.#headCache) {
      return this.#headCache;
    }

    const handle = native.windowHead(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("head not found");
    this.#headCache = node as Element;
    return this.#headCache;
  }

  get body(): Element {
    this._window.assertOpen();
    if (this.#bodyCache) {
      return this.#bodyCache;
    }

    const handle = native.windowBody(this._window._nativeWindowHandle);
    const node = this._window.getNode(handle);
    if (!node) throw new Error("body not found");
    this.#bodyCache = node as Element;
    return this.#bodyCache;
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
    if (canUseNativeSelector(selector)) {
      const handle = native.documentQuerySelector(this._handle, selector);
      return this._window.getNode(handle) as Element | null;
    }

    return this.querySelectorAll(selector)[0] ?? null;
  }

  querySelectorAll(selector: string): Element[] {
    this._window.assertOpen();
    if (canUseNativeSelector(selector)) {
      return native.documentQuerySelectorAll(this._handle, selector)
        .map((handle) => this._window.getNode(handle))
        .filter((node): node is Element => Boolean(node && node.nodeType === Node.ELEMENT_NODE));
    }

    return querySelectorAllInDocument(this, selector);
  }

  adoptNode<TNode extends Node>(node: TNode): TNode {
    this._window.assertOpen();

    if (node.nodeType === Node.DOCUMENT_NODE) {
      throw new ZigDOMException("A Document node cannot be adopted.", "NotSupportedError", 9);
    }

    if (node._window !== this._window) {
      throw new ZigDOMException("Cannot adopt nodes across different windows.", "WrongDocumentError", 4);
    }

    if (node.parentNode) {
      node.parentNode.removeChild(node);
    }

    return node;
  }

  importNode<TNode extends Node>(node: TNode, deep = false): TNode {
    this._window.assertOpen();

    if (node.nodeType === Node.DOCUMENT_NODE) {
      throw new ZigDOMException("A Document node cannot be imported.", "NotSupportedError", 9);
    }

    return cloneNodeIntoDocument(this, node, deep) as TNode;
  }

  reset(): void {
    this._window.assertOpen();
    native.documentReset(this._handle);
    this.#documentElementCache = null;
    this.#headCache = null;
    this.#bodyCache = null;
    this._window.setActiveElement(null);
  }
}

function cloneNodeIntoDocument(document: Document, source: Node, deep: boolean): Node {
  if (source.nodeType === Node.TEXT_NODE) {
    return document.createTextNode(source.textContent);
  }

  if (source.nodeType === Node.COMMENT_NODE) {
    return document.createComment(source.textContent);
  }

  if (source.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
    const fragment = document.createDocumentFragment();
    if (deep) {
      for (const child of source.childNodes.toArray()) {
        fragment.appendChild(cloneNodeIntoDocument(document, child, true));
      }
    }
    return fragment;
  }

  if (source.nodeType === Node.ELEMENT_NODE) {
    const sourceElement = source as unknown as Element;
    const clone = document.createElement(sourceElement.tagName.toLowerCase());
    for (const attribute of sourceElement.attributes) {
      clone.setAttribute(attribute.name, attribute.value);
    }

    if (deep) {
      for (const child of source.childNodes.toArray()) {
        clone.appendChild(cloneNodeIntoDocument(document, child, true));
      }
    }

    return clone;
  }

  throw new ZigDOMException(`Unsupported node type for import: ${source.nodeType}`, "NotSupportedError", 9);
}

import { native } from "../ffi.js";
import { Event, EventTargetBase } from "./Event.js";
import { NodeList } from "./NodeList.js";
import type { Document } from "./Document.js";
import type { Window } from "./Window.js";

export class Node extends EventTargetBase {
  static readonly ELEMENT_NODE = 1;
  static readonly TEXT_NODE = 3;
  static readonly COMMENT_NODE = 8;
  static readonly DOCUMENT_NODE = 9;
  static readonly DOCUMENT_FRAGMENT_NODE = 11;

  readonly _window: Window;
  readonly _handle: number;

  constructor(window: Window, handle: number) {
    super();
    this._window = window;
    this._handle = handle;
  }

  get nodeType(): number {
    this._window.assertOpen();
    return native.nodeType(this._handle);
  }

  get nodeName(): string {
    this._window.assertOpen();
    return native.nodeName(this._handle);
  }

  get parentNode(): Node | null {
    this._window.assertOpen();
    return this._window.getNode(native.nodeParent(this._handle));
  }

  get firstChild(): Node | null {
    this._window.assertOpen();
    return this._window.getNode(native.nodeFirstChild(this._handle));
  }

  get lastChild(): Node | null {
    this._window.assertOpen();
    return this._window.getNode(native.nodeLastChild(this._handle));
  }

  get previousSibling(): Node | null {
    this._window.assertOpen();
    return this._window.getNode(native.nodePreviousSibling(this._handle));
  }

  get nextSibling(): Node | null {
    this._window.assertOpen();
    return this._window.getNode(native.nodeNextSibling(this._handle));
  }

  get ownerDocument(): Document | null {
    this._window.assertOpen();
    if (this.nodeType === Node.DOCUMENT_NODE) {
      return null;
    }
    const documentHandle = native.nodeOwnerDocument(this._handle);
    return this._window.getNode(documentHandle) as Document | null;
  }

  get childNodes(): NodeList {
    this._window.assertOpen();
    return new NodeList(() => this._window.collectChildren(this._handle));
  }

  get textContent(): string {
    this._window.assertOpen();
    return native.nodeTextContent(this._handle);
  }

  set textContent(value: string | null) {
    this._window.assertOpen();
    native.setNodeTextContent(this._handle, value ?? "");
  }

  get nodeValue(): string | null {
    const type = this.nodeType;
    if (type === Node.TEXT_NODE || type === Node.COMMENT_NODE) {
      return this.textContent;
    }
    return null;
  }

  set nodeValue(value: string | null) {
    const type = this.nodeType;
    if (type === Node.TEXT_NODE || type === Node.COMMENT_NODE) {
      this.textContent = value ?? "";
    }
  }

  appendChild<TNode extends Node>(child: TNode): TNode {
    this._window.assertOpen();

    if (child.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
      while (child.firstChild) {
        this.appendChild(child.firstChild);
      }
      return child;
    }

    native.appendChild(this._handle, child._handle);
    return child;
  }

  insertBefore<TNode extends Node>(newChild: TNode, referenceChild: Node | null): TNode {
    this._window.assertOpen();

    if (newChild.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
      const children = newChild.childNodes.toArray();
      for (const child of children) {
        this.insertBefore(child, referenceChild);
      }
      return newChild;
    }

    native.insertBefore(this._handle, newChild._handle, referenceChild?._handle ?? 0);
    return newChild;
  }

  removeChild<TNode extends Node>(child: TNode): TNode {
    this._window.assertOpen();
    native.removeChild(this._handle, child._handle);
    return child;
  }

  replaceChild<TNode extends Node>(newChild: Node, oldChild: TNode): TNode {
    this._window.assertOpen();
    native.replaceChild(this._handle, newChild._handle, oldChild._handle);
    return oldChild;
  }

  contains(other: Node | null): boolean {
    if (!other) return false;
    let cursor: Node | null = other;
    while (cursor) {
      if (cursor === this) return true;
      cursor = cursor.parentNode;
    }
    return false;
  }

  dispatchEvent(event: Event): boolean {
    this._window.assertOpen();

    if (!event.target) {
      event.target = this;
    }

    const propagationPath: Node[] = [this];
    let cursor = this.parentNode;
    while (cursor) {
      propagationPath.push(cursor);
      cursor = cursor.parentNode;
    }

    for (let i = propagationPath.length - 1; i >= 1; i -= 1) {
      if (event.propagationStopped) break;
      const current = propagationPath[i];
      event.currentTarget = current;
      event.eventPhase = Event.CAPTURING_PHASE;
      current.invokeListeners(event, true);
    }

    if (!event.propagationStopped) {
      event.currentTarget = this;
      event.eventPhase = Event.AT_TARGET;
      this.invokeListeners(event, true);
      if (!event.immediatePropagationStopped) {
        this.invokeListeners(event, false);
      }
      this.invokePropertyHandler(event);
    }

    if (event.bubbles && !event.propagationStopped) {
      for (let i = 1; i < propagationPath.length; i += 1) {
        if (event.propagationStopped) break;
        const current = propagationPath[i];
        event.currentTarget = current;
        event.eventPhase = Event.BUBBLING_PHASE;
        current.invokeListeners(event, false);
        current.invokePropertyHandler(event);
      }
    }

    event.currentTarget = null;
    event.eventPhase = Event.NONE;
    return !event.defaultPrevented;
  }

  protected invokePropertyHandler(event: Event): void {
    const handlerName = `on${event.type}` as keyof this;
    const handler = this[handlerName] as unknown;
    if (typeof handler === "function") {
      (handler as (this: Node, event: Event) => void).call(this, event);
    }
  }

  get outerHTML(): string {
    return native.nodeOuterHtml(this._handle);
  }
}

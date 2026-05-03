import { native } from "../ffi.js";
import { NativeHandleRegistry } from "../memory.js";
import { Comment } from "./Comment.js";
import { Document } from "./Document.js";
import { DocumentFragment } from "./DocumentFragment.js";
import { Element } from "./Element.js";
import { CustomEvent, Event, MouseEvent } from "./Event.js";
import { HTMLButtonElement, HTMLElement, HTMLFormElement, HTMLIFrameElement, HTMLInputElement } from "./HTMLElement.js";
import { Node } from "./Node.js";
import { Text } from "./Text.js";

export interface WindowOptions {
  url?: string;
  width?: number;
  height?: number;
}

export class Window {
  readonly _nativeWindowHandle: number;
  readonly #documentHandle: number;
  readonly #nodeCache = new Map<number, Node>();
  readonly #handleRegistry = new NativeHandleRegistry(native);

  #closed = false;

  readonly Node = Node;
  readonly Element = Element;
  readonly HTMLElement = HTMLElement;
  readonly HTMLButtonElement = HTMLButtonElement;
  readonly HTMLIFrameElement = HTMLIFrameElement;
  readonly HTMLInputElement = HTMLInputElement;
  readonly HTMLFormElement = HTMLFormElement;
  readonly Text = Text;
  readonly Comment = Comment;
  readonly DocumentFragment = DocumentFragment;
  readonly Event = Event;
  readonly CustomEvent = CustomEvent;
  readonly MouseEvent = MouseEvent;
  readonly Document = Document;

  readonly location: { href: string };
  readonly document: Document;

  readonly happyDOM: {
    reset: () => void;
    close: () => void;
    abort: () => void;
  };

  constructor(options?: WindowOptions) {
    this._nativeWindowHandle = native.createWindow();
    this.#documentHandle = native.windowDocument(this._nativeWindowHandle);

    this.location = {
      href: options?.url ?? "http://localhost/"
    };

    this.document = this.getNode(this.#documentHandle) as Document;

    this.happyDOM = {
      reset: () => {
        this.assertOpen();
        this.document.reset();
      },
      close: () => {
        this.close();
      },
      abort: () => {
        this.close();
      }
    };

    Object.defineProperty(this, "window", { value: this, configurable: true });
    Object.defineProperty(this, "self", { value: this, configurable: true });

    this.setTimeout = globalThis.setTimeout.bind(globalThis);
    this.clearTimeout = globalThis.clearTimeout.bind(globalThis);
    this.setInterval = globalThis.setInterval.bind(globalThis);
    this.clearInterval = globalThis.clearInterval.bind(globalThis);
    this.queueMicrotask = globalThis.queueMicrotask.bind(globalThis);
  }

  assertOpen(): void {
    if (this.#closed) {
      throw new Error("Window is closed");
    }
  }

  get closed(): boolean {
    return this.#closed;
  }

  getNode(handle: number): Node | null {
    if (!handle) return null;
    this.assertOpen();

    const existing = this.#nodeCache.get(handle);
    if (existing) {
      return existing;
    }

    const kind = native.nodeKind(handle);
    let wrapped: Node;
    switch (kind) {
      case Node.DOCUMENT_NODE:
        wrapped = new Document(this, handle);
        break;
      case Node.ELEMENT_NODE: {
        const tagName = native.nodeName(handle).toLowerCase();
        if (tagName === "input") {
          wrapped = new HTMLInputElement(this, handle);
        } else if (tagName === "button") {
          wrapped = new HTMLButtonElement(this, handle);
        } else if (tagName === "form") {
          wrapped = new HTMLFormElement(this, handle);
        } else if (tagName === "iframe") {
          wrapped = new HTMLIFrameElement(this, handle);
        } else {
          wrapped = new HTMLElement(this, handle);
        }
        break;
      }
      case Node.TEXT_NODE:
        wrapped = new Text(this, handle);
        break;
      case Node.COMMENT_NODE:
        wrapped = new Comment(this, handle);
        break;
      case Node.DOCUMENT_FRAGMENT_NODE:
        wrapped = new DocumentFragment(this, handle);
        break;
      default:
        throw new Error(`Unsupported native node kind: ${kind}`);
    }

    native.retainHandle(handle);
    this.#handleRegistry.track(wrapped, handle);
    this.#nodeCache.set(handle, wrapped);
    return wrapped;
  }

  collectChildren(parentHandle: number): Node[] {
    this.assertOpen();

    const result: Node[] = [];
    let cursor = native.nodeFirstChild(parentHandle);
    while (cursor) {
      const node = this.getNode(cursor);
      if (node) {
        result.push(node);
      }
      cursor = native.nodeNextSibling(cursor);
    }
    return result;
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    native.destroyWindow(this._nativeWindowHandle);
    this.#nodeCache.clear();
  }

  setTimeout!: typeof globalThis.setTimeout;
  clearTimeout!: typeof globalThis.clearTimeout;
  setInterval!: typeof globalThis.setInterval;
  clearInterval!: typeof globalThis.clearInterval;
  queueMicrotask!: typeof globalThis.queueMicrotask;
}

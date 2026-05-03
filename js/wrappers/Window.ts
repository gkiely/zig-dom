import { native } from "../ffi.ts";
import { Comment } from "./Comment.ts";
import { CustomElementRegistry } from "./CustomElementRegistry.ts";
import { Document } from "./Document.ts";
import { DocumentFragment } from "./DocumentFragment.ts";
import { Element } from "./Element.ts";
import { CustomEvent, Event, InputEvent, KeyboardEvent, MouseEvent } from "./Event.ts";
import { HTMLButtonElement, HTMLElement, HTMLFormElement, HTMLIFrameElement, HTMLInputElement } from "./HTMLElement.ts";
import { MutationObserver } from "./MutationObserver.ts";
import { Node } from "./Node.ts";
import { Range, Selection } from "./Range.ts";
import { Storage } from "./Storage.ts";
import { Text } from "./Text.ts";

export interface WindowOptions {
  url?: string;
  width?: number;
  height?: number;
}

export interface WindowLocation {
  href: string;
  protocol: string;
  host: string;
  hostname: string;
  port: string;
  pathname: string;
  search: string;
  hash: string;
  readonly origin: string;
  assign(next: string): void;
  replace(next: string): void;
  toString(): string;
}

class WindowLocationImpl implements WindowLocation {
  #url: URL;

  constructor(initialHref: string) {
    this.#url = new URL(initialHref);
  }

  #resolve(next: string): URL {
    return new URL(next, this.#url);
  }

  get href(): string {
    return this.#url.href;
  }

  set href(next: string) {
    this.#url = this.#resolve(next);
  }

  get protocol(): string {
    return this.#url.protocol;
  }

  set protocol(next: string) {
    const updated = new URL(this.#url.href);
    updated.protocol = next;
    this.#url = updated;
  }

  get host(): string {
    return this.#url.host;
  }

  set host(next: string) {
    const updated = new URL(this.#url.href);
    updated.host = next;
    this.#url = updated;
  }

  get hostname(): string {
    return this.#url.hostname;
  }

  set hostname(next: string) {
    const updated = new URL(this.#url.href);
    updated.hostname = next;
    this.#url = updated;
  }

  get port(): string {
    return this.#url.port;
  }

  set port(next: string) {
    const updated = new URL(this.#url.href);
    updated.port = next;
    this.#url = updated;
  }

  get pathname(): string {
    return this.#url.pathname;
  }

  set pathname(next: string) {
    const updated = new URL(this.#url.href);
    updated.pathname = next;
    this.#url = updated;
  }

  get search(): string {
    return this.#url.search;
  }

  set search(next: string) {
    const updated = new URL(this.#url.href);
    updated.search = next;
    this.#url = updated;
  }

  get hash(): string {
    return this.#url.hash;
  }

  set hash(next: string) {
    const updated = new URL(this.#url.href);
    updated.hash = next;
    this.#url = updated;
  }

  get origin(): string {
    return this.#url.origin;
  }

  assign(next: string): void {
    this.href = next;
  }

  replace(next: string): void {
    this.href = next;
  }

  toString(): string {
    return this.href;
  }
}

export class Window {
  readonly _nativeWindowHandle: number;
  readonly #documentHandle: number;
  readonly #nodeCache: Array<Node | undefined> = [];
  #activeElementHandle: number | null = null;
  readonly #selection = new Selection();
  readonly #cookies = new Map<string, string>();

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
  readonly InputEvent = InputEvent;
  readonly KeyboardEvent = KeyboardEvent;
  readonly MutationObserver = MutationObserver;
  readonly Range = Range;
  readonly Selection = Selection;
  readonly Document = Document;

  readonly location: WindowLocation;
  readonly document: Document;
  readonly localStorage = new Storage();
  readonly sessionStorage = new Storage();
  readonly customElements = new CustomElementRegistry();

  readonly happyDOM: {
    reset: () => void;
    close: () => void;
    abort: () => void;
  };

  constructor(options?: WindowOptions) {
    this._nativeWindowHandle = native.createWindow();
    this.#documentHandle = native.windowDocument(this._nativeWindowHandle);

    this.location = new WindowLocationImpl(options?.url ?? "http://localhost/");

    this.document = this.getNode(this.#documentHandle) as Document;

    this.happyDOM = {
      reset: () => {
        this.assertOpen();
        this.document.reset();
        this.setActiveElement(null);
        this.#selection.removeAllRanges();
        this.#cookies.clear();
        this.localStorage.clear();
        this.sessionStorage.clear();
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
    this.fetch = globalThis.fetch.bind(globalThis);
    this.Headers = globalThis.Headers;
    this.Request = globalThis.Request;
    this.Response = globalThis.Response;
    this.FormData = globalThis.FormData;
    this.Blob = globalThis.Blob;
    this.File = globalThis.File;
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

    const nodeId = handle % 0x1_0000_0000;
    const existing = this.#nodeCache[nodeId];
    if (existing) {
      return existing;
    }

    const kind = native.nodeKind(handle);
    const tagName = kind === Node.ELEMENT_NODE ? native.nodeName(handle).toLowerCase() : undefined;
    return this.#createNode(handle, kind, tagName, false);
  }

  createKnownNode(handle: number, kind: number, options?: { tagName?: string; skipInitialStyleSync?: boolean }): Node | null {
    if (!handle) return null;
    this.assertOpen();

    const nodeId = handle % 0x1_0000_0000;
    const existing = this.#nodeCache[nodeId];
    if (existing) {
      return existing;
    }

    return this.#createNode(handle, kind, options?.tagName, options?.skipInitialStyleSync ?? false);
  }

  #createNode(handle: number, kind: number, tagNameHint: string | undefined, skipInitialStyleSync: boolean): Node {
    let wrapped: Node;
    switch (kind) {
      case Node.DOCUMENT_NODE:
        wrapped = new Document(this, handle, kind);
        break;
      case Node.ELEMENT_NODE: {
        const tagName = tagNameHint ?? native.nodeName(handle).toLowerCase();
        if (tagName === "input") {
          wrapped = new HTMLInputElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "button") {
          wrapped = new HTMLButtonElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "form") {
          wrapped = new HTMLFormElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "iframe") {
          wrapped = new HTMLIFrameElement(this, handle, kind, skipInitialStyleSync);
        } else {
          wrapped = new HTMLElement(this, handle, kind, skipInitialStyleSync);
        }
        break;
      }
      case Node.TEXT_NODE:
        wrapped = new Text(this, handle, kind);
        break;
      case Node.COMMENT_NODE:
        wrapped = new Comment(this, handle, kind);
        break;
      case Node.DOCUMENT_FRAGMENT_NODE:
        wrapped = new DocumentFragment(this, handle, kind);
        break;
      default:
        throw new Error(`Unsupported native node kind: ${kind}`);
    }

    const nodeId = handle % 0x1_0000_0000;
    this.#nodeCache[nodeId] = wrapped;
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
    this.#activeElementHandle = null;
    native.destroyWindow(this._nativeWindowHandle);
    this.#nodeCache.length = 0;
  }

  getActiveElement(): Element | null {
    this.assertOpen();
    if (!this.#activeElementHandle) {
      return this.document.body;
    }

    const node = this.getNode(this.#activeElementHandle);
    if (!node || node.nodeType !== Node.ELEMENT_NODE) {
      return this.document.body;
    }

    return node as Element;
  }

  setActiveElement(element: Element | null): void {
    this.assertOpen();
    this.#activeElementHandle = element?._handle ?? null;
  }

  getSelection(): Selection {
    this.assertOpen();
    return this.#selection;
  }

  getCookieString(): string {
    this.assertOpen();
    return [...this.#cookies.entries()].map(([name, value]) => `${name}=${value}`).join("; ");
  }

  setCookie(cookieHeader: string): void {
    this.assertOpen();
    const pair = cookieHeader.split(";")[0]?.trim();
    if (!pair) {
      return;
    }

    const separatorIndex = pair.indexOf("=");
    if (separatorIndex <= 0) {
      return;
    }

    const name = pair.slice(0, separatorIndex).trim();
    const value = pair.slice(separatorIndex + 1).trim();
    this.#cookies.set(name, value);
  }

  setTimeout!: typeof globalThis.setTimeout;
  clearTimeout!: typeof globalThis.clearTimeout;
  setInterval!: typeof globalThis.setInterval;
  clearInterval!: typeof globalThis.clearInterval;
  queueMicrotask!: typeof globalThis.queueMicrotask;
  fetch!: typeof globalThis.fetch;
  Headers!: typeof globalThis.Headers;
  Request!: typeof globalThis.Request;
  Response!: typeof globalThis.Response;
  FormData!: typeof globalThis.FormData;
  Blob!: typeof globalThis.Blob;
  File!: typeof globalThis.File;
}

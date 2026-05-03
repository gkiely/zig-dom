import { native } from "../ffi.ts";
import { Comment } from "./Comment.ts";
import { CustomElementRegistry } from "./CustomElementRegistry.ts";
import { ZigDOMException } from "./DOMException.ts";
import { Document } from "./Document.ts";
import { DocumentFragment } from "./DocumentFragment.ts";
import { DocumentType } from "./DocumentType.ts";
import { Element } from "./Element.ts";
import { CompositionEvent, CustomEvent, Event, EventTargetBase, InputEvent, KeyboardEvent, MouseEvent } from "./Event.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import {
  HTMLButtonElement,
  HTMLElement,
  HTMLFormElement,
  HTMLIFrameElement,
  HTMLInputElement,
  HTMLLabelElement,
  HTMLOptionElement,
  HTMLSelectElement,
  HTMLTextAreaElement
} from "./HTMLElement.ts";
import { MutationObserver, type InternalMutationRecord } from "./MutationObserver.ts";
import { Node } from "./Node.ts";
import { Range, Selection } from "./Range.ts";
import { Storage } from "./Storage.ts";
import { Text } from "./Text.ts";

const CUSTOM_ELEMENT_UPGRADED = Symbol("zig-dom-custom-element-upgraded");

type CustomElementLifecycle = {
  [CUSTOM_ELEMENT_UPGRADED]?: boolean;
  connectedCallback?: () => void;
  disconnectedCallback?: () => void;
  attributeChangedCallback?: (name: string, oldValue: string | null, newValue: string | null) => void;
  constructor: {
    observedAttributes?: string[];
  };
};

type MutationObserverLike = {
  enqueueRecord(record: InternalMutationRecord): void;
};

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

type ComputedStyleLike = {
  cssText: string;
  display: string;
  visibility: string;
  getPropertyValue(name: string): string;
};

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

export class Window extends EventTargetBase {
  readonly _nativeWindowHandle: number;
  readonly #documentHandle: number;
  readonly #nodeCache: Array<Node | undefined> = [];
  #activeElementHandle: number | null = null;
  readonly #selection = new Selection();
  readonly #cookies = new Map<string, string>();
  readonly #mutationObservers = new Set<MutationObserverLike>();

  #closed = false;

  readonly Node = Node;
  readonly Element = Element;
  readonly HTMLElement = HTMLElement;
  readonly HTMLButtonElement = HTMLButtonElement;
  readonly HTMLIFrameElement = HTMLIFrameElement;
  readonly HTMLInputElement = HTMLInputElement;
  readonly HTMLFormElement = HTMLFormElement;
  readonly HTMLLabelElement = HTMLLabelElement;
  readonly HTMLSelectElement = HTMLSelectElement;
  readonly HTMLOptionElement = HTMLOptionElement;
  readonly HTMLTextAreaElement = HTMLTextAreaElement;
  readonly Text = Text;
  readonly Comment = Comment;
  readonly DocumentFragment = DocumentFragment;
  readonly DocumentType = DocumentType;
  readonly HTMLCollection = HTMLCollection;
  readonly Event = Event;
  readonly CustomEvent = CustomEvent;
  readonly MouseEvent = MouseEvent;
  readonly InputEvent = InputEvent;
  readonly CompositionEvent = CompositionEvent;
  readonly KeyboardEvent = KeyboardEvent;
  readonly DOMException = ZigDOMException;
  readonly MutationObserver = MutationObserver;
  readonly Range = Range;
  readonly Selection = Selection;
  readonly Document = Document;
  readonly XMLDocument = Document;

  readonly location: WindowLocation;
  readonly document: Document;
  readonly localStorage = new Storage();
  readonly sessionStorage = new Storage();
  readonly customElements: CustomElementRegistry;

  readonly happyDOM: {
    reset: () => void;
    close: () => void;
    abort: () => void;
  };

  constructor(options?: WindowOptions) {
    super();
    this._nativeWindowHandle = native.createWindow();
    this.#documentHandle = native.windowDocument(this._nativeWindowHandle);

    this.customElements = new CustomElementRegistry((name) => {
      this.upgradeDefinedElements(name);
    });

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
    Object.defineProperty(this, "parent", { value: this, configurable: true });
    Object.defineProperty(this, "top", { value: this, configurable: true });
    const framesLike = new Proxy({
      item: (index: number) => this.collectFrameWindows()[index] ?? null
    }, {
      get: (target, property, receiver) => {
        if (property === "length") {
          return this.collectFrameWindows().length;
        }

        if (typeof property === "string" && /^\d+$/.test(property)) {
          return this.collectFrameWindows()[Number(property)] ?? undefined;
        }

        return Reflect.get(target, property, receiver);
      },
      has: (target, property) => {
        if (typeof property === "string" && /^\d+$/.test(property)) {
          return Number(property) < this.collectFrameWindows().length;
        }
        return Reflect.has(target, property);
      },
      ownKeys: (target) => {
        const frameWindows = this.collectFrameWindows();
        const numeric = frameWindows.map((_, index) => String(index));
        return [...Reflect.ownKeys(target), ...numeric, "length"];
      },
      getOwnPropertyDescriptor: (target, property) => {
        if (property === "length") {
          return {
            configurable: true,
            enumerable: false,
            writable: false,
            value: this.collectFrameWindows().length
          };
        }

        if (typeof property === "string" && /^\d+$/.test(property)) {
          const frameWindows = this.collectFrameWindows();
          const index = Number(property);
          if (index < frameWindows.length) {
            return {
              configurable: true,
              enumerable: true,
              writable: false,
              value: frameWindows[index]
            };
          }
        }

        return Reflect.getOwnPropertyDescriptor(target, property);
      }
    });
    Object.defineProperty(this, "frames", { value: framesLike, configurable: true });
    Object.defineProperty(this, "opener", {
      value: null,
      configurable: true,
      writable: true
    });

    const htmlElementAliases = [
      "HTMLAudioElement",
      "HTMLAnchorElement",
      "HTMLAreaElement",
      "HTMLBaseElement",
      "HTMLBodyElement",
      "HTMLBRElement",
      "HTMLCanvasElement",
      "HTMLDataElement",
      "HTMLDataListElement",
      "HTMLDialogElement",
      "HTMLDivElement",
      "HTMLDListElement",
      "HTMLDirectoryElement",
      "HTMLEmbedElement",
      "HTMLFieldSetElement",
      "HTMLFontElement",
      "HTMLFrameElement",
      "HTMLFrameSetElement",
      "HTMLHeadElement",
      "HTMLHeadingElement",
      "HTMLHRElement",
      "HTMLHtmlElement",
      "HTMLImageElement",
      "HTMLLegendElement",
      "HTMLLIElement",
      "HTMLLinkElement",
      "HTMLMenuElement",
      "HTMLMetaElement",
      "HTMLMeterElement",
      "HTMLModElement",
      "HTMLMapElement",
      "HTMLOListElement",
      "HTMLObjectElement",
      "HTMLOptGroupElement",
      "HTMLOutputElement",
      "HTMLParagraphElement",
      "HTMLParamElement",
      "HTMLPictureElement",
      "HTMLPreElement",
      "HTMLProgressElement",
      "HTMLQuoteElement",
      "HTMLScriptElement",
      "HTMLSlotElement",
      "HTMLSourceElement",
      "HTMLSpanElement",
      "HTMLStyleElement",
      "HTMLTableCaptionElement",
      "HTMLTableCellElement",
      "HTMLTableColElement",
      "HTMLTableElement",
      "HTMLTableRowElement",
      "HTMLTableSectionElement",
      "HTMLTemplateElement",
      "HTMLTimeElement",
      "HTMLTitleElement",
      "HTMLTrackElement",
      "HTMLUnknownElement",
      "HTMLVideoElement",
      "HTMLUListElement"
    ];

    const selfRecord = this as unknown as Record<string, unknown>;
    for (const constructorName of htmlElementAliases) {
      if (!(constructorName in selfRecord)) {
        Object.defineProperty(this, constructorName, {
          value: HTMLElement,
          configurable: true,
          writable: true
        });
      }
    }

    if (!("HTMLUnknownElement" in selfRecord)) {
      Object.defineProperty(this, "HTMLUnknownElement", {
        value: HTMLElement,
        configurable: true,
        writable: true
      });
    }

    if (!("Attr" in selfRecord)) {
      class AttrImpl {}
      Object.defineProperty(this, "Attr", {
        value: AttrImpl,
        configurable: true,
        writable: true
      });
    }

    const WindowCtor = this.constructor as {
      new (options?: { url?: string }): Window;
    };

    const BaseDocument = Document;
    class DocumentConstructor {
      constructor() {
        const scopedWindow = new WindowCtor({ url: "about:blank" });
        const scopedDocument = scopedWindow.document;
        for (const child of scopedDocument.childNodes.toArray()) {
          scopedDocument.removeChild(child);
        }
        (scopedDocument as unknown as { __forceNoDocumentElement?: boolean }).__forceNoDocumentElement = true;
        Object.setPrototypeOf(scopedDocument, DocumentConstructor.prototype);
        return scopedDocument;
      }
    }
    Object.setPrototypeOf(DocumentConstructor.prototype, BaseDocument.prototype);

    Object.defineProperty(this, "Document", {
      value: DocumentConstructor,
      configurable: true,
      writable: true
    });

    Object.defineProperty(this, "XMLDocument", {
      value: DocumentConstructor,
      configurable: true,
      writable: true
    });

    Object.defineProperty(this, "open", {
      value: (url?: string) => new WindowCtor({ url: url ?? this.location.href }),
      configurable: true,
      writable: true
    });

    class DOMParserImpl {
      parseFromString(source: string, type: string): Document {
        if (type.toLowerCase().includes("xml")) {
          const parsedDocument = new DocumentConstructor() as unknown as Document;
          const rootMatch = source.match(/<\s*([A-Za-z_][A-Za-z0-9._:-]*)[^>]*\/?\s*>/);
          const rootName = rootMatch?.[1];
          if (rootName) {
            const root = parsedDocument.createElement(rootName);
            (root as unknown as { __namespaceURI?: string | null }).__namespaceURI = null;
            Object.defineProperty(parsedDocument, "documentElement", {
              value: root,
              configurable: true,
              writable: true
            });
          }
          return parsedDocument;
        }

        const parsedWindow = new WindowCtor({ url: "http://localhost/" });
        const parsedDocument = parsedWindow.document;
        const doctypeMatch = source.match(/<!doctype\s+([A-Za-z0-9:_-]+)/i);
        if (doctypeMatch && !parsedDocument.doctype) {
          const doctype = parsedDocument.implementation.createDocumentType(doctypeMatch[1], "", "");
          parsedDocument.insertBefore(doctype as unknown as Node, parsedDocument.firstChild);
        }
        const bodySource = source.replace(/<!doctype[^>]*>/i, "");
        parsedDocument.body.innerHTML = bodySource;
        return parsedDocument;
      }
    }

    if (!("DOMParser" in selfRecord)) {
      Object.defineProperty(this, "DOMParser", {
        value: DOMParserImpl,
        configurable: true,
        writable: true
      });
    }

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
    this.getComputedStyle = this.getComputedStyle.bind(this);
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
    let elementTagName: string | undefined;
    switch (kind) {
      case Node.DOCUMENT_NODE:
        wrapped = new Document(this, handle, kind);
        break;
      case Node.ELEMENT_NODE: {
        const tagName = tagNameHint ?? native.nodeName(handle).toLowerCase();
        elementTagName = tagName;
        if (tagName === "input") {
          wrapped = new HTMLInputElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "button") {
          wrapped = new HTMLButtonElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "form") {
          wrapped = new HTMLFormElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "label") {
          wrapped = new HTMLLabelElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "select") {
          wrapped = new HTMLSelectElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "option") {
          wrapped = new HTMLOptionElement(this, handle, kind, skipInitialStyleSync);
        } else if (tagName === "textarea") {
          wrapped = new HTMLTextAreaElement(this, handle, kind, skipInitialStyleSync);
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
      case Node.DOCUMENT_TYPE_NODE:
        wrapped = new DocumentType(this, handle);
        break;
      default:
        throw new Error(`Unsupported native node kind: ${kind}`);
    }

    if (elementTagName && this.customElements.hasDefinitions) {
      this.upgradeElementInstance(wrapped as Element, elementTagName);
    }

    const nodeId = handle % 0x1_0000_0000;
    this.#nodeCache[nodeId] = wrapped;
    return wrapped;
  }

  isConnectedNode(node: Node): boolean {
    let cursor: Node | null = node;
    while (cursor) {
      if (cursor.nodeType === Node.DOCUMENT_NODE) {
        return true;
      }

      if (cursor.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
        const host: Node | null | undefined = (cursor as unknown as { host?: Node | null }).host;
        if (host) {
          cursor = host;
          continue;
        }
      }

      cursor = cursor.parentNode;
    }
    return false;
  }

  private collectFrameWindows(): Window[] {
    const candidates = this.document.querySelectorAll("iframe") as unknown as Array<{
      contentWindow?: Window | null;
    }>;

    const frames: Window[] = [];
    for (const candidate of candidates) {
      if (candidate.contentWindow) {
        frames.push(candidate.contentWindow);
      }
    }

    return frames;
  }

  upgradeElementInstance(element: Element, normalizedTagName?: string): void {
    if (!this.customElements.hasDefinitions) {
      return;
    }

    const tagName = normalizedTagName ?? element.tagName.toLowerCase();
    if (!tagName.includes("-")) {
      return;
    }

    const customConstructor = this.customElements.get(tagName);
    if (!customConstructor) {
      return;
    }

    if (Object.getPrototypeOf(element) !== customConstructor.prototype) {
      Object.setPrototypeOf(element, customConstructor.prototype);
    }

    const lifecycle = element as unknown as CustomElementLifecycle;
    if (lifecycle[CUSTOM_ELEMENT_UPGRADED]) {
      return;
    }

    lifecycle[CUSTOM_ELEMENT_UPGRADED] = true;

    const observed = lifecycle.constructor.observedAttributes ?? [];
    if (typeof lifecycle.attributeChangedCallback === "function" && observed.length > 0) {
      const observedSet = new Set(observed.map((name) => name.toLowerCase()));
      for (const attribute of element.attributes) {
        if (observedSet.has(attribute.name.toLowerCase())) {
          lifecycle.attributeChangedCallback.call(element, attribute.name, null, attribute.value);
        }
      }
    }

    if (this.isConnectedNode(element)) {
      lifecycle.connectedCallback?.call(element);
    }
  }

  upgradeDefinedElements(tagName: string): void {
    const existing = this.document.querySelectorAll(tagName);
    for (const element of existing) {
      this.upgradeElementInstance(element, tagName);
    }
  }

  notifyConnectedSubtree(root: Node): void {
    if (!this.customElements.hasDefinitions) {
      return;
    }
    this.#walkElementSubtree(root, (element) => {
      const lifecycle = element as unknown as CustomElementLifecycle;
      if (lifecycle[CUSTOM_ELEMENT_UPGRADED]) {
        lifecycle.connectedCallback?.call(element);
      }
    });
  }

  notifyDisconnectedSubtree(root: Node): void {
    if (!this.customElements.hasDefinitions) {
      return;
    }
    this.#walkElementSubtree(root, (element) => {
      const lifecycle = element as unknown as CustomElementLifecycle;
      if (lifecycle[CUSTOM_ELEMENT_UPGRADED]) {
        lifecycle.disconnectedCallback?.call(element);
      }
    });
  }

  notifyAttributeChanged(element: Element, name: string, oldValue: string | null, newValue: string | null): void {
    if (oldValue === newValue) {
      return;
    }

    this.emitMutationRecord({
      type: "attributes",
      target: element,
      addedNodes: [],
      removedNodes: [],
      previousSibling: null,
      nextSibling: null,
      attributeName: name,
      attributeNamespace: null,
      oldValue
    });

    if (!this.customElements.hasDefinitions) {
      return;
    }

    const lifecycle = element as unknown as CustomElementLifecycle;
    if (!lifecycle[CUSTOM_ELEMENT_UPGRADED] || typeof lifecycle.attributeChangedCallback !== "function") {
      return;
    }

    const observed = lifecycle.constructor.observedAttributes ?? [];
    const normalized = name.toLowerCase();
    if (!observed.some((value) => value.toLowerCase() === normalized)) {
      return;
    }

    lifecycle.attributeChangedCallback.call(element, normalized, oldValue, newValue);
  }

  notifyChildListMutation(target: Node, addedNodes: Node[], removedNodes: Node[], previousSibling: Node | null, nextSibling: Node | null): void {
    this.emitMutationRecord({
      type: "childList",
      target,
      addedNodes,
      removedNodes,
      previousSibling,
      nextSibling,
      attributeName: null,
      attributeNamespace: null,
      oldValue: null
    });
  }

  notifyCharacterDataChanged(target: Node, oldValue: string): void {
    this.emitMutationRecord({
      type: "characterData",
      target,
      addedNodes: [],
      removedNodes: [],
      previousSibling: null,
      nextSibling: null,
      attributeName: null,
      attributeNamespace: null,
      oldValue
    });
  }

  registerMutationObserver(observer: MutationObserverLike): void {
    this.#mutationObservers.add(observer);
  }

  unregisterMutationObserver(observer: MutationObserverLike): void {
    this.#mutationObservers.delete(observer);
  }

  hasMutationObservers(): boolean {
    return this.#mutationObservers.size > 0;
  }

  private emitMutationRecord(record: InternalMutationRecord): void {
    if (this.#mutationObservers.size === 0) {
      return;
    }

    for (const observer of this.#mutationObservers) {
      observer.enqueueRecord(record);
    }
  }

  #walkElementSubtree(root: Node, visit: (element: Element) => void): void {
    const stack: Node[] = [root];
    while (stack.length > 0) {
      const node = stack.pop();
      if (!node) {
        continue;
      }

      if (node.nodeType === Node.ELEMENT_NODE) {
        visit(node as unknown as Element);
      }

      const children = node.childNodes.toArray();
      for (let index = children.length - 1; index >= 0; index -= 1) {
        const child = children[index];
        if (child) {
          stack.push(child);
        }
      }
    }
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

  adoptSubtreeWrappers(root: Node): void {
    this.assertOpen();

    const stack: Node[] = [root];
    while (stack.length > 0) {
      const current = stack.pop();
      if (!current) {
        continue;
      }

      const mutable = current as unknown as { _window: Window };
      mutable._window = this;

      const nodeId = current._handle % 0x1_0000_0000;
      this.#nodeCache[nodeId] = current;

      for (const child of current.childNodes.toArray()) {
        stack.push(child);
      }
    }
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    this.#activeElementHandle = null;
    this.#mutationObservers.clear();
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

  getComputedStyle(element: Element): ComputedStyleLike {
    this.assertOpen();

    const declarations = new Map<string, string>();
    const styleText = element.getAttribute("style") ?? "";
    for (const part of styleText.split(";")) {
      const [rawName, rawValue] = part.split(":");
      const name = rawName?.trim().toLowerCase();
      const value = rawValue?.trim();
      if (name && value) {
        declarations.set(name, value);
      }
    }

    return {
      cssText: styleText,
      display: declarations.get("display") ?? "block",
      visibility: declarations.get("visibility") ?? "visible",
      getPropertyValue(name: string): string {
        return declarations.get(name.trim().toLowerCase()) ?? "";
      }
    };
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

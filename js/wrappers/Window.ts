import { native } from "../ffi.ts";
import { CharacterData } from "./CharacterData.ts";
import { Comment } from "./Comment.ts";
import { CustomElementRegistry } from "./CustomElementRegistry.ts";
import { ZigDOMException } from "./DOMException.ts";
import { Document } from "./Document.ts";
import { DocumentFragment } from "./DocumentFragment.ts";
import { DocumentType } from "./DocumentType.ts";
import { DOMTokenList, Element } from "./Element.ts";
import { CompositionEvent, CustomEvent, Event, EventTargetBase, FocusEvent, InputEvent, KeyboardEvent, MouseEvent, UIEvent, WheelEvent } from "./Event.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import {
  HTMLAnchorElement,
  HTMLButtonElement,
  HTMLElement,
  HTMLFormElement,
  HTMLIFrameElement,
  HTMLInputElement,
  HTMLLabelElement,
  HTMLLIElement,
  HTMLOListElement,
  HTMLOptionElement,
  HTMLSelectElement,
  HTMLSpanElement,
  HTMLTextAreaElement,
  HTMLUListElement
} from "./HTMLElement.ts";
import { MutationObserver, type InternalMutationRecord } from "./MutationObserver.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { Range, Selection } from "./Range.ts";
import { Storage } from "./Storage.ts";
import { Text } from "./Text.ts";

class DOMImplementation {}
class NodeIterator {}
class TreeWalker {}
class NodeFilter {
  static readonly FILTER_ACCEPT = 1;
  static readonly FILTER_REJECT = 2;
  static readonly FILTER_SKIP = 3;
  static readonly SHOW_ALL = 0xffffffff;
  static readonly SHOW_ELEMENT = 0x1;
  static readonly SHOW_ATTRIBUTE = 0x2;
  static readonly SHOW_TEXT = 0x4;
  static readonly SHOW_CDATA_SECTION = 0x8;
  static readonly SHOW_ENTITY_REFERENCE = 0x10;
  static readonly SHOW_ENTITY = 0x20;
  static readonly SHOW_PROCESSING_INSTRUCTION = 0x40;
  static readonly SHOW_COMMENT = 0x80;
  static readonly SHOW_DOCUMENT = 0x100;
  static readonly SHOW_DOCUMENT_TYPE = 0x200;
  static readonly SHOW_DOCUMENT_FRAGMENT = 0x400;
  static readonly SHOW_NOTATION = 0x800;
}
class ProcessingInstruction {}

const CUSTOM_ELEMENT_UPGRADED = Symbol("zig-dom-custom-element-upgraded");
const HTML_NAMESPACE = "http://www.w3.org/1999/xhtml";
const SVG_NAMESPACE = "http://www.w3.org/2000/svg";

function htmlElementConstructorAlias(constructorName: string): typeof HTMLElement {
  switch (constructorName) {
    case "HTMLAnchorElement":
      return HTMLAnchorElement;
    case "HTMLLIElement":
      return HTMLLIElement;
    case "HTMLOListElement":
      return HTMLOListElement;
    case "HTMLSpanElement":
      return HTMLSpanElement;
    case "HTMLUListElement":
      return HTMLUListElement;
    default:
      return HTMLElement;
  }
}

function asciiLowercase(value: string): string {
  if (!/[A-Z]/.test(value)) {
    return value;
  }
  return value.replace(/[A-Z]/g, (letter) => letter.toLowerCase());
}

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

export interface WindowHistory {
  readonly length: number;
  readonly state: unknown;
  back(): void;
  forward(): void;
  go(delta?: number): void;
  pushState(state: unknown, unused: string, url?: string | URL | null): void;
  replaceState(state: unknown, unused: string, url?: string | URL | null): void;
}

type ComputedStyleLike = {
  cssText: string;
  display: string;
  listStyleType: string;
  visibility: string;
  getPropertyValue(name: string): string;
  [property: string]: string | ((name: string) => string);
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

class WindowHistoryImpl implements WindowHistory {
  #entries: Array<{ state: unknown; href: string }>;
  #index = 0;
  readonly #window: Window;

  constructor(window: Window) {
    this.#window = window;
    this.#entries = [{ state: null, href: this.#window.location.href }];
  }

  get length(): number {
    return this.#entries.length;
  }

  get state(): unknown {
    return this.#entries[this.#index]?.state ?? null;
  }

  back(): void {
    this.go(-1);
  }

  forward(): void {
    this.go(1);
  }

  go(delta = 0): void {
    if (delta === 0) {
      return;
    }

    const nextIndex = this.#index + Number(delta);
    if (!Number.isInteger(nextIndex) || nextIndex < 0 || nextIndex >= this.#entries.length) {
      return;
    }

    this.#index = nextIndex;
    const entry = this.#entries[this.#index];
    this.#window.location.href = entry.href;
    const event = new Event("popstate");
    Object.defineProperty(event, "state", {
      value: entry.state,
      configurable: true
    });
    this.#window.dispatchEvent(event);
  }

  pushState(state: unknown, _unused: string, url?: string | URL | null): void {
    const href = this.#resolveHref(url);
    this.#entries[this.#index] = {
      state: this.#entries[this.#index]?.state ?? null,
      href: this.#window.location.href
    };
    this.#entries.splice(this.#index + 1);
    this.#entries.push({ state, href });
    this.#index = this.#entries.length - 1;
    this.#window.location.href = href;
  }

  replaceState(state: unknown, _unused: string, url?: string | URL | null): void {
    const href = this.#resolveHref(url);
    this.#entries[this.#index] = { state, href };
    this.#window.location.href = href;
  }

  #resolveHref(url?: string | URL | null): string {
    if (url == null) {
      return this.#window.location.href;
    }
    return new URL(String(url), this.#window.location.href).href;
  }
}

function nodeIdFromHandle(handle: number): number {
  return handle >>> 0;
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
  readonly NodeList = NodeList;
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
  readonly CharacterData = CharacterData;
  readonly Comment = Comment;
  readonly DocumentFragment = DocumentFragment;
  readonly ProcessingInstruction = ProcessingInstruction;
  readonly DocumentType = DocumentType;
  readonly HTMLCollection = HTMLCollection;
  readonly EventTarget = EventTargetBase;
  readonly Event = Event;
  readonly UIEvent = UIEvent;
  readonly FocusEvent = FocusEvent;
  readonly CustomEvent = CustomEvent;
  readonly MouseEvent = MouseEvent;
  readonly WheelEvent = WheelEvent;
  readonly InputEvent = InputEvent;
  readonly CompositionEvent = CompositionEvent;
  readonly KeyboardEvent = KeyboardEvent;
  readonly DOMException = ZigDOMException;
  readonly TypeError = TypeError;
  readonly DOMImplementation = DOMImplementation;
  readonly NodeIterator = NodeIterator;
  readonly TreeWalker = TreeWalker;
  readonly NodeFilter = NodeFilter;
  readonly DOMTokenList = DOMTokenList;
  readonly MutationObserver = MutationObserver;
  readonly Range = Range;
  readonly Selection = Selection;
  readonly Document = Document;
  readonly XMLDocument = Document;

  readonly location: WindowLocation;
  readonly history: WindowHistory;
  readonly document: Document;
  readonly localStorage = new Storage();
  readonly sessionStorage = new Storage();
  readonly customElements: CustomElementRegistry;
  _hasCustomElementDefinitions = false;
  _hasCustomElementConnectionCallbacks = false;
  _hasMutationObservers = false;
  onanimationend: ((event: Event) => void) | null = null;
  onanimationiteration: ((event: Event) => void) | null = null;
  onanimationstart: ((event: Event) => void) | null = null;
  ontransitionend: ((event: Event) => void) | null = null;

  readonly happyDOM: {
    reset: () => void;
    close: () => void;
    abort: () => void;
  };

  constructor(options?: WindowOptions) {
    super();
    this._nativeWindowHandle = native.createWindow();
    this.#documentHandle = native.windowDocument(this._nativeWindowHandle);

    this.customElements = new CustomElementRegistry((name, constructor) => {
      this._hasCustomElementDefinitions = true;
      const prototype = constructor.prototype as unknown as {
        connectedCallback?: () => void;
        disconnectedCallback?: () => void;
      };
      if (
        typeof prototype.connectedCallback === "function" ||
        typeof prototype.disconnectedCallback === "function"
      ) {
        this._hasCustomElementConnectionCallbacks = true;
      }
      this.upgradeDefinedElements(name);
    });

    this.location = new WindowLocationImpl(options?.url ?? "http://localhost/");
    this.history = new WindowHistoryImpl(this);

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
    Object.defineProperty(this, "event", {
      value: undefined,
      configurable: true,
      writable: true
    });
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
          value: htmlElementConstructorAlias(constructorName),
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

    if (!("NamedNodeMap" in selfRecord)) {
      class NamedNodeMapImpl {}
      Object.defineProperty(this, "NamedNodeMap", {
        value: NamedNodeMapImpl,
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

    const BaseCharacterData = CharacterData;
    const CharacterDataConstructor = function(this: unknown) {
      throw new TypeError("Illegal constructor");
    } as unknown as {
      new (): CharacterData;
      prototype: CharacterData;
    };
    CharacterDataConstructor.prototype = BaseCharacterData.prototype;

    const thisWindow = this;
    const BaseText = Text;
    const TextConstructor = function(this: unknown, data?: unknown) {
      const value = arguments.length === 0 || data === undefined ? "" : String(data);
      return thisWindow.document.createTextNode(value);
    } as unknown as {
      new (data?: unknown): Text;
      prototype: Text;
    };
    TextConstructor.prototype = BaseText.prototype;

    const BaseComment = Comment;
    const CommentConstructor = function(this: unknown, data?: unknown) {
      const value = arguments.length === 0 || data === undefined ? "" : String(data);
      return thisWindow.document.createComment(value);
    } as unknown as {
      new (data?: unknown): Comment;
      prototype: Comment;
    };
    CommentConstructor.prototype = BaseComment.prototype;

    const BaseDocumentFragment = DocumentFragment;
    const DocumentFragmentConstructor = function(this: unknown) {
      return thisWindow.document.createDocumentFragment();
    } as unknown as {
      new (): DocumentFragment;
      prototype: DocumentFragment;
    };
    DocumentFragmentConstructor.prototype = BaseDocumentFragment.prototype;

    Object.defineProperty(this, "CharacterData", {
      value: CharacterDataConstructor,
      configurable: true,
      writable: true
    });

    Object.defineProperty(this, "Text", {
      value: TextConstructor,
      configurable: true,
      writable: true
    });

    Object.defineProperty(this, "Comment", {
      value: CommentConstructor,
      configurable: true,
      writable: true
    });

    Object.defineProperty(this, "DocumentFragment", {
      value: DocumentFragmentConstructor,
      configurable: true,
      writable: true
    });

    if (!("UIEvent" in selfRecord)) {
      Object.defineProperty(this, "UIEvent", {
        value: Event,
        configurable: true,
        writable: true
      });
    }

    if (!("FocusEvent" in selfRecord)) {
      Object.defineProperty(this, "FocusEvent", {
        value: Event,
        configurable: true,
        writable: true
      });
    }

    class DOMParserImpl {
      parseFromString(source: string, type: string): Document {
        const mimeType = String(type).toLowerCase();
        if (mimeType.includes("xml") || mimeType === "image/svg+xml") {
          const parsedDocument = new DocumentConstructor() as unknown as Document;
          const documentMetadata = parsedDocument as unknown as { __isXMLDocument?: boolean; __contentType?: string };
          documentMetadata.__isXMLDocument = true;
          documentMetadata.__contentType = mimeType;
          const rootMatch = source.match(/<\s*([A-Za-z_][A-Za-z0-9._:-]*)[^>]*\/?\s*>/);
          const rootName = rootMatch?.[1];
          if (rootName) {
            const rootSource = rootMatch?.[0] ?? "";
            const namespaceMatch = rootSource.match(/\sxmlns=(?:"([^"]*)"|'([^']*)')/);
            const namespaceURI = namespaceMatch
              ? namespaceMatch[1] ?? namespaceMatch[2] ?? null
              : mimeType === "application/xhtml+xml"
                ? HTML_NAMESPACE
                : mimeType === "image/svg+xml"
                  ? SVG_NAMESPACE
                  : null;
            const root = parsedDocument.createElementNS(namespaceURI, rootName);
            const metadata = root as unknown as { __namespaceURI?: string | null; __isXMLNode?: boolean };
            metadata.__namespaceURI = namespaceURI;
            metadata.__isXMLNode = true;
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
    this.requestAnimationFrame = (callback: FrameRequestCallback): number => {
      return globalThis.setTimeout(() => callback(globalThis.performance.now()), 0) as unknown as number;
    };
    this.cancelAnimationFrame = (handle: number): void => {
      globalThis.clearTimeout(handle as unknown as ReturnType<typeof globalThis.setTimeout>);
    };
    this.queueMicrotask = globalThis.queueMicrotask.bind(globalThis);
    this.fetch = globalThis.fetch.bind(globalThis);
    this.Headers = globalThis.Headers;
    this.Request = globalThis.Request;
    this.Response = globalThis.Response;
    this.FormData = globalThis.FormData;
    this.Blob = globalThis.Blob;
    this.File = globalThis.File;
    this.URL = globalThis.URL;
    this.AbortSignal = globalThis.AbortSignal;
    this.AbortController = globalThis.AbortController;
    this.getComputedStyle = this.getComputedStyle.bind(this);
    this.#makeInterfacePropertiesNonEnumerable();

    if (!("performance" in selfRecord)) {
      Object.defineProperty(this, "performance", {
        value: globalThis.performance,
        configurable: true,
        writable: true
      });
    }

    if (!("eval" in selfRecord)) {
      Object.defineProperty(this, "eval", {
        value: globalThis.eval,
        configurable: true,
        writable: true
      });
    }

    if (!("XMLHttpRequest" in selfRecord) && "XMLHttpRequest" in globalThis) {
      Object.defineProperty(this, "XMLHttpRequest", {
        value: (globalThis as unknown as Record<string, unknown>).XMLHttpRequest,
        configurable: true,
        writable: true
      });
    }
  }

  #makeInterfacePropertiesNonEnumerable(): void {
    const names = [
      "Event", "CustomEvent", "EventTarget", "AbortController", "AbortSignal",
      "Node", "Document", "DOMImplementation", "DocumentFragment", "ProcessingInstruction",
      "DocumentType", "Element", "Attr", "CharacterData", "Text", "Comment",
      "NodeIterator", "TreeWalker", "NodeFilter", "NodeList", "HTMLCollection", "DOMTokenList"
    ];
    for (const name of names) {
      const value = (this as unknown as Record<string, unknown>)[name];
      if (value == null) {
        continue;
      }
      Object.defineProperty(this, name, {
        value,
        configurable: true,
        writable: true,
        enumerable: false
      });
    }
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

    const nodeId = nodeIdFromHandle(handle);
    const existing = this.#nodeCache[nodeId];
    if (existing) {
      return existing;
    }

    const kind = native.nodeKind(handle);
    if (kind === 0) {
      return null;
    }
    const tagName = kind === Node.ELEMENT_NODE ? asciiLowercase(native.nodeName(handle)) : undefined;
    return this.#createNode(handle, kind, tagName, false);
  }

  createKnownNode(handle: number, kind: number, tagNameOrOptions?: string | { tagName?: string; skipInitialStyleSync?: boolean }, skipInitialStyleSync = false): Node | null {
    if (!handle) return null;
    this.assertOpen();

    const nodeId = nodeIdFromHandle(handle);
    const existing = this.#nodeCache[nodeId];
    if (existing) {
      return existing;
    }

    const tagNameHint = typeof tagNameOrOptions === "string"
      ? tagNameOrOptions
      : tagNameOrOptions?.tagName;
    const skipStyleSync = typeof tagNameOrOptions === "string"
      ? skipInitialStyleSync
      : tagNameOrOptions?.skipInitialStyleSync ?? false;

    return this.#createNode(handle, kind, tagNameHint, skipStyleSync);
  }

  createFreshElementNode(handle: number, tagName: string, skipInitialStyleSync = false): Element {
    const wrapped = this.#createElementNode(handle, tagName, skipInitialStyleSync);
    if (this.customElements.hasDefinitions) {
      this.upgradeElementInstance(wrapped, tagName);
    }
    this.#nodeCache[nodeIdFromHandle(handle)] = wrapped;
    return wrapped;
  }

  createFreshTextNode(handle: number): Text {
    const wrapped = new Text(this, handle, Node.TEXT_NODE);
    this.#nodeCache[nodeIdFromHandle(handle)] = wrapped;
    return wrapped;
  }

  bindNodeToHandle(handle: number, node: Node): void {
    if (!handle) {
      return;
    }
    const nodeId = nodeIdFromHandle(handle);
    this.#nodeCache[nodeId] = node;
  }

  unbindNodeFromHandle(handle: number, node?: Node): void {
    if (!handle) {
      return;
    }
    const nodeId = nodeIdFromHandle(handle);
    if (node == null || this.#nodeCache[nodeId] === node) {
      this.#nodeCache[nodeId] = undefined;
    }
  }

  #createNode(handle: number, kind: number, tagNameHint: string | undefined, skipInitialStyleSync: boolean): Node {
    let wrapped: Node;
    let elementTagName: string | undefined;
    switch (kind) {
      case Node.DOCUMENT_NODE:
        wrapped = new Document(this, handle, kind);
        break;
      case Node.ELEMENT_NODE: {
        const tagName = tagNameHint ?? asciiLowercase(native.nodeName(handle));
        elementTagName = tagName;
        wrapped = this.#createElementNode(handle, tagName, skipInitialStyleSync);
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

    const nodeId = nodeIdFromHandle(handle);
    this.#nodeCache[nodeId] = wrapped;
    return wrapped;
  }

  #createElementNode(handle: number, tagName: string, skipInitialStyleSync: boolean): Element {
    switch (tagName) {
      case "input":
        return new HTMLInputElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "button":
        return new HTMLButtonElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "form":
        return new HTMLFormElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "label":
        return new HTMLLabelElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "select":
        return new HTMLSelectElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "option":
        return new HTMLOptionElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "textarea":
        return new HTMLTextAreaElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "a":
        return new HTMLAnchorElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "li":
        return new HTMLLIElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "ol":
        return new HTMLOListElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "ul":
        return new HTMLUListElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "span":
        return new HTMLSpanElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      case "iframe":
        return new HTMLIFrameElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
      default:
        return new HTMLElement(this, handle, Node.ELEMENT_NODE, skipInitialStyleSync);
    }
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

  notifyAttributeChanged(element: Element, name: string, oldValue: string | null, newValue: string | null, forceMutation = false): void {
    if (oldValue === newValue && !forceMutation) {
      return;
    }

    if (this.#mutationObservers.size > 0) {
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
    }

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
    if (this.#mutationObservers.size > 0) {
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
    this._hasMutationObservers = true;
  }

  unregisterMutationObserver(observer: MutationObserverLike): void {
    this.#mutationObservers.delete(observer);
    this._hasMutationObservers = this.#mutationObservers.size > 0;
  }

  hasMutationObservers(): boolean {
    return this._hasMutationObservers;
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

    const handles = native.nodeChildHandles(parentHandle);
    const nodes: Node[] = [];
    for (let index = 0; index < handles.length; index += 1) {
      const node = this.getNode(handles[index] ?? 0);
      if (node) {
        nodes.push(node);
      }
    }
    return nodes;
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
    this._hasMutationObservers = false;
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

    const computed = {
      cssText: styleText,
      display: declarations.get("display") ?? "block",
      listStyleType: declarations.get("list-style-type") ?? (element.tagName === "OL" ? "decimal" : "disc"),
      visibility: declarations.get("visibility") ?? "visible",
      getPropertyValue(name: string): string {
        return declarations.get(name.trim().toLowerCase()) ?? "";
      }
    };
    return new Proxy(computed, {
      get(target, property, receiver) {
        if (typeof property === "string" && !(property in target)) {
          return declarations.get(property.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`)) ?? "";
        }
        return Reflect.get(target, property, receiver);
      }
    });
  }

  setTimeout!: typeof globalThis.setTimeout;
  clearTimeout!: typeof globalThis.clearTimeout;
  setInterval!: typeof globalThis.setInterval;
  clearInterval!: typeof globalThis.clearInterval;
  requestAnimationFrame!: typeof globalThis.requestAnimationFrame;
  cancelAnimationFrame!: typeof globalThis.cancelAnimationFrame;
  queueMicrotask!: typeof globalThis.queueMicrotask;
  fetch!: typeof globalThis.fetch;
  Headers!: typeof globalThis.Headers;
  Request!: typeof globalThis.Request;
  Response!: typeof globalThis.Response;
  FormData!: typeof globalThis.FormData;
  Blob!: typeof globalThis.Blob;
  File!: typeof globalThis.File;
  URL!: typeof globalThis.URL;
  AbortSignal!: typeof globalThis.AbortSignal;
  AbortController!: typeof globalThis.AbortController;
  declare performance: typeof globalThis.performance;
}

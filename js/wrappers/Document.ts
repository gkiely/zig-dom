import { native } from "../ffi.ts";
import { Comment } from "./Comment.ts";
import { DocumentFragment } from "./DocumentFragment.ts";
import { DocumentType } from "./DocumentType.ts";
import { ZigDOMException } from "./DOMException.ts";
import { Element } from "./Element.ts";
import { CompositionEvent, CustomEvent, Event, FocusEvent, InputEvent, KeyboardEvent, MouseEvent, UIEvent, WheelEvent } from "./Event.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { Range, Selection } from "./Range.ts";
import { canUseNativeSelector, querySelectorAllInDocument } from "./selector-engine.ts";
import { Text } from "./Text.ts";
import type { Window } from "./Window.ts";

const XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace";
const XMLNS_NAMESPACE = "http://www.w3.org/2000/xmlns/";

function asciiLowercase(value: string): string {
  return value.replace(/[A-Z]/g, (letter) => letter.toLowerCase());
}

function createSyntheticAttr(document: Document, name: string, namespaceURI: string | null): Attr {
  const AttrCtor = ((document._window as unknown as {
    Attr?: new () => Record<string, unknown>;
  }).Attr) ?? class {};

  const attr = Object.assign(new AttrCtor(), {
    nodeType: Node.ATTRIBUTE_NODE,
    nodeName: name,
    name,
    value: "",
    namespaceURI,
    ownerElement: null as Element | null,
    parentNode: null,
    parentElement: null,
    get textContent() {
      return this.value;
    },
    set textContent(next: string | null) {
      this.value = next ?? "";
    },
    lookupNamespaceURI(prefix: string | null) {
      if (!this.ownerElement) {
        return null;
      }
      return this.ownerElement.lookupNamespaceURI(prefix);
    },
    isDefaultNamespace(namespace: string | null) {
      if (!this.ownerElement) {
        return namespace == null || namespace === "";
      }
      return this.ownerElement.isDefaultNamespace(namespace);
    },
    isSameNode(other: unknown) {
      return other === this;
    },
    isEqualNode(other: unknown) {
      if (!other || typeof other !== "object") {
        return false;
      }
      const candidate = other as { name?: string; value?: string; namespaceURI?: string | null };
      return candidate.name === this.name && candidate.value === this.value && candidate.namespaceURI === this.namespaceURI;
    },
    cloneNode() {
      const clone = createSyntheticAttr(document, this.name, this.namespaceURI) as unknown as { value: string };
      clone.value = this.value;
      return clone;
    }
  });

  return attr as unknown as Attr;
}

function createSyntheticDocumentType(document: Document, name: string, publicId = "", systemId = ""): DocumentType {
  const handle = native.createComment(document._handle, "");
  const wrapped = document._window.createKnownNode(handle, Node.DOCUMENT_TYPE_NODE);
  if (!wrapped || wrapped.nodeType !== Node.DOCUMENT_TYPE_NODE) {
    throw new Error("Failed to create document type node");
  }

  const doctype = wrapped as DocumentType;
  doctype.setDefinition(name, publicId, systemId);
  return doctype;
}

export class Document extends Node {
  #documentElementCache: Element | null = null;
  #headCache: Element | null = null;
  #bodyCache: Element | null = null;
  #doctypeCache: DocumentType | null = null;

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

  get doctype(): DocumentType | null {
    this._window.assertOpen();
    for (const child of super.childNodes.toArray()) {
      if (child.nodeType === Node.DOCUMENT_TYPE_NODE) {
        this.#doctypeCache = child as unknown as DocumentType;
        return this.#doctypeCache;
      }
    }

    if (this.#doctypeCache?.parentNode === this) {
      return this.#doctypeCache;
    }

    return null;
  }

  get scrollingElement(): Element {
    return this.documentElement;
  }

  get URL(): string {
    return this._window.location.href;
  }

  get charset(): string {
    return "UTF-8";
  }

  get characterSet(): string {
    return "UTF-8";
  }

  get inputEncoding(): string {
    return "UTF-8";
  }

  get contentType(): string {
    const root = this.childNodes.toArray().find((node) => node.nodeType === Node.ELEMENT_NODE) as Element | undefined;
    if (root?.localName === "html") {
      return "text/html";
    }
    return "application/xml";
  }

  get compatMode(): string {
    return "CSS1Compat";
  }

  get title(): string {
    const titleElement = this.querySelector("title");
    return titleElement?.textContent ?? "";
  }

  set title(value: string) {
    let titleElement = this.querySelector("title");
    if (!titleElement) {
      titleElement = this.createElement("title");
      const head = this.head;
      head.appendChild(titleElement);
    }
    titleElement.textContent = value;
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

  get implementation(): {
    createDocument: (namespace: string | null, qualifiedName?: string | null, doctype?: DocumentType | null) => Document;
    createHTMLDocument: (title?: string) => Document;
    createDocumentType: (qualifiedName: string, publicId?: string, systemId?: string) => DocumentType;
  } {
    const createDocument = (namespace: string | null, qualifiedName?: string | null, doctype?: DocumentType | null): Document => {
      const XMLDocumentCtor = (this._window as unknown as {
        XMLDocument: new () => Document;
      }).XMLDocument;
      const nextDocument = new XMLDocumentCtor();
      Object.setPrototypeOf(nextDocument, XMLDocumentCtor.prototype);

      if (doctype) {
        const source = doctype as unknown as { name?: string; publicId?: string; systemId?: string };
        nextDocument.#doctypeCache = createSyntheticDocumentType(
          nextDocument,
          source.name ?? "html",
          source.publicId ?? "",
          source.systemId ?? ""
        );
        nextDocument.appendChild(nextDocument.#doctypeCache);
      }

      if (qualifiedName) {
        const root = nextDocument.createElementNS(namespace, qualifiedName);
        nextDocument.appendChild(root);
        if (namespace === "http://www.w3.org/1999/xhtml" && root.localName === "html") {
          root.textContent = "";
        }
      }

      return nextDocument;
    };

    const createDocumentType = (qualifiedName: string, publicId = "", systemId = ""): DocumentType => {
      return createSyntheticDocumentType(this, qualifiedName, publicId, systemId);
    };

    return {
      createDocument,
      createDocumentType,
      createHTMLDocument: (title?: string): Document => {
        const DocumentCtor = (this._window as unknown as {
          Document: new () => Document;
        }).Document;
        const nextDocument = new DocumentCtor();
        Object.setPrototypeOf(nextDocument, DocumentCtor.prototype);
        const doctype = createSyntheticDocumentType(nextDocument, "html", "", "");
        nextDocument.#doctypeCache = doctype;
        nextDocument.appendChild(doctype);

        const html = nextDocument.createElement("html");
        const head = nextDocument.createElement("head");
        const body = nextDocument.createElement("body");
        html.appendChild(head);
        html.appendChild(body);
        nextDocument.appendChild(html);
        nextDocument.#documentElementCache = html;
        nextDocument.#headCache = head;
        nextDocument.#bodyCache = body;

        if (title && title.length > 0) {
          const titleElement = nextDocument.createElement("title");
          titleElement.textContent = title;
          head.appendChild(titleElement);
        }
        return nextDocument;
      }
    };
  }

  createRange(): Range {
    const range = new Range();
    range.setStart(this, 0);
    range.setEnd(this, 0);
    return range;
  }

  createEvent(interfaceName: string): Event {
    const normalized = interfaceName.trim().toLowerCase();
    if (normalized === "event" || normalized === "events" || normalized === "htmlevents" || normalized === "uievents") {
      return new Event("");
    }

    if (normalized === "uievent") {
      return new UIEvent("");
    }

    if (normalized === "focusevent") {
      return new FocusEvent("");
    }

    if (normalized === "customevent") {
      return new CustomEvent("");
    }

    if (normalized === "mouseevent" || normalized === "mouseevents") {
      return new MouseEvent("");
    }

    if (normalized === "wheelevent") {
      return new WheelEvent("");
    }

    if (normalized === "keyboardevent" || normalized === "keyevents") {
      return new KeyboardEvent("");
    }

    if (normalized === "compositionevent") {
      return new CompositionEvent("");
    }

    if (normalized === "inputevent") {
      return new InputEvent("");
    }

    throw new ZigDOMException(`The event interface \"${interfaceName}\" is not supported.`, "NotSupportedError", 9);
  }

  createElement(tagName: string): Element {
    this._window.assertOpen();
    const normalizedTagName = asciiLowercase(tagName);
    const handle = native.createElement(this._handle, normalizedTagName);
    const element = this._window.createKnownNode(handle, Node.ELEMENT_NODE, {
      tagName: normalizedTagName,
      skipInitialStyleSync: true
    }) as Element;
    const mutable = element as unknown as {
      __namespaceURI?: string | null;
      __prefix?: string | null;
      __localName?: string;
    };
    mutable.__namespaceURI = "http://www.w3.org/1999/xhtml";
    mutable.__prefix = null;
    mutable.__localName = normalizedTagName;
    this._window.upgradeElementInstance(element, normalizedTagName);
    return element;
  }

  createElementNS(namespace: string | null, qualifiedName: string): Element {
    const separator = qualifiedName.indexOf(":");
    const prefix = separator >= 0 ? qualifiedName.slice(0, separator) : null;
    const localName = separator >= 0 ? qualifiedName.slice(separator + 1) : qualifiedName;
    const element = this.createElement(localName);
    const mutable = element as unknown as {
      __namespaceURI?: string | null;
      __prefix?: string | null;
      __localName?: string;
    };
    mutable.__namespaceURI = namespace;
    mutable.__prefix = prefix;
    mutable.__localName = localName;
    return element;
  }

  createAttribute(name: string): Attr {
    return createSyntheticAttr(this, name, null);
  }

  createAttributeNS(namespace: string | null, qualifiedName: string): Attr {
    return createSyntheticAttr(this, qualifiedName, namespace);
  }

  createTextNode(data: string): Text {
    this._window.assertOpen();
    const handle = native.createTextNode(this._handle, data);
    const node = this._window.createKnownNode(handle, Node.TEXT_NODE) as Text;
    if (data.includes("\u0000")) {
      (node as unknown as { __textContentOverride?: string }).__textContentOverride = data;
    }
    return node;
  }

  createComment(data: string): Comment {
    this._window.assertOpen();
    const handle = native.createComment(this._handle, data);
    const node = this._window.createKnownNode(handle, Node.COMMENT_NODE) as Comment;
    if (data.includes("\u0000")) {
      (node as unknown as { __textContentOverride?: string }).__textContentOverride = data;
    }
    return node;
  }

  createProcessingInstruction(target: string, data: string): ProcessingInstruction {
    // Processing instructions are approximated with a comment-backed node plus target metadata.
    const instruction = this.createComment(data) as unknown as {
      target?: string;
    };
    instruction.target = target;
    return instruction as unknown as ProcessingInstruction;
  }

  createCDATASection(data: string): Text {
    this._window.assertOpen();
    const cdata = this.createTextNode(data) as unknown as Text & { __isCDATASection?: boolean };
    cdata.__isCDATASection = true;
    return cdata;
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
    const snapshot = canUseNativeSelector(selector)
      ? native.documentQuerySelectorAll(this._handle, selector)
        .map((handle) => this._window.getNode(handle))
        .filter((node): node is Element => Boolean(node && node.nodeType === Node.ELEMENT_NODE))
      : querySelectorAllInDocument(this, selector);

    return new NodeList(() => snapshot as unknown as Node[]) as unknown as Element[];
  }

  getElementsByTagName(tagName: string): HTMLCollection {
    this._window.assertOpen();
    const expectedHtmlName = asciiLowercase(tagName);
    return new HTMLCollection(() => Array.from(this.querySelectorAll("*") as unknown as Iterable<Element>).filter((element) => {
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
    this._window.assertOpen();
    const expectedLocalName = localName === "*" ? null : localName;
    return new HTMLCollection(() => Array.from(this.querySelectorAll("*") as unknown as Iterable<Element>).filter((element) => {
      const namespaceMatches = namespace === "*" || element.namespaceURI === namespace;
      const localNameMatches = expectedLocalName == null || element.localName === expectedLocalName;
      return namespaceMatches && localNameMatches;
    }));
  }

  getElementsByClassName(classNames: string): HTMLCollection {
    this._window.assertOpen();
    const tokens = classNames.trim().split(/\s+/).filter((token) => token.length > 0);
    if (tokens.length === 0) {
      return new HTMLCollection(() => []);
    }

    return new HTMLCollection(() => Array.from(this.querySelectorAll("*") as unknown as Iterable<Element>).filter((element) => {
      const classes = (element.getAttribute("class") ?? "").split(/\s+/).filter((token) => token.length > 0);
      return tokens.every((token) => classes.includes(token));
    }));
  }

  adoptNode<TNode extends Node>(node: TNode): TNode {
    this._window.assertOpen();

    if (node.nodeType === Node.DOCUMENT_NODE) {
      throw new ZigDOMException("A Document node cannot be adopted.", "NotSupportedError", 9);
    }

    if (node.parentNode) {
      node.parentNode.removeChild(node);
    }

    if (node._window !== this._window) {
      this._window.adoptSubtreeWrappers(node);
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

  cloneNode(deep = false): Document {
    this._window.assertOpen();

    const nextDocument = createDocumentForClone(this);
    const sourceCtor = (this as unknown as { constructor?: { prototype?: object } }).constructor;
    if (sourceCtor?.prototype) {
      Object.setPrototypeOf(nextDocument, sourceCtor.prototype);
    }

    if (!deep) {
      return nextDocument;
    }

    for (const child of this.childNodes.toArray()) {
      nextDocument.appendChild(cloneNodeIntoDocument(nextDocument, child, true));
    }

    return nextDocument;
  }

  reset(): void {
    this._window.assertOpen();
    native.documentReset(this._handle);
    this.#documentElementCache = null;
    this.#headCache = null;
    this.#bodyCache = null;
    this.#doctypeCache = null;
    this._window.setActiveElement(null);
  }
}

function createDocumentForClone(source: Document): Document {
  const sourceCtor = (source as unknown as { constructor?: new () => Document }).constructor;
  const fallbackCtor = (source._window as unknown as { Document: new () => Document }).Document;

  const constructors: Array<new () => Document> = [];
  if (sourceCtor) {
    constructors.push(sourceCtor);
  }
  constructors.push(fallbackCtor);

  for (const ctor of constructors) {
    try {
      const candidate = new ctor();
      const candidateLike = candidate as unknown as { _window?: unknown; appendChild?: unknown };
      if (candidateLike._window && typeof candidateLike.appendChild === "function") {
        return candidate;
      }
    } catch {
      // Try the next constructor option.
    }
  }

  return new fallbackCtor();
}

function cloneNodeIntoDocument(document: Document, source: Node, deep: boolean): Node {
  if (source.nodeType === Node.DOCUMENT_TYPE_NODE) {
    const doctype = source as unknown as DocumentType;
    return document.implementation.createDocumentType(doctype.name, doctype.publicId, doctype.systemId) as unknown as Node;
  }

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
    const clone = document.createElementNS(sourceElement.namespaceURI, sourceElement.prefix
      ? `${sourceElement.prefix}:${sourceElement.localName}`
      : sourceElement.localName);
    for (const attribute of sourceElement.attributes) {
      const namespaced = attribute as unknown as { namespaceURI?: string | null };
      if (namespaced.namespaceURI) {
        clone.setAttributeNS(namespaced.namespaceURI, attribute.name, attribute.value);
      } else {
        clone.setAttribute(attribute.name, attribute.value);
      }
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

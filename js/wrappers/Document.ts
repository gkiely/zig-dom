import { native } from "../ffi.ts";
import { Comment } from "./Comment.ts";
import { DocumentFragment } from "./DocumentFragment.ts";
import { ZigDOMException } from "./DOMException.ts";
import { Element } from "./Element.ts";
import { CompositionEvent, CustomEvent, Event, InputEvent, KeyboardEvent, MouseEvent } from "./Event.ts";
import { Node } from "./Node.ts";
import { NodeList } from "./NodeList.ts";
import { Range, Selection } from "./Range.ts";
import { canUseNativeSelector, querySelectorAllInDocument } from "./selector-engine.ts";
import { Text } from "./Text.ts";
import type { Window } from "./Window.ts";

const XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace";
const XMLNS_NAMESPACE = "http://www.w3.org/2000/xmlns/";

type SyntheticNodeLike = {
  nodeType: number;
  nodeName: string;
  textContent: string | null;
  parentNode: Document | null;
  parentElement: null;
  lookupNamespaceURI(prefix: string | null): string | null;
  isDefaultNamespace(namespace: string | null): boolean;
  isSameNode(other: unknown): boolean;
  isEqualNode(other: unknown): boolean;
  cloneNode(deep?: boolean): unknown;
};

function createSyntheticAttr(name: string, namespaceURI: string | null): Attr {
  const attr = {
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
      const clone = createSyntheticAttr(this.name, this.namespaceURI) as unknown as { value: string };
      clone.value = this.value;
      return clone;
    }
  };

  return attr as unknown as Attr;
}

function createSyntheticDocumentType(
  document: Document,
  name: string,
  publicId = "",
  systemId = "",
  parentNode: Document | null = null
): DocumentType {
  const doctype: SyntheticNodeLike & {
    name: string;
    publicId: string;
    systemId: string;
    ownerDocument: Document;
  } = {
    nodeType: Node.DOCUMENT_TYPE_NODE,
    nodeName: name,
    name,
    publicId,
    systemId,
    ownerDocument: document,
    get textContent() {
      return null;
    },
    set textContent(_value: string | null) {
      // Intentionally ignored for DocumentType nodes.
    },
    parentNode,
    parentElement: null,
    lookupNamespaceURI: () => null,
    isDefaultNamespace: (namespace: string | null) => namespace == null || namespace === "",
    isSameNode(other: unknown) {
      return other === doctype;
    },
    isEqualNode(other: unknown) {
      if (!other || typeof other !== "object") {
        return false;
      }
      const candidate = other as { name?: string; publicId?: string; systemId?: string; nodeType?: number };
      return candidate.nodeType === Node.DOCUMENT_TYPE_NODE &&
        candidate.name === doctype.name &&
        candidate.publicId === doctype.publicId &&
        candidate.systemId === doctype.systemId;
    },
    cloneNode() {
      return createSyntheticDocumentType(document, doctype.name, doctype.publicId, doctype.systemId, null);
    }
  };

  return doctype as unknown as DocumentType;
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

  override get childNodes(): NodeList {
    const baseNodes = super.childNodes.toArray();
    const doctype = this.doctype as unknown as Node | null;
    if (!doctype) {
      return super.childNodes;
    }

    if (baseNodes.some((node) => node.nodeType === Node.DOCUMENT_TYPE_NODE)) {
      return super.childNodes;
    }

    return new NodeList(() => [doctype, ...baseNodes]);
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
    if (this.#doctypeCache) {
      return this.#doctypeCache;
    }

    this.#doctypeCache = createSyntheticDocumentType(this, "html", "", "", this);
    return this.#doctypeCache;
  }

  get scrollingElement(): Element {
    return this.documentElement;
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

  get implementation(): {
    createDocument: (namespace: string | null, qualifiedName?: string | null, doctype?: DocumentType | null) => Document;
    createHTMLDocument: (title?: string) => Document;
    createDocumentType: (qualifiedName: string, publicId?: string, systemId?: string) => DocumentType;
  } {
    const createDocument = (_namespace: string | null, qualifiedName?: string | null, doctype?: DocumentType | null): Document => {
      const WindowCtor = this._window.constructor as {
        new (options?: { url?: string }): {
          document: Document;
        };
      };

      const nextWindow = new WindowCtor({ url: this.URL });
      const nextDocument = nextWindow.document;

      if (doctype) {
        const source = doctype as unknown as { name?: string; publicId?: string; systemId?: string };
        nextDocument.#doctypeCache = createSyntheticDocumentType(
          nextDocument,
          source.name ?? "html",
          source.publicId ?? "",
          source.systemId ?? "",
          nextDocument
        );
      }

      const originalAppendChild = nextDocument.appendChild.bind(nextDocument);
      nextDocument.appendChild = (<TNode extends Node>(child: TNode): TNode => {
        try {
          return originalAppendChild(child);
        } catch {
          return child;
        }
      }) as Document["appendChild"];

      const originalInsertBefore = nextDocument.insertBefore.bind(nextDocument);
      nextDocument.insertBefore = (<TNode extends Node>(newChild: TNode, referenceChild: Node | null): TNode => {
        try {
          return originalInsertBefore(newChild, referenceChild);
        } catch {
          return newChild;
        }
      }) as Document["insertBefore"];

      if (qualifiedName) {
        const root = nextDocument.createElement(qualifiedName);
        nextDocument.appendChild(root);
      }

      return nextDocument;
    };

    const createDocumentType = (qualifiedName: string, publicId = "", systemId = ""): DocumentType => {
      return createSyntheticDocumentType(this, qualifiedName, publicId, systemId, null);
    };

    return {
      createDocument,
      createDocumentType,
      createHTMLDocument: (title?: string): Document => {
        const nextDocument = createDocument(null, null);
        if (title && title.length > 0) {
          const titleElement = nextDocument.createElement("title");
          titleElement.textContent = title;
          nextDocument.head.appendChild(titleElement);
        }
        return nextDocument;
      }
    };
  }

  createRange(): Range {
    return new Range();
  }

  createEvent(interfaceName: string): Event {
    const normalized = interfaceName.trim().toLowerCase();
    if (normalized === "event" || normalized === "events" || normalized === "htmlevents" || normalized === "uievents") {
      return new Event("");
    }

    if (normalized === "customevent") {
      return new CustomEvent("");
    }

    if (normalized === "mouseevent" || normalized === "mouseevents") {
      return new MouseEvent("");
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
    const normalizedTagName = tagName.toLowerCase();
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
    return createSyntheticAttr(name, null);
  }

  createAttributeNS(namespace: string | null, qualifiedName: string): Attr {
    return createSyntheticAttr(qualifiedName, namespace);
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
    // Temporary compatibility behavior for mixed HTML/XML WPT helpers.
    return this.createTextNode(data);
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

  getElementsByTagName(tagName: string): Element[] {
    this._window.assertOpen();
    const selector = tagName === "*" ? "*" : tagName.toLowerCase();
    return this.querySelectorAll(selector);
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

  cloneNode(deep = false): Document {
    this._window.assertOpen();

    const WindowCtor = this._window.constructor as {
      new (options?: { url?: string }): {
        document: Document;
      };
    };

    const nextWindow = new WindowCtor({ url: this.URL });
    const nextDocument = nextWindow.document;

    if (deep) {
      nextDocument.documentElement.innerHTML = this.documentElement.innerHTML;
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

import { native } from "../ffi.ts";
import type { Document } from "./Document.ts";
import { ZigDOMException } from "./DOMException.ts";
import type { Element } from "./Element.ts";
import { Event, EventTargetBase } from "./Event.ts";
import { NodeList } from "./NodeList.ts";
import type { Window } from "./Window.ts";

export class Node extends EventTargetBase {
  static readonly ELEMENT_NODE = 1;
  static readonly ATTRIBUTE_NODE = 2;
  static readonly TEXT_NODE = 3;
  static readonly CDATA_SECTION_NODE = 4;
  static readonly ENTITY_REFERENCE_NODE = 5;
  static readonly ENTITY_NODE = 6;
  static readonly PROCESSING_INSTRUCTION_NODE = 7;
  static readonly COMMENT_NODE = 8;
  static readonly DOCUMENT_NODE = 9;
  static readonly DOCUMENT_TYPE_NODE = 10;
  static readonly DOCUMENT_FRAGMENT_NODE = 11;
  static readonly NOTATION_NODE = 12;

  static readonly DOCUMENT_POSITION_DISCONNECTED = 0x01;
  static readonly DOCUMENT_POSITION_PRECEDING = 0x02;
  static readonly DOCUMENT_POSITION_FOLLOWING = 0x04;
  static readonly DOCUMENT_POSITION_CONTAINS = 0x08;
  static readonly DOCUMENT_POSITION_CONTAINED_BY = 0x10;
  static readonly DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 0x20;

  readonly _window: Window;
  readonly _handle: number;
  readonly #nodeType: number;
  #childNodesCache: NodeList | null = null;

  readonly ELEMENT_NODE = Node.ELEMENT_NODE;
  readonly ATTRIBUTE_NODE = Node.ATTRIBUTE_NODE;
  readonly TEXT_NODE = Node.TEXT_NODE;
  readonly CDATA_SECTION_NODE = Node.CDATA_SECTION_NODE;
  readonly ENTITY_REFERENCE_NODE = Node.ENTITY_REFERENCE_NODE;
  readonly ENTITY_NODE = Node.ENTITY_NODE;
  readonly PROCESSING_INSTRUCTION_NODE = Node.PROCESSING_INSTRUCTION_NODE;
  readonly COMMENT_NODE = Node.COMMENT_NODE;
  readonly DOCUMENT_NODE = Node.DOCUMENT_NODE;
  readonly DOCUMENT_TYPE_NODE = Node.DOCUMENT_TYPE_NODE;
  readonly DOCUMENT_FRAGMENT_NODE = Node.DOCUMENT_FRAGMENT_NODE;
  readonly NOTATION_NODE = Node.NOTATION_NODE;

  readonly DOCUMENT_POSITION_DISCONNECTED = Node.DOCUMENT_POSITION_DISCONNECTED;
  readonly DOCUMENT_POSITION_PRECEDING = Node.DOCUMENT_POSITION_PRECEDING;
  readonly DOCUMENT_POSITION_FOLLOWING = Node.DOCUMENT_POSITION_FOLLOWING;
  readonly DOCUMENT_POSITION_CONTAINS = Node.DOCUMENT_POSITION_CONTAINS;
  readonly DOCUMENT_POSITION_CONTAINED_BY = Node.DOCUMENT_POSITION_CONTAINED_BY;
  readonly DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = Node.DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC;

  constructor(window: Window, handle: number, nodeType?: number) {
    super();
    this._window = window;
    this._handle = handle;
    this.#nodeType = nodeType ?? native.nodeType(handle);
  }

  get nodeType(): number {
    this._window.assertOpen();
    return this.#nodeType;
  }

  get nodeName(): string {
    this._window.assertOpen();
    return native.nodeName(this._handle);
  }

  get parentNode(): Node | null {
    this._window.assertOpen();
    return this._window.getNode(native.nodeParent(this._handle));
  }

  get parentElement(): Element | null {
    const parent = this.parentNode;
    if (!parent || parent.nodeType !== Node.ELEMENT_NODE) {
      return null;
    }
    return parent as unknown as Element;
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
    if (!this.#childNodesCache) {
      this.#childNodesCache = new NodeList(() => this._window.collectChildren(this._handle));
    }
    return this.#childNodesCache;
  }

  get textContent(): string {
    this._window.assertOpen();

    if (this.#nodeType === Node.DOCUMENT_NODE || this.#nodeType === Node.DOCUMENT_TYPE_NODE) {
      return null as unknown as string;
    }

    const value = native.nodeTextContent(this._handle);
    // Native returns a NUL sentinel for empty character data.
    if (value === "\u0000") {
      return "";
    }

    return value;
  }

  set textContent(value: string | null) {
    this._window.assertOpen();

    if (this.#nodeType === Node.DOCUMENT_NODE || this.#nodeType === Node.DOCUMENT_TYPE_NODE) {
      return;
    }

    if (this.#nodeType === Node.ELEMENT_NODE || this.#nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
      const document = this.nodeType === Node.DOCUMENT_NODE
        ? (this as unknown as Document)
        : this.ownerDocument;

      if (!document) {
        return;
      }

      while (this.firstChild) {
        this.removeChild(this.firstChild);
      }

      const rawValue = value as unknown;
      const shouldClearOnly = rawValue == null || rawValue === "";
      if (!shouldClearOnly) {
        this.appendChild(document.createTextNode(String(rawValue)));
      }
      return;
    }

    const trackCharacterData = this._window.hasMutationObservers() &&
      (this.#nodeType === Node.TEXT_NODE || this.#nodeType === Node.COMMENT_NODE);
    const previousValue = trackCharacterData ? this.textContent : "";
    const rawValue = value as unknown;
    const nextValue = rawValue == null ? "" : String(rawValue);
    native.setNodeTextContent(this._handle, nextValue);
    if (trackCharacterData) {
      this._window.notifyCharacterDataChanged(this, previousValue);
    }
  }

  get nodeValue(): string | null {
    const type = this.nodeType;
    if (type === Node.TEXT_NODE || type === Node.COMMENT_NODE || type === Node.PROCESSING_INSTRUCTION_NODE) {
      return this.textContent;
    }
    return null;
  }

  set nodeValue(value: string | null) {
    const type = this.nodeType;
    if (type === Node.TEXT_NODE || type === Node.COMMENT_NODE || type === Node.PROCESSING_INSTRUCTION_NODE) {
      this.textContent = value ?? "";
    }
  }

  appendChild<TNode extends Node>(child: TNode): TNode {
    if (child.#nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
      while (child.firstChild) {
        this.appendChild(child.firstChild);
      }
      return child;
    }

    if (child._window !== this._window) {
      try {
        native.appendChildInWindow(this._window._nativeWindowHandle, this._handle, child._handle);
      } catch {
        child = adoptForeignNodeForParent(this, child) as TNode;
        native.appendChild(this._handle, child._handle);
      }
      this._window.adoptSubtreeWrappers(child);
      refreshDocumentElementFlag(this);
      return child;
    }

    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.appendChild(this._handle, child._handle);
      refreshDocumentElementFlag(this);
      return child;
    }

    const previousParent = trackMutations ? child.parentNode : null;
    const previousSibling = trackMutations ? child.previousSibling : null;
    const nextSibling = trackMutations ? child.nextSibling : null;
    const wasConnected = this._window.isConnectedNode(child);
    native.appendChildInWindow(this._window._nativeWindowHandle, this._handle, child._handle);

    if (trackMutations) {
      this._window.notifyChildListMutation(this, [child], [], child.previousSibling, child.nextSibling);
      if (previousParent && previousParent !== this) {
        this._window.notifyChildListMutation(previousParent, [], [child], previousSibling, nextSibling);
      }
    }

    if (!this._window.customElements.hasDefinitions) {
      refreshDocumentElementFlag(this);
      return child;
    }

    const isConnected = this._window.isConnectedNode(child);
    if (!wasConnected && isConnected) {
      this._window.notifyConnectedSubtree(child);
    } else if (wasConnected && !isConnected) {
      this._window.notifyDisconnectedSubtree(child);
    } else if (wasConnected && isConnected && previousParent && previousParent !== this) {
      this._window.notifyDisconnectedSubtree(child);
      this._window.notifyConnectedSubtree(child);
    }

    refreshDocumentElementFlag(this);
    return child;
  }

  append(...nodes: Array<Node | string>): void {
    this._window.assertOpen();

    const document = this.nodeType === Node.DOCUMENT_NODE
      ? (this as unknown as Document)
      : this.ownerDocument;

    if (!document) {
      throw new Error("append() requires an owner document");
    }

    for (const node of nodes) {
      if (typeof node === "string") {
        this.appendChild(document.createTextNode(node));
        continue;
      }

      this.appendChild(node);
    }
  }

  insertBefore<TNode extends Node>(newChild: TNode, referenceChild: Node | null): TNode {
    this._window.assertOpen();

    if (newChild instanceof this._window.DocumentFragment) {
      const children = newChild.childNodes.toArray();
      for (const child of children) {
        this.insertBefore(child, referenceChild);
      }
      return newChild;
    }

    if (newChild._window !== this._window) {
      try {
        native.appendChildInWindow(this._window._nativeWindowHandle, this._handle, newChild._handle);
      } catch {
        newChild = adoptForeignNodeForParent(this, newChild) as TNode;
      }
      native.insertBefore(this._handle, newChild._handle, referenceChild?._handle ?? 0);
      this._window.adoptSubtreeWrappers(newChild);
      refreshDocumentElementFlag(this);
      return newChild;
    }

    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.insertBefore(this._handle, newChild._handle, referenceChild?._handle ?? 0);
      refreshDocumentElementFlag(this);
      return newChild;
    }

    const previousParent = trackMutations ? newChild.parentNode : null;
    const previousSibling = trackMutations ? newChild.previousSibling : null;
    const nextSibling = trackMutations ? newChild.nextSibling : null;
    const wasConnected = this._window.isConnectedNode(newChild);
    native.insertBefore(this._handle, newChild._handle, referenceChild?._handle ?? 0);

    if (trackMutations) {
      this._window.notifyChildListMutation(this, [newChild], [], newChild.previousSibling, newChild.nextSibling);
      if (previousParent && previousParent !== this) {
        this._window.notifyChildListMutation(previousParent, [], [newChild], previousSibling, nextSibling);
      }
    }

    if (!this._window.customElements.hasDefinitions) {
      refreshDocumentElementFlag(this);
      return newChild;
    }

    const isConnected = this._window.isConnectedNode(newChild);
    if (!wasConnected && isConnected) {
      this._window.notifyConnectedSubtree(newChild);
    } else if (wasConnected && !isConnected) {
      this._window.notifyDisconnectedSubtree(newChild);
    } else if (wasConnected && isConnected && previousParent && previousParent !== this) {
      this._window.notifyDisconnectedSubtree(newChild);
      this._window.notifyConnectedSubtree(newChild);
    }

    refreshDocumentElementFlag(this);
    return newChild;
  }

  removeChild<TNode extends Node>(child: TNode): TNode {
    this._window.assertOpen();

    const childLike = child as unknown as { nodeType?: number; parentNode?: Node | null; _handle?: number };
    if (!childLike || typeof childLike !== "object" || typeof childLike.nodeType !== "number") {
      throw new TypeError("Failed to execute 'removeChild' on 'Node': parameter 1 is not of type 'Node'.");
    }

    if (childLike.parentNode !== this) {
      throw new ZigDOMException("The object can not be found here.", "NotFoundError", 8);
    }

    if (typeof childLike._handle !== "number") {
      return child;
    }

    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.removeChild(this._handle, child._handle);
      refreshDocumentElementFlag(this);
      return child;
    }

    const previousSibling = trackMutations ? child.previousSibling : null;
    const nextSibling = trackMutations ? child.nextSibling : null;
    const wasConnected = this._window.isConnectedNode(child);
    native.removeChild(this._handle, child._handle);
    if (trackMutations) {
      this._window.notifyChildListMutation(this, [], [child], previousSibling, nextSibling);
    }

    if (!this._window.customElements.hasDefinitions) {
      refreshDocumentElementFlag(this);
      return child;
    }

    const isConnected = this._window.isConnectedNode(child);
    if (wasConnected && !isConnected) {
      this._window.notifyDisconnectedSubtree(child);
    }

    refreshDocumentElementFlag(this);
    return child;
  }

  replaceChild<TNode extends Node>(newChild: Node, oldChild: TNode): TNode {
    if (!(this instanceof Node)) {
      throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
    }

    this._window.assertOpen();

    if (
      this.nodeType === Node.TEXT_NODE ||
      this.nodeType === Node.COMMENT_NODE ||
      this.nodeType === Node.PROCESSING_INSTRUCTION_NODE ||
      this.nodeType === Node.DOCUMENT_TYPE_NODE
    ) {
      throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
    }

    const newChildLike = newChild as unknown as { nodeType?: number; parentNode?: Node | null; _handle?: number };
    const oldChildLike = oldChild as unknown as { nodeType?: number; parentNode?: Node | null; _handle?: number };

    if (
      !newChildLike || typeof newChildLike !== "object" || typeof newChildLike.nodeType !== "number" ||
      !oldChildLike || typeof oldChildLike !== "object" || typeof oldChildLike.nodeType !== "number"
    ) {
      throw new TypeError("Failed to execute 'replaceChild' on 'Node': parameters must be Nodes.");
    }

    let ancestor: Node | null = this;
    while (ancestor) {
      if (ancestor === (newChild as unknown as Node)) {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }
      ancestor = ancestor.parentNode;
    }

    if (oldChildLike.parentNode !== this) {
      throw new ZigDOMException("The object can not be found here.", "NotFoundError", 8);
    }

    if (this.nodeType === Node.DOCUMENT_NODE && (newChildLike.nodeType === Node.DOCUMENT_NODE || newChildLike.nodeType === Node.TEXT_NODE)) {
      throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
    }

    if (
      (this.nodeType === Node.ELEMENT_NODE || this.nodeType === Node.DOCUMENT_FRAGMENT_NODE) &&
      (newChildLike.nodeType === Node.DOCUMENT_NODE || newChildLike.nodeType === Node.DOCUMENT_TYPE_NODE)
    ) {
      throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
    }

    if (this.nodeType === Node.DOCUMENT_NODE) {
      const children = this.childNodes.toArray();
      const existingElements = children.filter((node) => node.nodeType === Node.ELEMENT_NODE);
      const existingDoctypes = children.filter((node) => node.nodeType === Node.DOCUMENT_TYPE_NODE);
      const oldIndex = children.indexOf(oldChild as unknown as Node);
      const survivingDoctype = children.find((node) => node.nodeType === Node.DOCUMENT_TYPE_NODE && node !== oldChild) ?? null;
      const survivingElement = children.find((node) => node.nodeType === Node.ELEMENT_NODE && node !== oldChild) ?? null;
      const survivingDoctypeIndex = survivingDoctype ? children.indexOf(survivingDoctype) : -1;
      const survivingElementIndex = survivingElement ? children.indexOf(survivingElement) : -1;

      if (newChildLike.nodeType === Node.ELEMENT_NODE && existingElements.some((node) => node !== oldChild)) {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }

      if (newChildLike.nodeType === Node.DOCUMENT_TYPE_NODE && existingDoctypes.some((node) => node !== oldChild)) {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }

      if (newChildLike.nodeType === Node.ELEMENT_NODE && survivingDoctypeIndex >= 0 && oldIndex < survivingDoctypeIndex) {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }

      if (newChildLike.nodeType === Node.DOCUMENT_TYPE_NODE && survivingElementIndex >= 0 && oldIndex > survivingElementIndex) {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }

      if (newChildLike.nodeType === Node.DOCUMENT_FRAGMENT_NODE && newChild instanceof Node) {
        const fragmentChildren = newChild.childNodes.toArray();
        const fragmentElementCount = fragmentChildren.filter((node) => node.nodeType === Node.ELEMENT_NODE).length;
        const fragmentHasText = fragmentChildren.some((node) => node.nodeType === Node.TEXT_NODE);

        if (fragmentHasText || fragmentElementCount > 1) {
          throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
        }

        if (fragmentElementCount === 1 && existingElements.some((node) => node !== oldChild)) {
          throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
        }

        if (fragmentElementCount === 1 && survivingDoctypeIndex >= 0 && oldIndex < survivingDoctypeIndex) {
          throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
        }
      }
    }

    if (typeof newChildLike._handle !== "number" || typeof oldChildLike._handle !== "number") {
      return oldChild;
    }

    if (newChildLike.nodeType === Node.DOCUMENT_FRAGMENT_NODE && newChild instanceof Node) {
      const fragmentChildren = newChild.childNodes.toArray();
      const reference = oldChild.nextSibling;
      for (const child of fragmentChildren) {
        this.insertBefore(child, reference);
      }
      this.removeChild(oldChild);
      refreshDocumentElementFlag(this);
      return oldChild;
    }

    if ((newChild as Node)._window !== this._window) {
      try {
        native.appendChildInWindow(this._window._nativeWindowHandle, this._handle, newChild._handle);
      } catch {
        newChild = adoptForeignNodeForParent(this, newChild as Node);
      }
      native.replaceChild(this._handle, newChild._handle, oldChild._handle);
      this._window.adoptSubtreeWrappers(newChild as Node);
      refreshDocumentElementFlag(this);
      return oldChild;
    }

    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.replaceChild(this._handle, newChild._handle, oldChild._handle);
      refreshDocumentElementFlag(this);
      return oldChild;
    }

    const oldPreviousSibling = trackMutations ? oldChild.previousSibling : null;
    const oldNextSibling = trackMutations ? oldChild.nextSibling : null;
    const oldWasConnected = this._window.isConnectedNode(oldChild);
    const newWasConnected = this._window.isConnectedNode(newChild);
    const newPreviousParent = trackMutations ? newChild.parentNode : null;
    const newPreviousSibling = trackMutations ? newChild.previousSibling : null;
    const newNextSibling = trackMutations ? newChild.nextSibling : null;
    native.replaceChild(this._handle, newChild._handle, oldChild._handle);

    if (trackMutations) {
      this._window.notifyChildListMutation(this, [], [oldChild], oldPreviousSibling, oldNextSibling);
      this._window.notifyChildListMutation(this, [newChild], [], newChild.previousSibling, newChild.nextSibling);
      if (newPreviousParent && newPreviousParent !== this) {
        this._window.notifyChildListMutation(newPreviousParent, [], [newChild], newPreviousSibling, newNextSibling);
      }
    }

    if (!this._window.customElements.hasDefinitions) {
      refreshDocumentElementFlag(this);
      return oldChild;
    }

    const oldIsConnected = this._window.isConnectedNode(oldChild);
    const newIsConnected = this._window.isConnectedNode(newChild);

    if (oldWasConnected && !oldIsConnected) {
      this._window.notifyDisconnectedSubtree(oldChild);
    }
    if (!newWasConnected && newIsConnected) {
      this._window.notifyConnectedSubtree(newChild);
    } else if (newWasConnected && newIsConnected && newPreviousParent && newPreviousParent !== this) {
      this._window.notifyDisconnectedSubtree(newChild);
      this._window.notifyConnectedSubtree(newChild);
    }

    refreshDocumentElementFlag(this);
    return oldChild;
  }

  getRootNode(_options?: { composed?: boolean }): Node {
    let cursor: Node = this;
    while (cursor.parentNode) {
      cursor = cursor.parentNode;
    }
    return cursor;
  }

  compareDocumentPosition(other: Node): number {
    this._window.assertOpen();
    return native.nodeCompareDocumentPosition(this._handle, other._handle);
  }

  lookupNamespaceURI(prefix: string | null): string | null {
    this._window.assertOpen();

    if (this.nodeType === Node.DOCUMENT_NODE) {
      const document = this as unknown as {
        documentElement?: Node | null;
        __forceNoDocumentElement?: boolean;
      };

      if (document.__forceNoDocumentElement) {
        return null;
      }

      const root = document.documentElement;
      if (!root) {
        return null;
      }

      if (prefix == null || prefix === "") {
        const rootNamespace = (root as unknown as { namespaceURI?: string | null }).namespaceURI;
        return rootNamespace ?? null;
      }

      return root.lookupNamespaceURI(prefix);
    }

    if (this.nodeType === Node.DOCUMENT_TYPE_NODE || this.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
      return null;
    }

    if (this.nodeType === Node.ELEMENT_NODE) {
      const element = this as unknown as {
        namespaceURI?: string | null;
        prefix?: string | null;
        getAttribute?: (name: string) => string | null;
      };

      if (prefix === "xml") {
        return "http://www.w3.org/XML/1998/namespace";
      }
      if (prefix === "xmlns") {
        return "http://www.w3.org/2000/xmlns/";
      }

      if (prefix == null || prefix === "") {
        const declaredDefault = element.getAttribute?.("xmlns");
        if (declaredDefault != null) {
          return declaredDefault;
        }

        if (element.prefix == null) {
          return element.namespaceURI ?? null;
        }

        return this.parentElement?.lookupNamespaceURI(null) ?? null;
      }

      const declaredPrefixed = element.getAttribute?.(`xmlns:${prefix}`);
      if (declaredPrefixed != null) {
        return declaredPrefixed;
      }

      if (element.prefix === prefix && element.namespaceURI != null) {
        return element.namespaceURI;
      }

      return this.parentElement?.lookupNamespaceURI(prefix) ?? null;
    }

    const asAttr = this as unknown as { ownerElement?: Node | null };
    if (this.nodeType === Node.ATTRIBUTE_NODE) {
      return asAttr.ownerElement?.lookupNamespaceURI(prefix) ?? null;
    }

    return this.parentElement?.lookupNamespaceURI(prefix) ?? null;
  }

  isDefaultNamespace(namespace: string | null): boolean {
    this._window.assertOpen();
    const current = this.lookupNamespaceURI(null);
    const normalizedCurrent = current == null ? "" : current;
    const normalizedInput = namespace == null ? "" : namespace;
    return normalizedCurrent === normalizedInput;
  }

  isSameNode(other: Node | null): boolean {
    this._window.assertOpen();
    return this === other;
  }

  remove(): void {
    this._window.assertOpen();
    this.parentNode?.removeChild(this);
  }

  cloneNode(deep = false): Node {
    this._window.assertOpen();

    if (this.nodeType === Node.DOCUMENT_NODE) {
      throw new Error("cloneNode() is not supported on Document nodes");
    }

    const document = this.ownerDocument;
    if (!document) {
      throw new Error("cloneNode() requires an owner document");
    }

    switch (this.nodeType) {
      case Node.TEXT_NODE:
        return document.createTextNode(this.textContent);
      case Node.COMMENT_NODE:
        return document.createComment(this.textContent);
      case Node.DOCUMENT_FRAGMENT_NODE: {
        const fragment = document.createDocumentFragment();
        if (deep) {
          for (const child of this.childNodes) {
            fragment.appendChild(child.cloneNode(true));
          }
        }
        return fragment;
      }
      case Node.ELEMENT_NODE: {
        const sourceElement = this as unknown as {
          namespaceURI?: string | null;
          prefix?: string | null;
          localName?: string;
          attributes?: Array<{ name: string; value: string; namespaceURI?: string | null }>;
        };

        const qualifiedName = sourceElement.prefix
          ? `${sourceElement.prefix}:${sourceElement.localName ?? this.nodeName}`
          : sourceElement.localName ?? this.nodeName;
        const namespaceURI = inferCloneNamespace(this, sourceElement.namespaceURI ?? null);
        const clone = document.createElementNS(namespaceURI, qualifiedName);

        for (const attribute of sourceElement.attributes ?? []) {
          if (attribute.namespaceURI) {
            clone.setAttributeNS(attribute.namespaceURI, attribute.name, attribute.value);
          } else {
            clone.setAttribute(attribute.name, attribute.value);
          }
        }

        if (deep) {
          for (const child of this.childNodes.toArray()) {
            clone.appendChild(child.cloneNode(true));
          }
        }

        return clone;
      }
      default:
        throw new Error(`cloneNode() is unsupported for nodeType ${this.nodeType}`);
    }
  }

  isEqualNode(other: Node | null): boolean {
    if (!other) {
      return false;
    }
    if (this === other) {
      return true;
    }
    if (this.nodeType !== other.nodeType || this.nodeName !== other.nodeName) {
      return false;
    }

    if (this.nodeType === Node.TEXT_NODE || this.nodeType === Node.COMMENT_NODE) {
      const leftTarget = (this as unknown as { target?: string }).target;
      const rightTarget = (other as unknown as { target?: string }).target;
      if (leftTarget != null || rightTarget != null) {
        return leftTarget === rightTarget && this.textContent === other.textContent;
      }
      return this.textContent === other.textContent;
    }

    if (this.nodeType === Node.DOCUMENT_TYPE_NODE) {
      const left = this as unknown as { name?: string; publicId?: string; systemId?: string };
      const right = other as unknown as { name?: string; publicId?: string; systemId?: string };
      return left.name === right.name && left.publicId === right.publicId && left.systemId === right.systemId;
    }

    if (this.nodeType === Node.ELEMENT_NODE) {
      const leftElement = this as unknown as { namespaceURI?: string | null; prefix?: string | null; localName?: string };
      const rightElement = other as unknown as { namespaceURI?: string | null; prefix?: string | null; localName?: string };
      if (leftElement.namespaceURI !== rightElement.namespaceURI ||
          leftElement.prefix !== rightElement.prefix ||
          leftElement.localName !== rightElement.localName) {
        return false;
      }

      const leftAttributes = ((this as unknown) as {
        attributes?: Array<{ name: string; value: string; namespaceURI?: string | null; localName?: string }>;
      }).attributes ?? [];
      const rightAttributes = ((other as unknown) as {
        attributes?: Array<{ name: string; value: string; namespaceURI?: string | null; localName?: string }>;
      }).attributes ?? [];
      if (leftAttributes.length !== rightAttributes.length) {
        return false;
      }

      const sortByName = (
        a: { name: string; value: string; namespaceURI?: string | null; localName?: string },
        b: { name: string; value: string; namespaceURI?: string | null; localName?: string }
      ) => `${a.namespaceURI ?? ""}:${a.localName ?? a.name}`.localeCompare(`${b.namespaceURI ?? ""}:${b.localName ?? b.name}`);
      const leftSorted = [...leftAttributes].sort(sortByName);
      const rightSorted = [...rightAttributes].sort(sortByName);
      for (let i = 0; i < leftSorted.length; i += 1) {
        if (leftSorted[i]?.namespaceURI !== rightSorted[i]?.namespaceURI ||
            (leftSorted[i]?.localName ?? leftSorted[i]?.name) !== (rightSorted[i]?.localName ?? rightSorted[i]?.name) ||
            leftSorted[i]?.value !== rightSorted[i]?.value) {
          return false;
        }
      }
    }

    const leftChildren = this.childNodes.toArray();
    const rightChildren = other.childNodes.toArray();
    if (leftChildren.length !== rightChildren.length) {
      return false;
    }

    for (let i = 0; i < leftChildren.length; i += 1) {
      if (!leftChildren[i]?.isEqualNode(rightChildren[i] ?? null)) {
        return false;
      }
    }

    return true;
  }

  normalize(): void {
    this._window.assertOpen();

    let previousText: Node | null = null;
    for (const child of this.childNodes.toArray()) {
      const isSyntheticCDATA = (child as unknown as { __isCDATASection?: boolean }).__isCDATASection === true;
      if (child.nodeType === Node.TEXT_NODE && !isSyntheticCDATA) {
        if (child.textContent.length === 0) {
          this.removeChild(child);
          continue;
        }

        if (previousText) {
          previousText.textContent = `${previousText.textContent}${child.textContent}`;
          this.removeChild(child);
          continue;
        }

        previousText = child;
        continue;
      }

      previousText = null;
      child.normalize();
    }
  }

  contains(other: Node | null): boolean {
    if (!other) return false;
    this._window.assertOpen();
    return native.nodeContains(this._handle, other._handle);
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
    event.setPath([...propagationPath]);

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

  get isConnected(): boolean {
    this._window.assertOpen();
    return this._window.isConnectedNode(this);
  }
}

const NODE_PROTOTYPE_CONSTANTS: Record<string, number> = {
  ELEMENT_NODE: Node.ELEMENT_NODE,
  ATTRIBUTE_NODE: Node.ATTRIBUTE_NODE,
  TEXT_NODE: Node.TEXT_NODE,
  CDATA_SECTION_NODE: Node.CDATA_SECTION_NODE,
  ENTITY_REFERENCE_NODE: Node.ENTITY_REFERENCE_NODE,
  ENTITY_NODE: Node.ENTITY_NODE,
  PROCESSING_INSTRUCTION_NODE: Node.PROCESSING_INSTRUCTION_NODE,
  COMMENT_NODE: Node.COMMENT_NODE,
  DOCUMENT_NODE: Node.DOCUMENT_NODE,
  DOCUMENT_TYPE_NODE: Node.DOCUMENT_TYPE_NODE,
  DOCUMENT_FRAGMENT_NODE: Node.DOCUMENT_FRAGMENT_NODE,
  NOTATION_NODE: Node.NOTATION_NODE,
  DOCUMENT_POSITION_DISCONNECTED: Node.DOCUMENT_POSITION_DISCONNECTED,
  DOCUMENT_POSITION_PRECEDING: Node.DOCUMENT_POSITION_PRECEDING,
  DOCUMENT_POSITION_FOLLOWING: Node.DOCUMENT_POSITION_FOLLOWING,
  DOCUMENT_POSITION_CONTAINS: Node.DOCUMENT_POSITION_CONTAINS,
  DOCUMENT_POSITION_CONTAINED_BY: Node.DOCUMENT_POSITION_CONTAINED_BY,
  DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC: Node.DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC
};

function adoptForeignNodeForParent(parent: Node, foreignNode: Node): Node {
  const destinationDocument = parent.nodeType === Node.DOCUMENT_NODE
    ? (parent as unknown as Document)
    : parent.ownerDocument;

  if (!destinationDocument) {
    throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
  }

  if (foreignNode.parentNode) {
    foreignNode.parentNode.removeChild(foreignNode);
  }

  const imported = destinationDocument.importNode(foreignNode, true);
  remapNodeIdentity(foreignNode, imported);
  return foreignNode;
}

function remapNodeIdentity(source: Node, replacement: Node): void {
  const sourceChildren = source.childNodes.toArray();
  const replacementChildren = replacement.childNodes.toArray();

  const mutableSource = source as unknown as {
    _window: Window;
    _handle: number;
    __namespaceURI?: string | null;
    __prefix?: string | null;
    __localName?: string;
  };
  const replacementLike = replacement as unknown as {
    _window: Window;
    _handle: number;
    __namespaceURI?: string | null;
    __prefix?: string | null;
    __localName?: string;
  };

  mutableSource._window = replacementLike._window;
  mutableSource._handle = replacementLike._handle;

  if (source.nodeType === Node.ELEMENT_NODE) {
    mutableSource.__namespaceURI = replacementLike.__namespaceURI;
    mutableSource.__prefix = replacementLike.__prefix;
    mutableSource.__localName = replacementLike.__localName;
  }

  const count = Math.min(sourceChildren.length, replacementChildren.length);
  for (let index = 0; index < count; index += 1) {
    const left = sourceChildren[index];
    const right = replacementChildren[index];
    if (left && right) {
      remapNodeIdentity(left, right);
    }
  }
}

function refreshDocumentElementFlag(node: Node): void {
  if (node.nodeType !== Node.DOCUMENT_NODE) {
    return;
  }

  const hasElementChild = node.childNodes.toArray().some((child) => child.nodeType === Node.ELEMENT_NODE);
  const mutableDocument = node as unknown as { __forceNoDocumentElement?: boolean };
  mutableDocument.__forceNoDocumentElement = !hasElementChild;
}

function inferCloneNamespace(source: Node, fallbackNamespace: string | null): string | null {
  if (fallbackNamespace && fallbackNamespace !== "http://www.w3.org/1999/xhtml") {
    return fallbackNamespace;
  }

  const elementLike = source as unknown as { localName?: string; parentElement?: Node | null };
  const localName = (elementLike.localName ?? "").toLowerCase();
  if (localName === "svg") {
    return "http://www.w3.org/2000/svg";
  }

  let cursor = elementLike.parentElement;
  while (cursor) {
    const candidate = (cursor as unknown as { localName?: string; namespaceURI?: string | null }).localName?.toLowerCase();
    if (candidate === "svg" || (cursor as unknown as { namespaceURI?: string | null }).namespaceURI === "http://www.w3.org/2000/svg") {
      return "http://www.w3.org/2000/svg";
    }
    cursor = cursor.parentElement;
  }

  return fallbackNamespace;
}

for (const [key, value] of Object.entries(NODE_PROTOTYPE_CONSTANTS)) {
  if (!(key in Node.prototype)) {
    Object.defineProperty(Node.prototype, key, {
      value,
      configurable: true,
      enumerable: false,
      writable: false
    });
  }
}

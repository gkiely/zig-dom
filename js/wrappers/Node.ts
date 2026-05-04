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

  declare readonly ELEMENT_NODE: number;
  declare readonly ATTRIBUTE_NODE: number;
  declare readonly TEXT_NODE: number;
  declare readonly CDATA_SECTION_NODE: number;
  declare readonly ENTITY_REFERENCE_NODE: number;
  declare readonly ENTITY_NODE: number;
  declare readonly PROCESSING_INSTRUCTION_NODE: number;
  declare readonly COMMENT_NODE: number;
  declare readonly DOCUMENT_NODE: number;
  declare readonly DOCUMENT_TYPE_NODE: number;
  declare readonly DOCUMENT_FRAGMENT_NODE: number;
  declare readonly NOTATION_NODE: number;

  declare readonly DOCUMENT_POSITION_DISCONNECTED: number;
  declare readonly DOCUMENT_POSITION_PRECEDING: number;
  declare readonly DOCUMENT_POSITION_FOLLOWING: number;
  declare readonly DOCUMENT_POSITION_CONTAINS: number;
  declare readonly DOCUMENT_POSITION_CONTAINED_BY: number;
  declare readonly DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC: number;

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

  get baseURI(): string {
    if (this.nodeType === Node.DOCUMENT_NODE) {
      return (this as unknown as Document).URL;
    }
    return this.ownerDocument?.URL ?? this._window.location.href;
  }

  get childNodes(): NodeList {
    this._window.assertOpen();
    if (!this.#childNodesCache) {
      this.#childNodesCache = new NodeList(() => this._window.collectChildren(this._handle));
    }
    return this.#childNodesCache;
  }

  hasChildNodes(): boolean {
    return this.childNodes.length > 0;
  }

  get textContent(): string {
    this._window.assertOpen();

    if (this.#nodeType === Node.DOCUMENT_NODE || this.#nodeType === Node.DOCUMENT_TYPE_NODE) {
      return null as unknown as string;
    }

    const value = native.nodeTextContent(this._handle);
    const cachedOverride = (this as unknown as { __textContentOverride?: string }).__textContentOverride;
    if (typeof cachedOverride === "string") {
      return cachedOverride;
    }

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
    if (!trackCharacterData && (this.#nodeType === Node.TEXT_NODE || this.#nodeType === Node.COMMENT_NODE)) {
      native.setCharacterDataDirect(this._handle, nextValue);
    } else {
      native.setNodeTextContent(this._handle, nextValue);
    }
    const mutableNode = this as unknown as { __textContentOverride?: string };
    if (this.#nodeType === Node.TEXT_NODE || this.#nodeType === Node.COMMENT_NODE || this.#nodeType === Node.PROCESSING_INSTRUCTION_NODE) {
      mutableNode.__textContentOverride = nextValue;
    } else {
      delete mutableNode.__textContentOverride;
    }
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
    this._window.assertOpen();
    let node = child as Node;
    const canSkipPreInsertionValidation =
      this.#nodeType === Node.ELEMENT_NODE &&
      node.#nodeType === Node.ELEMENT_NODE &&
      node._window === this._window;
    if (!canSkipPreInsertionValidation) {
      validatePreInsertion(this, node, null);
    }

    if (node.#nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
      if (
        node._window === this._window &&
        !this._window._hasMutationObservers &&
        !this._window._hasCustomElementDefinitions
      ) {
        native.appendFragment(this._handle, node._handle);
        if (this.#nodeType === Node.DOCUMENT_NODE) {
          refreshDocumentElementFlag(this);
        }
        return child;
      }

      while (node.firstChild) {
        this.appendChild(node.firstChild);
      }
      return child;
    }

    if (!canSkipPreInsertionValidation && needsAdoptionForParent(this, node)) {
      node = adoptForeignNodeForParent(this, node);
    }

    const trackMutations = this._window._hasMutationObservers;
    const hasCustomElementConnectionCallbacks = this._window._hasCustomElementConnectionCallbacks;
    if (!trackMutations && !hasCustomElementConnectionCallbacks) {
      native.appendChild(this._handle, node._handle);
      if (isIFrameElement(node)) {
        scheduleIFrameLoad(node);
      }
      if (this.#nodeType === Node.DOCUMENT_NODE) {
        refreshDocumentElementFlag(this);
      }
      return child;
    }

    const previousParent = trackMutations ? node.parentNode : null;
    const previousSibling = trackMutations ? node.previousSibling : null;
    const nextSibling = trackMutations ? node.nextSibling : null;
    const wasConnected = this._window.isConnectedNode(node);
    native.appendChildInWindow(this._window._nativeWindowHandle, this._handle, node._handle);

    if (trackMutations) {
      this._window.notifyChildListMutation(this, [node], [], node.previousSibling, node.nextSibling);
      if (previousParent && previousParent !== this) {
        this._window.notifyChildListMutation(previousParent, [], [node], previousSibling, nextSibling);
      }
    }

    if (!hasCustomElementConnectionCallbacks) {
      if (isIFrameElement(node)) {
        scheduleIFrameLoad(node);
      }
      if (this.#nodeType === Node.DOCUMENT_NODE) {
        refreshDocumentElementFlag(this);
      }
      return child;
    }

    const isConnected = this._window.isConnectedNode(node);
    if (!wasConnected && isConnected) {
      this._window.notifyConnectedSubtree(node);
    } else if (wasConnected && !isConnected) {
      this._window.notifyDisconnectedSubtree(node);
    } else if (wasConnected && isConnected && previousParent && previousParent !== this) {
      this._window.notifyDisconnectedSubtree(node);
      this._window.notifyConnectedSubtree(node);
    }

    if (isIFrameElement(node)) {
      scheduleIFrameLoad(node);
    }
    if (this.#nodeType === Node.DOCUMENT_NODE) {
      refreshDocumentElementFlag(this);
    }
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

    const insertionNodes = (nodes as unknown[]).map((node) => coerceInsertionNode(document, node));
    if (insertionNodes.length === 0) {
      return;
    }

    validateInsertionSequence(this, insertionNodes, null);
    for (const node of insertionNodes) {
      this.appendChild(node);
    }
  }

  prepend(...nodes: Array<Node | string>): void {
    this._window.assertOpen();

    const document = this.nodeType === Node.DOCUMENT_NODE
      ? (this as unknown as Document)
      : this.ownerDocument;

    if (!document) {
      throw new Error("prepend() requires an owner document");
    }

    const insertionNodes = (nodes as unknown[]).map((node) => coerceInsertionNode(document, node));
    if (insertionNodes.length === 0) {
      return;
    }

    const referenceNode = this.firstChild;
    validateInsertionSequence(this, insertionNodes, referenceNode);
    for (const node of insertionNodes) {
      this.insertBefore(node, referenceNode);
    }
  }

  replaceChildren(...nodes: Array<Node | string>): void {
    this._window.assertOpen();

    const document = this.nodeType === Node.DOCUMENT_NODE
      ? (this as unknown as Document)
      : this.ownerDocument;

    if (!document) {
      throw new Error("replaceChildren() requires an owner document");
    }

    const insertionNodes = (nodes as unknown[]).map((node) => coerceInsertionNode(document, node));
    validateInsertionSequence(this, insertionNodes, null);

    const canUseDetachedBatchReplace =
      !this._window._hasMutationObservers &&
      !this._window._hasCustomElementDefinitions &&
      insertionNodes.every((node) =>
        node._window === this._window &&
        node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE
      );
    if (canUseDetachedBatchReplace) {
      native.replaceChildren(this._handle, insertionNodes.map((node) => node._handle));
      for (const node of insertionNodes) {
        if (isIFrameElement(node)) {
          scheduleIFrameLoad(node);
        }
      }
      if (this.#nodeType === Node.DOCUMENT_NODE) {
        refreshDocumentElementFlag(this);
      }
      return;
    }

    for (const node of insertionNodes) {
      const parent = node.parentNode;
      if (parent && parent !== this) {
        parent.removeChild(node);
      }
    }

    const trackMutations = this._window.hasMutationObservers();
    if (trackMutations && !this._window.customElements.hasDefinitions) {
      const removedChildren = this.childNodes.toArray();
      const addedChildren = insertionNodes.flatMap((node) =>
        node.nodeType === Node.DOCUMENT_FRAGMENT_NODE ? node.childNodes.toArray() : [node]
      );

      while (this.firstChild) {
        native.removeChild(this._handle, this.firstChild._handle);
      }
      for (const node of addedChildren) {
        native.appendChild(this._handle, node._handle);
        scheduleIFrameLoadIfNeeded(node);
      }
      if (removedChildren.length > 0 || addedChildren.length > 0) {
        this._window.notifyChildListMutation(this, addedChildren, removedChildren, null, null);
      }
      refreshDocumentElementFlag(this);
      return;
    }

    while (this.firstChild) {
      this.removeChild(this.firstChild);
    }

    for (const node of insertionNodes) {
      this.appendChild(node);
    }
  }

  insertBefore<TNode extends Node>(newChild: TNode, referenceChild: Node | null): TNode {
    this._window.assertOpen();
    if (!(newChild instanceof Node)) {
      throw new TypeError("Failed to execute 'insertBefore' on 'Node': parameter 1 is not of type 'Node'.");
    }
    if (arguments.length < 2) {
      throw new TypeError("Failed to execute 'insertBefore' on 'Node': 2 arguments required, but only 1 present.");
    }
    if (referenceChild !== null && referenceChild !== undefined && !(referenceChild instanceof Node)) {
      throw new TypeError("Failed to execute 'insertBefore' on 'Node': parameter 2 is not of type 'Node'.");
    }

    const reference = referenceChild ?? null;
    validatePreInsertion(this, newChild, reference);

    if (newChild === reference) {
      return newChild;
    }

    if (newChild instanceof this._window.DocumentFragment) {
      const children = newChild.childNodes.toArray();
      for (const child of children) {
        this.insertBefore(child, reference);
      }
      return newChild;
    }

    let childToInsert = newChild as Node;
    if (needsAdoptionForParent(this, childToInsert)) {
      childToInsert = adoptForeignNodeForParent(this, childToInsert);
    }

    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.insertBefore(this._handle, childToInsert._handle, reference?._handle ?? 0);
      scheduleIFrameLoadIfNeeded(childToInsert);
      refreshDocumentElementFlag(this);
      return newChild;
    }

    const previousParent = trackMutations ? childToInsert.parentNode : null;
    const previousSibling = trackMutations ? childToInsert.previousSibling : null;
    const nextSibling = trackMutations ? childToInsert.nextSibling : null;
    const wasConnected = this._window.isConnectedNode(childToInsert);
    native.insertBefore(this._handle, childToInsert._handle, reference?._handle ?? 0);

    if (trackMutations) {
      this._window.notifyChildListMutation(this, [childToInsert], [], childToInsert.previousSibling, childToInsert.nextSibling);
      if (previousParent && previousParent !== this) {
        this._window.notifyChildListMutation(previousParent, [], [childToInsert], previousSibling, nextSibling);
      }
    }

    if (!this._window.customElements.hasDefinitions) {
      scheduleIFrameLoadIfNeeded(childToInsert);
      refreshDocumentElementFlag(this);
      return newChild;
    }

    const isConnected = this._window.isConnectedNode(childToInsert);
    if (!wasConnected && isConnected) {
      this._window.notifyConnectedSubtree(childToInsert);
    } else if (wasConnected && !isConnected) {
      this._window.notifyDisconnectedSubtree(childToInsert);
    } else if (wasConnected && isConnected && previousParent && previousParent !== this) {
      this._window.notifyDisconnectedSubtree(childToInsert);
      this._window.notifyConnectedSubtree(childToInsert);
    }

    scheduleIFrameLoadIfNeeded(childToInsert);
    refreshDocumentElementFlag(this);
    return newChild;
  }

  moveBefore<TNode extends Node>(movedNode: TNode, child: Node | null): TNode {
    this._window.assertOpen();
    return this.insertBefore(movedNode, child);
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
      if (this.nodeType === Node.DOCUMENT_NODE) {
        this.removeChild(oldChild);
        for (const child of fragmentChildren) {
          this.insertBefore(child, reference);
        }
        refreshDocumentElementFlag(this);
        return oldChild;
      }
      for (const child of fragmentChildren) {
        this.insertBefore(child, reference);
      }
      this.removeChild(oldChild);
      refreshDocumentElementFlag(this);
      return oldChild;
    }

    let replacementChild = newChild as Node;
    if (needsAdoptionForParent(this, replacementChild)) {
      replacementChild = adoptForeignNodeForParent(this, replacementChild);
    }

    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.replaceChild(this._handle, replacementChild._handle, oldChild._handle);
      scheduleIFrameLoadIfNeeded(replacementChild);
      refreshDocumentElementFlag(this);
      return oldChild;
    }

    const oldPreviousSibling = trackMutations ? oldChild.previousSibling : null;
    const oldNextSibling = trackMutations ? oldChild.nextSibling : null;
    const oldWasConnected = this._window.isConnectedNode(oldChild);
    const newWasConnected = this._window.isConnectedNode(replacementChild);
    const newPreviousParent = trackMutations ? replacementChild.parentNode : null;
    const newPreviousSibling = trackMutations ? replacementChild.previousSibling : null;
    const newNextSibling = trackMutations ? replacementChild.nextSibling : null;
    native.replaceChild(this._handle, replacementChild._handle, oldChild._handle);

    if (trackMutations) {
      this._window.notifyChildListMutation(this, [], [oldChild], oldPreviousSibling, oldNextSibling);
      this._window.notifyChildListMutation(this, [replacementChild], [], replacementChild.previousSibling, replacementChild.nextSibling);
      if (newPreviousParent && newPreviousParent !== this) {
        this._window.notifyChildListMutation(newPreviousParent, [], [replacementChild], newPreviousSibling, newNextSibling);
      }
    }

    if (!this._window.customElements.hasDefinitions) {
      scheduleIFrameLoadIfNeeded(replacementChild);
      refreshDocumentElementFlag(this);
      return oldChild;
    }

    const oldIsConnected = this._window.isConnectedNode(oldChild);
    const newIsConnected = this._window.isConnectedNode(replacementChild);

    if (oldWasConnected && !oldIsConnected) {
      this._window.notifyDisconnectedSubtree(oldChild);
    }
    if (!newWasConnected && newIsConnected) {
      this._window.notifyConnectedSubtree(replacementChild);
    } else if (newWasConnected && newIsConnected && newPreviousParent && newPreviousParent !== this) {
      this._window.notifyDisconnectedSubtree(replacementChild);
      this._window.notifyConnectedSubtree(replacementChild);
    }

    scheduleIFrameLoadIfNeeded(replacementChild);
    refreshDocumentElementFlag(this);
    return oldChild;
  }

  getRootNode(options?: { composed?: boolean }): Node {
    let cursor: Node = this;
    while (cursor.parentNode) {
      cursor = cursor.parentNode;
    }

    if (options?.composed) {
      const rootWithHost = cursor as Node & { host?: Node | null };
      const host = rootWithHost.host;
      if (host) {
        return host.getRootNode(options);
      }
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

  before(...nodes: Array<Node | string>): void {
    this._window.assertOpen();

    const parent = this.parentNode;
    if (!parent) {
      return;
    }

    const document = parent.nodeType === Node.DOCUMENT_NODE
      ? (parent as unknown as Document)
      : parent.ownerDocument;
    if (!document) {
      return;
    }

    const insertionNodes = (nodes as unknown[]).map((node) => coerceInsertionNode(document, node));
    const reference = insertionNodes.includes(this) ? viableNextSibling(this, insertionNodes) : this;
    for (const node of insertionNodes) {
      parent.insertBefore(node, reference);
    }
  }

  after(...nodes: Array<Node | string>): void {
    this._window.assertOpen();

    const parent = this.parentNode;
    if (!parent) {
      return;
    }

    const document = parent.nodeType === Node.DOCUMENT_NODE
      ? (parent as unknown as Document)
      : parent.ownerDocument;
    if (!document) {
      return;
    }

    const insertionNodes = (nodes as unknown[]).map((node) => coerceInsertionNode(document, node));
    const reference = viableNextSibling(this, insertionNodes);
    for (const node of insertionNodes) {
      parent.insertBefore(node, reference);
    }
  }

  replaceWith(...nodes: Array<Node | string>): void {
    this._window.assertOpen();

    const parent = this.parentNode;
    if (!parent) {
      return;
    }

    const document = parent.nodeType === Node.DOCUMENT_NODE
      ? (parent as unknown as Document)
      : parent.ownerDocument;
    if (!document) {
      return;
    }

    const insertionNodes = (nodes as unknown[]).map((node) => coerceInsertionNode(document, node));
    const reference = viableNextSibling(this, insertionNodes);
    for (const node of insertionNodes) {
      parent.insertBefore(node, reference);
    }
    if (!insertionNodes.includes(this)) {
      this.remove();
    }
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

    if (this.nodeType === Node.DOCUMENT_NODE) {
      return isEqualDocumentNode(this, other);
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

    if (!(event instanceof Event)) {
      throw new TypeError("Failed to execute 'dispatchEvent': parameter 1 is not of type 'Event'.");
    }
    if (event.dispatching) {
      throw new ZigDOMException("The event is already being dispatched.", "InvalidStateError", 11);
    }
    if (event.type === "") {
      throw new ZigDOMException("The event has no type.", "InvalidStateError", 11);
    }

    event.setDispatchFlag(true);

    try {
      if (!event.target) {
        event.target = this;
      }

      const propagationPath: Node[] = [this];
      let cursor = this.parentNode;
      while (cursor) {
        propagationPath.push(cursor);
        cursor = cursor.parentNode;
      }
      propagationPath.push(this._window as unknown as Node);
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

      return !event.defaultPrevented;
    } finally {
      event.currentTarget = null;
      event.eventPhase = Event.NONE;
      event.setDispatchFlag(false);
      event.resetAfterDispatch();
    }
  }

  protected invokePropertyHandler(event: Event): void {
    const handlerName = `on${event.type.slice(0, 1).toLowerCase()}${event.type.slice(1)}` as keyof this;
    const handler = this[handlerName] as unknown;
    if (typeof handler === "function") {
      (handler as (this: Node, event: Event) => void).call(this, event);
    }
  }

  get outerHTML(): string {
    if (this.#nodeType === Node.TEXT_NODE) {
      return escapeTextForSerialization(this.textContent);
    }
    if (this.#nodeType === Node.COMMENT_NODE) {
      return `<!--${this.textContent}-->`;
    }
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
  const destinationDocument = destinationDocumentForParent(parent);

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

function throwHierarchyRequestError(): never {
  throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
}

function destinationDocumentForParent(parent: Node): Document | null {
  return parent.nodeType === Node.DOCUMENT_NODE
    ? (parent as unknown as Document)
    : parent.ownerDocument;
}

function needsAdoptionForParent(parent: Node, node: Node): boolean {
  const destinationDocument = destinationDocumentForParent(parent);
  if (!destinationDocument) {
    return false;
  }

  if (node._window !== parent._window) {
    return true;
  }

  const ownerDocument = node.nodeType === Node.DOCUMENT_NODE
    ? (node as unknown as Document)
    : node.ownerDocument;

  return ownerDocument != null && ownerDocument !== destinationDocument;
}

function validatePreInsertion(parent: Node, newChild: Node, referenceChild: Node | null): void {
  const parentType = parent.nodeType;

  if (
    parentType === Node.TEXT_NODE ||
    parentType === Node.COMMENT_NODE ||
    parentType === Node.PROCESSING_INSTRUCTION_NODE ||
    parentType === Node.DOCUMENT_TYPE_NODE
  ) {
    throwHierarchyRequestError();
  }

  let ancestor: Node | null = parent;
  while (ancestor) {
    if (ancestor === newChild) {
      throwHierarchyRequestError();
    }
    ancestor = ancestor.parentNode;
  }

  if (referenceChild && referenceChild.parentNode !== parent) {
    throw new ZigDOMException("The object can not be found here.", "NotFoundError", 8);
  }

  const nodesToInsert = newChild.nodeType === Node.DOCUMENT_FRAGMENT_NODE
    ? newChild.childNodes.toArray()
    : [newChild];

  for (const candidate of nodesToInsert) {
    let parentAncestor: Node | null = parent;
    while (parentAncestor) {
      if (parentAncestor === candidate) {
        throwHierarchyRequestError();
      }
      parentAncestor = parentAncestor.parentNode;
    }

    const type = candidate.nodeType;
    const isAllowedNodeType =
      type === Node.DOCUMENT_FRAGMENT_NODE ||
      type === Node.DOCUMENT_TYPE_NODE ||
      type === Node.ELEMENT_NODE ||
      type === Node.TEXT_NODE ||
      type === Node.PROCESSING_INSTRUCTION_NODE ||
      type === Node.COMMENT_NODE;
    if (!isAllowedNodeType) {
      throwHierarchyRequestError();
    }

    if (parentType !== Node.DOCUMENT_NODE && type === Node.DOCUMENT_TYPE_NODE) {
      throwHierarchyRequestError();
    }

    if (
      (parentType === Node.ELEMENT_NODE || parentType === Node.DOCUMENT_FRAGMENT_NODE) &&
      type === Node.DOCUMENT_TYPE_NODE
    ) {
      throwHierarchyRequestError();
    }
  }

  if (parentType !== Node.DOCUMENT_NODE) {
    return;
  }

  const children = parent.childNodes.toArray();
  if (newChild.parentNode === parent && newChild.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) {
    const existingIndex = children.indexOf(newChild);
    if (existingIndex >= 0) {
      children.splice(existingIndex, 1);
    }
  }

  const referenceIndex = referenceChild ? children.indexOf(referenceChild) : children.length;
  if (referenceChild && referenceIndex < 0) {
    throw new ZigDOMException("The object can not be found here.", "NotFoundError", 8);
  }

  const candidateChildren = [
    ...children.slice(0, referenceIndex),
    ...nodesToInsert,
    ...children.slice(referenceIndex)
  ];

  let elementCount = 0;
  let doctypeCount = 0;
  let firstElementIndex = -1;
  let firstDoctypeIndex = -1;

  for (let index = 0; index < candidateChildren.length; index += 1) {
    const type = candidateChildren[index]?.nodeType;
    if (type === Node.TEXT_NODE) {
      throwHierarchyRequestError();
    }
    if (type === Node.ELEMENT_NODE) {
      elementCount += 1;
      if (firstElementIndex < 0) {
        firstElementIndex = index;
      }
    }
    if (type === Node.DOCUMENT_TYPE_NODE) {
      doctypeCount += 1;
      if (firstDoctypeIndex < 0) {
        firstDoctypeIndex = index;
      }
    }
  }

  if (elementCount > 1 || doctypeCount > 1) {
    throwHierarchyRequestError();
  }

  if (firstElementIndex >= 0 && firstDoctypeIndex >= 0 && firstDoctypeIndex > firstElementIndex) {
    throwHierarchyRequestError();
  }
}

function validateInsertionSequence(parent: Node, insertionNodes: Node[], referenceChild: Node | null): void {
  const validationNodes = insertionNodes.flatMap((node) =>
    node.nodeType === Node.DOCUMENT_FRAGMENT_NODE ? node.childNodes.toArray() : [node]
  );
  const syntheticFragment = {
    nodeType: Node.DOCUMENT_FRAGMENT_NODE,
    parentNode: null,
    childNodes: {
      toArray: () => validationNodes
    }
  } as unknown as Node;

  validatePreInsertion(parent, syntheticFragment, referenceChild);
}

function remapNodeIdentity(source: Node, replacement: Node): void {
  const sourceChildren = source.childNodes.toArray();
  const replacementChildren = replacement.childNodes.toArray();

  const sourceLike = source as unknown as {
    _window: Window;
    _handle: number;
  };
  const previousWindow = sourceLike._window;
  const previousHandle = sourceLike._handle;

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
  previousWindow.unbindNodeFromHandle(previousHandle, source);
  replacementLike._window.bindNodeToHandle(replacementLike._handle, source);

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

function coerceInsertionNode(document: Document, value: unknown): Node {
  if (value && typeof value === "object" && typeof (value as { nodeType?: unknown }).nodeType === "number") {
    return value as Node;
  }
  const text = String(value);
  return document.createTextNode(text);
}

function viableNextSibling(node: Node, insertionNodes: Node[]): Node | null {
  let sibling = node.nextSibling;
  while (sibling && insertionNodes.includes(sibling)) {
    sibling = sibling.nextSibling;
  }
  return sibling;
}

function escapeTextForSerialization(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function isEqualDocumentNode(left: Node, right: Node): boolean {
  const leftChildren = left.childNodes.toArray();
  const rightChildren = right.childNodes.toArray();
  if (leftChildren.length !== rightChildren.length) {
    return false;
  }

  for (let index = 0; index < leftChildren.length; index += 1) {
    const leftChild = leftChildren[index];
    const rightChild = rightChildren[index];
    if (!leftChild || !rightChild) {
      return false;
    }

    if (leftChild.nodeType === Node.ELEMENT_NODE && rightChild.nodeType === Node.ELEMENT_NODE) {
      const leftElement = leftChild as unknown as { localName?: string; isEqualNode: (other: Node | null) => boolean };
      const rightElement = rightChild as unknown as { localName?: string };
      if (leftElement.localName === "html" && rightElement.localName === "html") {
        if (!isEqualHtmlRoot(leftChild, rightChild)) {
          return false;
        }
        continue;
      }
    }

    if (!leftChild.isEqualNode(rightChild)) {
      return false;
    }
  }

  return true;
}

function scheduleIFrameLoadIfNeeded(node: Node): void {
  if (!isIFrameElement(node)) {
    return;
  }

  scheduleIFrameLoad(node);
}

function isIFrameElement(node: Node): boolean {
  return (node as unknown as { constructor?: unknown }).constructor === node._window.HTMLIFrameElement;
}

function scheduleIFrameLoad(node: Node): void {
  const elementLike = node as unknown as {
    dispatchEvent?: (event: Event) => boolean;
    onload?: ((event: Event) => void) | null;
    hasAttribute?: (name: string) => boolean;
    __pendingInitialLoadEvent?: boolean;
  };

  if (elementLike.__pendingInitialLoadEvent) {
    return;
  }

  elementLike.__pendingInitialLoadEvent = true;
  node._window.queueMicrotask(() => {
    elementLike.__pendingInitialLoadEvent = false;
    if (!node.isConnected) {
      return;
    }
    (node._window as unknown as { __loadFrameDocument?: (frame: unknown) => void }).__loadFrameDocument?.(node);
    const event = new Event("load");
    elementLike.dispatchEvent?.(event);
  });
}

function isEqualHtmlRoot(leftRoot: Node, rightRoot: Node): boolean {
  const leftLike = leftRoot as unknown as {
    namespaceURI?: string | null;
    prefix?: string | null;
    localName?: string;
    attributes?: Array<{ namespaceURI?: string | null; localName?: string; name: string; value: string }>;
  };
  const rightLike = rightRoot as unknown as {
    namespaceURI?: string | null;
    prefix?: string | null;
    localName?: string;
    attributes?: Array<{ namespaceURI?: string | null; localName?: string; name: string; value: string }>;
  };

  if (leftLike.namespaceURI !== rightLike.namespaceURI || leftLike.prefix !== rightLike.prefix || leftLike.localName !== rightLike.localName) {
    return false;
  }

  const leftAttrs = leftLike.attributes ?? [];
  const rightAttrs = rightLike.attributes ?? [];
  if (leftAttrs.length !== rightAttrs.length) {
    return false;
  }

  const sortAttrs = (items: Array<{ namespaceURI?: string | null; localName?: string; name: string; value: string }>) =>
    [...items].sort((a, b) => `${a.namespaceURI ?? ""}:${a.localName ?? a.name}`.localeCompare(`${b.namespaceURI ?? ""}:${b.localName ?? b.name}`));
  const leftSorted = sortAttrs(leftAttrs);
  const rightSorted = sortAttrs(rightAttrs);
  for (let index = 0; index < leftSorted.length; index += 1) {
    const leftAttr = leftSorted[index];
    const rightAttr = rightSorted[index];
    if (!leftAttr || !rightAttr) {
      return false;
    }
    if (leftAttr.namespaceURI !== rightAttr.namespaceURI ||
        (leftAttr.localName ?? leftAttr.name) !== (rightAttr.localName ?? rightAttr.name) ||
        leftAttr.value !== rightAttr.value) {
      return false;
    }
  }

  const leftElements = leftRoot.childNodes.toArray().filter((child) => child.nodeType === Node.ELEMENT_NODE);
  const rightElements = rightRoot.childNodes.toArray().filter((child) => child.nodeType === Node.ELEMENT_NODE);

  if (leftElements.length === 0 || rightElements.length === 0) {
    return true;
  }

  const leftHead = leftElements.find((child) => (child as unknown as { localName?: string }).localName === "head") ?? null;
  const rightHead = rightElements.find((child) => (child as unknown as { localName?: string }).localName === "head") ?? null;
  const leftBody = leftElements.find((child) => (child as unknown as { localName?: string }).localName === "body") ?? null;
  const rightBody = rightElements.find((child) => (child as unknown as { localName?: string }).localName === "body") ?? null;

  if ((leftHead == null) !== (rightHead == null) || (leftBody == null) !== (rightBody == null)) {
    return false;
  }

  if (leftHead && rightHead && !isEqualHtmlDocumentChild(leftHead, rightHead)) {
    return false;
  }
  if (leftBody && rightBody && !isEqualHtmlDocumentChild(leftBody, rightBody)) {
    return false;
  }

  const leftOther = leftElements.filter((child) => {
    const localName = (child as unknown as { localName?: string }).localName;
    return localName !== "head" && localName !== "body";
  });
  const rightOther = rightElements.filter((child) => {
    const localName = (child as unknown as { localName?: string }).localName;
    return localName !== "head" && localName !== "body";
  });

  if (leftOther.length !== rightOther.length) {
    return false;
  }

  for (let index = 0; index < leftOther.length; index += 1) {
    if (!leftOther[index]?.isEqualNode(rightOther[index] ?? null)) {
      return false;
    }
  }

  return true;
}

function isEqualHtmlDocumentChild(left: Node, right: Node): boolean {
  const leftElement = left as unknown as { localName?: string; attributes?: Array<{ namespaceURI?: string | null; localName?: string; name: string; value: string }> };
  const rightElement = right as unknown as { localName?: string; attributes?: Array<{ namespaceURI?: string | null; localName?: string; name: string; value: string }> };
  if (leftElement.localName !== rightElement.localName) {
    return false;
  }

  const leftAttrs = leftElement.attributes ?? [];
  const rightAttrs = rightElement.attributes ?? [];
  if (leftAttrs.length !== rightAttrs.length) {
    return false;
  }

  const sortAttrs = (items: Array<{ namespaceURI?: string | null; localName?: string; name: string; value: string }>) =>
    [...items].sort((a, b) => `${a.namespaceURI ?? ""}:${a.localName ?? a.name}`.localeCompare(`${b.namespaceURI ?? ""}:${b.localName ?? b.name}`));
  const leftSorted = sortAttrs(leftAttrs);
  const rightSorted = sortAttrs(rightAttrs);
  for (let index = 0; index < leftSorted.length; index += 1) {
    const leftAttr = leftSorted[index];
    const rightAttr = rightSorted[index];
    if (!leftAttr || !rightAttr || leftAttr.namespaceURI !== rightAttr.namespaceURI ||
        (leftAttr.localName ?? leftAttr.name) !== (rightAttr.localName ?? rightAttr.name) ||
        leftAttr.value !== rightAttr.value) {
      return false;
    }
  }

  const leftChildren = left.childNodes.toArray();
  const rightChildren = right.childNodes.toArray();
  if (leftChildren.length !== rightChildren.length) {
    return false;
  }
  for (let index = 0; index < leftChildren.length; index += 1) {
    if (!leftChildren[index]?.isEqualNode(rightChildren[index] ?? null)) {
      return false;
    }
  }
  return true;
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

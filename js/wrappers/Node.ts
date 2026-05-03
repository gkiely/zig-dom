import { native } from "../ffi.ts";
import type { Document } from "./Document.ts";
import { Event, EventTargetBase } from "./Event.ts";
import { NodeList } from "./NodeList.ts";
import type { Window } from "./Window.ts";

export class Node extends EventTargetBase {
  static readonly ELEMENT_NODE = 1;
  static readonly TEXT_NODE = 3;
  static readonly COMMENT_NODE = 8;
  static readonly DOCUMENT_NODE = 9;
  static readonly DOCUMENT_FRAGMENT_NODE = 11;

  static readonly DOCUMENT_POSITION_DISCONNECTED = 0x01;
  static readonly DOCUMENT_POSITION_PRECEDING = 0x02;
  static readonly DOCUMENT_POSITION_FOLLOWING = 0x04;
  static readonly DOCUMENT_POSITION_CONTAINS = 0x08;
  static readonly DOCUMENT_POSITION_CONTAINED_BY = 0x10;
  static readonly DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 0x20;

  readonly _window: Window;
  readonly _handle: number;
  readonly #nodeType: number;

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
    const trackCharacterData = this._window.hasMutationObservers() &&
      (this.#nodeType === Node.TEXT_NODE || this.#nodeType === Node.COMMENT_NODE);
    const previousValue = trackCharacterData ? this.textContent : "";
    native.setNodeTextContent(this._handle, value ?? "");
    if (trackCharacterData) {
      this._window.notifyCharacterDataChanged(this, previousValue);
    }
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
    if (child.#nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
      while (child.firstChild) {
        this.appendChild(child.firstChild);
      }
      return child;
    }

    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.appendChild(this._handle, child._handle);
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

    return child;
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

    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.insertBefore(this._handle, newChild._handle, referenceChild?._handle ?? 0);
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

    return newChild;
  }

  removeChild<TNode extends Node>(child: TNode): TNode {
    this._window.assertOpen();
    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.removeChild(this._handle, child._handle);
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
      return child;
    }

    const isConnected = this._window.isConnectedNode(child);
    if (wasConnected && !isConnected) {
      this._window.notifyDisconnectedSubtree(child);
    }

    return child;
  }

  replaceChild<TNode extends Node>(newChild: Node, oldChild: TNode): TNode {
    this._window.assertOpen();
    const trackMutations = this._window.hasMutationObservers();
    if (!trackMutations && !this._window.customElements.hasDefinitions) {
      native.replaceChild(this._handle, newChild._handle, oldChild._handle);
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
        const container = document.createElement("div");
        container.innerHTML = this.outerHTML;
        const clone = container.firstChild;
        if (!clone) {
          throw new Error("cloneNode() failed to produce an element clone");
        }
        if (!deep) {
          while (clone.firstChild) {
            clone.removeChild(clone.firstChild);
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
      return this.textContent === other.textContent;
    }

    if (this.nodeType === Node.ELEMENT_NODE) {
      const leftAttributes = ((this as unknown) as { attributes?: Array<{ name: string; value: string }> }).attributes ?? [];
      const rightAttributes = ((other as unknown) as { attributes?: Array<{ name: string; value: string }> }).attributes ?? [];
      if (leftAttributes.length !== rightAttributes.length) {
        return false;
      }

      const sortByName = (a: { name: string; value: string }, b: { name: string; value: string }) => a.name.localeCompare(b.name);
      const leftSorted = [...leftAttributes].sort(sortByName);
      const rightSorted = [...rightAttributes].sort(sortByName);
      for (let i = 0; i < leftSorted.length; i += 1) {
        if (leftSorted[i]?.name !== rightSorted[i]?.name || leftSorted[i]?.value !== rightSorted[i]?.value) {
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
      if (child.nodeType === Node.TEXT_NODE) {
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

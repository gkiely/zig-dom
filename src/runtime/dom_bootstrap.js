(() => {
  const native = globalThis.__zigDomNative;
  const initialWindowHandle = Number(globalThis.__zigDomWindowHandle || 0);
  const initialDocumentHandle = Number(globalThis.__zigDomDocumentHandle || 0);

  const HANDLE = Symbol("zigDomHandle");
  const OWNER_DOCUMENT_HANDLE = Symbol("zigDomOwnerDocumentHandle");
  const INTERNAL = Symbol("zigDomInternal");

  const NODE_CACHE = new Map();
  const WINDOW_CACHE = new Map();

  function asWindowHandleFromNode(nodeHandle) {
    return Math.floor(Number(nodeHandle) / 4294967296);
  }

  function toStringValue(value) {
    return value == null ? "" : String(value);
  }

  function assertNode(value, typeName) {
    if (!value || typeof value !== "object" || typeof value[HANDLE] !== "number") {
      throw new TypeError(typeName + " must be a native DOM node");
    }
  }

  function getHandle(value, typeName) {
    assertNode(value, typeName);
    return value[HANDLE];
  }

  function parseAttributes(element) {
    const raw = native.elementAttributesJson(element[HANDLE]);
    if (!raw) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }

  function collectChildNodes(node) {
    const out = [];
    let cursor = node.firstChild;
    while (cursor) {
      out.push(cursor);
      cursor = cursor.nextSibling;
    }
    return out;
  }

  function collectChildElements(node) {
    return collectChildNodes(node).filter((child) => child.nodeType === Node.ELEMENT_NODE);
  }

  function dataAttrFromProp(name) {
    return "data-" + String(name).replace(/[A-Z]/g, (letter) => "-" + letter.toLowerCase());
  }

  function propFromDataAttr(name) {
    return String(name)
      .slice(5)
      .replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
  }

  function listenerOptions(options) {
    if (options === true) {
      return { capture: true, once: false };
    }
    if (!options || typeof options !== "object") {
      return { capture: false, once: false };
    }
    return {
      capture: Boolean(options.capture),
      once: Boolean(options.once)
    };
  }

  function invokeListenerCallback(target, callback, event) {
    if (typeof callback === "function") {
      callback.call(target, event);
      return;
    }
    if (callback && typeof callback.handleEvent === "function") {
      callback.handleEvent(event);
    }
  }

  function walkDescendants(root, visit) {
    let cursor = root.firstChild;
    while (cursor) {
      visit(cursor);
      walkDescendants(cursor, visit);
      cursor = cursor.nextSibling;
    }
  }

  function parseAttributeSelector(selector) {
    const match = String(selector).match(/^\[([A-Za-z_:-][\w:.-]*)(?:=(["']?)(.*?)\2)?\]$/);
    if (!match) {
      return null;
    }
    return {
      name: match[1],
      value: match[3],
      hasValue: match[3] !== undefined
    };
  }

  function elementMatchesSimpleSelector(element, selector) {
    const trimmed = String(selector).trim();
    if (!trimmed) {
      return false;
    }

    const notSelectors = [];
    let base = trimmed.replace(/:not\((\[[^\]]+\])\)/g, (_full, inner) => {
      notSelectors.push(inner);
      return "";
    });

    const tagMatch = base.match(/^[A-Za-z][\w:-]*/);
    if (tagMatch && element.localName !== tagMatch[0].toLowerCase()) {
      return false;
    }
    if (!tagMatch && base.startsWith("*")) {
      base = base.slice(1);
    }

    const attributeMatches = base.match(/\[[^\]]+\]/g) || [];
    for (const rawAttribute of attributeMatches) {
      const attribute = parseAttributeSelector(rawAttribute);
      if (!attribute || !element.hasAttribute(attribute.name)) {
        return false;
      }
      if (attribute.hasValue && element.getAttribute(attribute.name) !== attribute.value) {
        return false;
      }
    }

    for (const rawNotAttribute of notSelectors) {
      const attribute = parseAttributeSelector(rawNotAttribute);
      if (!attribute) {
        return null;
      }
      if (!element.hasAttribute(attribute.name)) {
        continue;
      }
      if (!attribute.hasValue || element.getAttribute(attribute.name) === attribute.value) {
        return false;
      }
    }

    return true;
  }

  function elementMatchesSelectorList(element, selector) {
    const text = String(selector);
    const parts = text.split(",").map((part) => part.trim()).filter(Boolean);
    if (parts.length === 0) {
      return false;
    }

    for (const part of parts) {
      if (/[>+~\s]/.test(part)) {
        continue;
      }
      const matched = elementMatchesSimpleSelector(element, part);
      if (matched === null) {
        continue;
      }
      if (matched) {
        return true;
      }
    }
    return false;
  }

  class EventTarget {
    constructor() {
      this._listeners = new Map();
    }

    addEventListener(type, callback, options) {
      if (!callback) {
        return;
      }
      const key = String(type);
      const info = listenerOptions(options);
      const bucket = this._listeners.get(key) || [];
      for (const existing of bucket) {
        if (existing.callback === callback && existing.capture === info.capture) {
          return;
        }
      }
      bucket.push({ callback, capture: info.capture, once: info.once });
      this._listeners.set(key, bucket);
    }

    removeEventListener(type, callback, options) {
      if (!callback) {
        return;
      }
      const key = String(type);
      const info = listenerOptions(options);
      const bucket = this._listeners.get(key);
      if (!bucket || bucket.length === 0) {
        return;
      }
      const next = bucket.filter((entry) => !(entry.callback === callback && entry.capture === info.capture));
      if (next.length === 0) {
        this._listeners.delete(key);
      } else {
        this._listeners.set(key, next);
      }
    }

    dispatchEvent(event) {
      if (!(event instanceof Event)) {
        throw new TypeError("dispatchEvent expects an Event");
      }
      event._target = this;
      event._currentTarget = this;
      event._eventPhase = Event.AT_TARGET;
      dispatchListeners(this, event, true);
      if (!event._immediateStopped) {
        dispatchListeners(this, event, false);
      }
      event._eventPhase = Event.NONE;
      event._currentTarget = null;
      return !event.defaultPrevented;
    }
  }

  class Event {
    constructor(type, options = {}) {
      this.type = String(type);
      this.bubbles = Boolean(options.bubbles);
      this.cancelable = Boolean(options.cancelable);
      this.composed = Boolean(options.composed);
      this._target = null;
      this._currentTarget = null;
      this._eventPhase = Event.NONE;
      this._stopped = false;
      this._immediateStopped = false;
      this._canceled = false;
      this.timeStamp = Date.now();
    }

    get target() {
      return this._target;
    }

    get currentTarget() {
      return this._currentTarget;
    }

    get eventPhase() {
      return this._eventPhase;
    }

    get defaultPrevented() {
      return this._canceled;
    }

    preventDefault() {
      if (this.cancelable) {
        this._canceled = true;
      }
    }

    stopPropagation() {
      this._stopped = true;
    }

    stopImmediatePropagation() {
      this._stopped = true;
      this._immediateStopped = true;
    }
  }

  Event.NONE = 0;
  Event.CAPTURING_PHASE = 1;
  Event.AT_TARGET = 2;
  Event.BUBBLING_PHASE = 3;

  class CustomEvent extends Event {
    constructor(type, options = {}) {
      super(type, options);
      this.detail = options.detail;
    }
  }

  class MouseEvent extends Event {
    constructor(type, options = {}) {
      super(type, options);
      this.clientX = Number(options.clientX || 0);
      this.clientY = Number(options.clientY || 0);
      this.button = Number(options.button || 0);
      this.buttons = Number(options.buttons || 0);
      this.relatedTarget = options.relatedTarget || null;
    }
  }

  function dispatchListeners(target, event, capturePhase) {
    const bucket = target._listeners.get(event.type);
    if (!bucket || bucket.length === 0) {
      return;
    }

    for (const listener of bucket.slice()) {
      if (event._immediateStopped) {
        break;
      }
      if (Boolean(listener.capture) !== capturePhase) {
        continue;
      }
      invokeListenerCallback(target, listener.callback, event);
      if (listener.once) {
        target.removeEventListener(event.type, listener.callback, { capture: listener.capture });
      }
    }
  }

  class NodeList {
    constructor(readNodes, options = {}) {
      const isStatic = Boolean(options.static);
      const staticSnapshot = isStatic ? readNodes().slice() : null;
      this._read = staticSnapshot ? () => staticSnapshot : readNodes;

      return new Proxy(this, {
        get(target, property, receiver) {
          if (typeof property === "string" && /^\d+$/.test(property)) {
            return target._read()[Number(property)];
          }
          return Reflect.get(target, property, receiver);
        },
        has(target, property) {
          if (typeof property === "string" && /^\d+$/.test(property)) {
            return Number(property) < target._read().length;
          }
          return Reflect.has(target, property);
        },
        ownKeys(target) {
          const keys = Reflect.ownKeys(target);
          const numeric = target._read().map((_value, index) => String(index));
          return [...keys, ...numeric];
        },
        getOwnPropertyDescriptor(target, property) {
          if (typeof property === "string" && /^\d+$/.test(property)) {
            const index = Number(property);
            const values = target._read();
            if (index < values.length) {
              return {
                configurable: true,
                enumerable: true,
                writable: false,
                value: values[index]
              };
            }
          }
          return Reflect.getOwnPropertyDescriptor(target, property);
        }
      });
    }

    get length() {
      return this._read().length;
    }

    item(index) {
      return this._read()[Number(index)] || null;
    }

    toArray() {
      return this._read().slice();
    }

    forEach(callback, thisArg) {
      this.toArray().forEach((value, index) => callback.call(thisArg, value, index, this));
    }

    keys() {
      return this.toArray().keys();
    }

    values() {
      return this.toArray().values();
    }

    entries() {
      return this.toArray().entries();
    }

    [Symbol.iterator]() {
      return this.values();
    }
  }

  class HTMLCollection {
    constructor(readElements) {
      this._read = readElements;
      return new Proxy(this, {
        get(target, property, receiver) {
          if (typeof property === "string") {
            if (/^\d+$/.test(property)) {
              return target._read()[Number(property)];
            }
            const named = findNamedElement(target._read(), property);
            if (named) {
              return named;
            }
          }
          return Reflect.get(target, property, receiver);
        },
        has(target, property) {
          if (typeof property === "string") {
            if (/^\d+$/.test(property)) {
              return Number(property) < target._read().length;
            }
            if (findNamedElement(target._read(), property)) {
              return true;
            }
          }
          return Reflect.has(target, property);
        },
        ownKeys(target) {
          const keys = Reflect.ownKeys(target);
          const values = target._read();
          const numeric = values.map((_value, index) => String(index));
          return [...keys, ...numeric];
        },
        getOwnPropertyDescriptor(target, property) {
          if (typeof property === "string" && /^\d+$/.test(property)) {
            const index = Number(property);
            const values = target._read();
            if (index < values.length) {
              return {
                configurable: true,
                enumerable: true,
                writable: false,
                value: values[index]
              };
            }
          }
          return Reflect.getOwnPropertyDescriptor(target, property);
        }
      });
    }

    get length() {
      return this._read().length;
    }

    item(index) {
      return this._read()[Number(index)] || null;
    }

    namedItem(name) {
      return findNamedElement(this._read(), String(name));
    }

    toArray() {
      return this._read().slice();
    }

    [Symbol.iterator]() {
      return this._read()[Symbol.iterator]();
    }
  }

  function findNamedElement(elements, name) {
    for (const element of elements) {
      if (element.id === name) {
        return element;
      }
      if (element.getAttribute("name") === name) {
        return element;
      }
    }
    return null;
  }

  class Node extends EventTarget {
    constructor(handle, ownerDocumentHandle, nodeTypeOverride = 0, nodeNameOverride = null) {
      super();
      this[HANDLE] = Number(handle);
      this[OWNER_DOCUMENT_HANDLE] = Number(ownerDocumentHandle || 0);
      this._nodeTypeOverride = Number(nodeTypeOverride || 0);
      this._nodeNameOverride = nodeNameOverride == null ? null : String(nodeNameOverride);
      this._childNodesCache = null;
      this._childrenCache = null;
      if (this[HANDLE] && !NODE_CACHE.has(this[HANDLE])) {
        NODE_CACHE.set(this[HANDLE], this);
      }
    }

    get nodeType() {
      return this._nodeTypeOverride || Number(native.nodeType(this[HANDLE]));
    }

    get nodeName() {
      if (this._nodeNameOverride != null) {
        return this._nodeNameOverride;
      }
      return native.nodeName(this[HANDLE]);
    }

    get parentNode() {
      return wrapNode(native.nodeParent(this[HANDLE]));
    }

    get parentElement() {
      const parent = this.parentNode;
      return parent && parent.nodeType === Node.ELEMENT_NODE ? parent : null;
    }

    get firstChild() {
      return wrapNode(native.nodeFirstChild(this[HANDLE]));
    }

    get lastChild() {
      return wrapNode(native.nodeLastChild(this[HANDLE]));
    }

    get previousSibling() {
      return wrapNode(native.nodePreviousSibling(this[HANDLE]));
    }

    get nextSibling() {
      return wrapNode(native.nodeNextSibling(this[HANDLE]));
    }

    get ownerDocument() {
      if (this.nodeType === Node.DOCUMENT_NODE) {
        return null;
      }
      const owner = native.nodeOwnerDocument(this[HANDLE]) || this[OWNER_DOCUMENT_HANDLE];
      return wrapNode(owner);
    }

    get isConnected() {
      if (this.nodeType === Node.DOCUMENT_NODE) {
        return true;
      }
      let cursor = this.parentNode;
      while (cursor) {
        if (cursor.nodeType === Node.DOCUMENT_NODE) {
          return true;
        }
        cursor = cursor.parentNode;
      }
      return false;
    }

    get childNodes() {
      if (!this._childNodesCache) {
        this._childNodesCache = new NodeList(() => collectChildNodes(this));
      }
      return this._childNodesCache;
    }

    get children() {
      if (!this._childrenCache) {
        this._childrenCache = new HTMLCollection(() => collectChildElements(this));
      }
      return this._childrenCache;
    }

    get firstElementChild() {
      const values = this.children;
      return values.length > 0 ? values.item(0) : null;
    }

    get lastElementChild() {
      const values = this.children;
      return values.length > 0 ? values.item(values.length - 1) : null;
    }

    get previousElementSibling() {
      let cursor = this.previousSibling;
      while (cursor) {
        if (cursor.nodeType === Node.ELEMENT_NODE) {
          return cursor;
        }
        cursor = cursor.previousSibling;
      }
      return null;
    }

    get nextElementSibling() {
      let cursor = this.nextSibling;
      while (cursor) {
        if (cursor.nodeType === Node.ELEMENT_NODE) {
          return cursor;
        }
        cursor = cursor.nextSibling;
      }
      return null;
    }

    get childElementCount() {
      return this.children.length;
    }

    get textContent() {
      if (this.nodeType === Node.DOCUMENT_TYPE_NODE) {
        return null;
      }
      return native.nodeTextContent(this[HANDLE]);
    }

    set textContent(value) {
      if (this.nodeType === Node.DOCUMENT_TYPE_NODE) {
        return;
      }
      native.nodeSetTextContent(this[HANDLE], toStringValue(value));
    }

    get nodeValue() {
      if (this.nodeType === Node.TEXT_NODE || this.nodeType === Node.COMMENT_NODE) {
        return this.textContent;
      }
      return null;
    }

    set nodeValue(value) {
      if (this.nodeType === Node.TEXT_NODE || this.nodeType === Node.COMMENT_NODE) {
        this.textContent = value;
      }
    }

    appendChild(child) {
      assertNode(child, "child");
      if (child.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
        if (typeof native.nodeAppendFragment === "function") {
          native.nodeAppendFragment(this[HANDLE], child[HANDLE]);
          return child;
        }
        while (child.firstChild) {
          this.appendChild(child.firstChild);
        }
        return child;
      }
      native.nodeAppendChild(this[HANDLE], child[HANDLE]);
      return child;
    }

    insertBefore(child, referenceChild) {
      assertNode(child, "child");
      const referenceHandle = referenceChild == null ? 0 : getHandle(referenceChild, "referenceChild");
      if (child.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
        const moving = child.childNodes.toArray();
        for (const item of moving) {
          this.insertBefore(item, referenceChild);
        }
        return child;
      }
      native.nodeInsertBefore(this[HANDLE], child[HANDLE], referenceHandle);
      return child;
    }

    removeChild(child) {
      assertNode(child, "child");
      native.nodeRemoveChild(this[HANDLE], child[HANDLE]);
      return child;
    }

    replaceChild(newChild, oldChild) {
      assertNode(newChild, "newChild");
      assertNode(oldChild, "oldChild");
      if (newChild.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
        this.insertBefore(newChild, oldChild);
        this.removeChild(oldChild);
        return oldChild;
      }
      native.nodeReplaceChild(this[HANDLE], newChild[HANDLE], oldChild[HANDLE]);
      return oldChild;
    }

    contains(other) {
      if (!other || typeof other !== "object" || typeof other[HANDLE] !== "number") {
        return false;
      }
      return Boolean(native.nodeContains(this[HANDLE], other[HANDLE]));
    }

    cloneNode(deep = false) {
      return cloneNodeValue(this, Boolean(deep));
    }

    querySelector(selector) {
      const local = this.querySelectorAll(selector);
      if (String(selector).includes(",") && local.length > 0) {
        return local.item(0);
      }
      const handle = native.nodeQuerySelector(this[HANDLE], String(selector));
      return wrapNode(handle);
    }

    querySelectorAll(selector) {
      if (String(selector).includes(",")) {
        const matches = [];
        walkDescendants(this, (node) => {
          if (node.nodeType === Node.ELEMENT_NODE && node.matches(selector)) {
            matches.push(node);
          }
        });
        return new NodeList(() => matches, { static: true });
      }
      const handles = native.nodeQuerySelectorAll(this[HANDLE], String(selector));
      return new NodeList(() => wrapHandleArray(handles), { static: true });
    }

    dispatchEvent(event) {
      if (!(event instanceof Event)) {
        throw new TypeError("dispatchEvent expects an Event");
      }

      const path = [];
      let cursor = this.parentNode;
      while (cursor) {
        path.push(cursor);
        cursor = cursor.parentNode;
      }

      event._target = this;
      event._currentTarget = null;
      event._stopped = false;
      event._immediateStopped = false;
      event._eventPhase = Event.NONE;

      for (let index = path.length - 1; index >= 0; index -= 1) {
        if (event._stopped) {
          break;
        }
        event._eventPhase = Event.CAPTURING_PHASE;
        event._currentTarget = path[index];
        dispatchListeners(path[index], event, true);
      }

      if (!event._stopped) {
        event._eventPhase = Event.AT_TARGET;
        event._currentTarget = this;
        dispatchListeners(this, event, true);
        if (!event._immediateStopped) {
          dispatchListeners(this, event, false);
        }
      }

      if (event.bubbles && !event._stopped) {
        for (const target of path) {
          if (event._stopped) {
            break;
          }
          event._eventPhase = Event.BUBBLING_PHASE;
          event._currentTarget = target;
          dispatchListeners(target, event, false);
        }
      }

      event._eventPhase = Event.NONE;
      event._currentTarget = null;
      return !event.defaultPrevented;
    }
  }

  Node.ELEMENT_NODE = 1;
  Node.TEXT_NODE = 3;
  Node.COMMENT_NODE = 8;
  Node.DOCUMENT_NODE = 9;
  Node.DOCUMENT_TYPE_NODE = 10;
  Node.DOCUMENT_FRAGMENT_NODE = 11;

  Node.DOCUMENT_POSITION_DISCONNECTED = 0x01;
  Node.DOCUMENT_POSITION_PRECEDING = 0x02;
  Node.DOCUMENT_POSITION_FOLLOWING = 0x04;
  Node.DOCUMENT_POSITION_CONTAINS = 0x08;
  Node.DOCUMENT_POSITION_CONTAINED_BY = 0x10;
  Node.DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 0x20;

  Object.assign(Node.prototype, {
    ELEMENT_NODE: Node.ELEMENT_NODE,
    TEXT_NODE: Node.TEXT_NODE,
    COMMENT_NODE: Node.COMMENT_NODE,
    DOCUMENT_NODE: Node.DOCUMENT_NODE,
    DOCUMENT_TYPE_NODE: Node.DOCUMENT_TYPE_NODE,
    DOCUMENT_FRAGMENT_NODE: Node.DOCUMENT_FRAGMENT_NODE,
    DOCUMENT_POSITION_DISCONNECTED: Node.DOCUMENT_POSITION_DISCONNECTED,
    DOCUMENT_POSITION_PRECEDING: Node.DOCUMENT_POSITION_PRECEDING,
    DOCUMENT_POSITION_FOLLOWING: Node.DOCUMENT_POSITION_FOLLOWING,
    DOCUMENT_POSITION_CONTAINS: Node.DOCUMENT_POSITION_CONTAINS,
    DOCUMENT_POSITION_CONTAINED_BY: Node.DOCUMENT_POSITION_CONTAINED_BY,
    DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC: Node.DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC
  });

  class CharacterData extends Node {
    constructor(handle, ownerDocumentHandle, nodeTypeOverride, nodeNameOverride) {
      super(handle, ownerDocumentHandle, nodeTypeOverride, nodeNameOverride);
    }

    get data() {
      return this.textContent;
    }

    set data(value) {
      this.textContent = toStringValue(value);
    }

    get length() {
      return this.data.length;
    }

    appendData(data) {
      this.data = this.data + toStringValue(data);
    }

    deleteData(offset, count) {
      const value = this.data;
      const start = clampIndex(offset, value.length);
      const length = clampIndex(count, value.length - start);
      this.data = value.slice(0, start) + value.slice(start + length);
    }

    insertData(offset, data) {
      const value = this.data;
      const index = clampIndex(offset, value.length);
      const text = toStringValue(data);
      this.data = value.slice(0, index) + text + value.slice(index);
    }

    replaceData(offset, count, data) {
      const value = this.data;
      const start = clampIndex(offset, value.length);
      const length = clampIndex(count, value.length - start);
      const text = toStringValue(data);
      this.data = value.slice(0, start) + text + value.slice(start + length);
    }

    substringData(offset, count) {
      const value = this.data;
      const start = clampIndex(offset, value.length);
      const length = clampIndex(count, value.length - start);
      return value.slice(start, start + length);
    }
  }

  function clampIndex(value, max) {
    const n = Number(value);
    if (!Number.isFinite(n) || n <= 0) {
      return 0;
    }
    if (n >= max) {
      return max;
    }
    return Math.floor(n);
  }

  class Text extends CharacterData {
    constructor(value = "", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      if (marker === INTERNAL) {
        super(Number(value), Number(ownerDocumentHandle), Node.TEXT_NODE, "#text");
      } else {
        const handle = native.documentCreateTextNode(Number(ownerDocumentHandle), toStringValue(value));
        super(handle, Number(ownerDocumentHandle), Node.TEXT_NODE, "#text");
      }
    }

    splitText(offset) {
      const data = this.data;
      const index = clampIndex(offset, data.length);
      const head = data.slice(0, index);
      const tail = data.slice(index);
      this.data = head;
      const owner = this.ownerDocument || document;
      const sibling = owner.createTextNode(tail);
      if (this.parentNode) {
        this.parentNode.insertBefore(sibling, this.nextSibling);
      }
      return sibling;
    }
  }

  class Comment extends CharacterData {
    constructor(value = "", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      if (marker === INTERNAL) {
        super(Number(value), Number(ownerDocumentHandle), Node.COMMENT_NODE, "#comment");
      } else {
        const handle = native.documentCreateComment(Number(ownerDocumentHandle), toStringValue(value));
        super(handle, Number(ownerDocumentHandle), Node.COMMENT_NODE, "#comment");
      }
    }
  }

  class DocumentFragment extends Node {
    constructor(ownerDocumentHandle = initialDocumentHandle, marker = null, existingHandle = 0) {
      if (marker === INTERNAL) {
        super(Number(existingHandle), Number(ownerDocumentHandle), Node.DOCUMENT_FRAGMENT_NODE, "#document-fragment");
      } else {
        const handle = native.documentCreateDocumentFragment(Number(ownerDocumentHandle));
        super(handle, Number(ownerDocumentHandle), Node.DOCUMENT_FRAGMENT_NODE, "#document-fragment");
      }
    }

    get innerHTML() {
      return this.childNodes
        .toArray()
        .map((child) => child.outerHTML || child.textContent || "")
        .join("");
    }

    set innerHTML(value) {
      native.nodeSetInnerHtml(this[HANDLE], toStringValue(value));
    }
  }

  class DocumentType extends Node {
    constructor(name = "html", publicId = "", systemId = "", ownerDocumentHandle = initialDocumentHandle, marker = null, existingHandle = 0) {
      if (marker === INTERNAL) {
        super(Number(existingHandle), Number(ownerDocumentHandle), Node.DOCUMENT_TYPE_NODE, String(name));
      } else {
        const handle = native.documentCreateComment(Number(ownerDocumentHandle), "");
        super(handle, Number(ownerDocumentHandle), Node.DOCUMENT_TYPE_NODE, String(name));
      }
      this.name = String(name);
      this.publicId = String(publicId);
      this.systemId = String(systemId);
    }

    get nodeName() {
      return this.name;
    }

    get nodeValue() {
      return null;
    }

    set nodeValue(_value) {}

    get textContent() {
      return null;
    }

    set textContent(_value) {}

    get outerHTML() {
      const publicId = this.publicId ? ' PUBLIC "' + this.publicId + '"' : "";
      const systemId = this.systemId ? ' "' + this.systemId + '"' : "";
      return "<!DOCTYPE " + this.name + publicId + systemId + ">";
    }
  }

  class DOMTokenList {
    constructor(element, attributeName) {
      this._element = element;
      this._attributeName = attributeName;
      return new Proxy(this, {
        get(target, property, receiver) {
          if (typeof property === "string" && /^\d+$/.test(property)) {
            return target.item(Number(property)) || undefined;
          }
          const value = Reflect.get(target, property, receiver);
          return typeof value === "function" ? value.bind(target) : value;
        },
        has(target, property) {
          if (typeof property === "string" && /^\d+$/.test(property)) {
            return Number(property) < target.length;
          }
          return Reflect.has(target, property);
        }
      });
    }

    _tokens() {
      const raw = this._element.getAttribute(this._attributeName) || "";
      return Array.from(new Set(raw.split(/[\t\n\f\r ]+/).filter(Boolean)));
    }

    _set(tokens) {
      if (tokens.length === 0) {
        this._element.removeAttribute(this._attributeName);
        return;
      }
      this._element.setAttribute(this._attributeName, tokens.join(" "));
    }

    get length() {
      return this._tokens().length;
    }

    item(index) {
      return this._tokens()[Number(index)] || null;
    }

    contains(token) {
      return this._tokens().includes(String(token));
    }

    add(...tokens) {
      const set = new Set(this._tokens());
      for (const token of tokens) {
        const value = String(token);
        if (value.length > 0) {
          set.add(value);
        }
      }
      this._set([...set]);
    }

    remove(...tokens) {
      const removeSet = new Set(tokens.map((item) => String(item)));
      this._set(this._tokens().filter((item) => !removeSet.has(item)));
    }

    toggle(token, force) {
      const value = String(token);
      const has = this.contains(value);
      if (force === true || (!has && force !== false)) {
        this.add(value);
        return true;
      }
      if (has) {
        this.remove(value);
      }
      return false;
    }

    values() {
      return this._tokens().values();
    }

    keys() {
      return this._tokens().keys();
    }

    entries() {
      return this._tokens().entries();
    }

    forEach(callback, thisArg) {
      this._tokens().forEach((value, index) => callback.call(thisArg, value, index, this));
    }

    [Symbol.iterator]() {
      return this.values();
    }

    toString() {
      return this._tokens().join(" ");
    }
  }

  class Element extends Node {
    constructor(handleOrName = "div", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      if (marker === INTERNAL) {
        super(Number(handleOrName), Number(ownerDocumentHandle), Node.ELEMENT_NODE, null);
      } else {
        const handle = native.documentCreateElement(Number(ownerDocumentHandle), String(handleOrName).toLowerCase());
        super(handle, Number(ownerDocumentHandle), Node.ELEMENT_NODE, null);
      }
      this._classList = null;
      this._dataset = null;
    }

    get tagName() {
      return native.nodeName(this[HANDLE]).toUpperCase();
    }

    get localName() {
      return native.nodeName(this[HANDLE]).toLowerCase();
    }

    get id() {
      return this.getAttribute("id") || "";
    }

    set id(value) {
      this.setAttribute("id", toStringValue(value));
    }

    get className() {
      return this.getAttribute("class") || "";
    }

    set className(value) {
      this.setAttribute("class", toStringValue(value));
    }

    get classList() {
      if (!this._classList) {
        this._classList = new DOMTokenList(this, "class");
      }
      return this._classList;
    }

    getAttribute(name) {
      const value = native.elementGetAttribute(this[HANDLE], String(name));
      return value == null ? null : String(value);
    }

    getAttributeNode(name) {
      const attributeName = String(name);
      if (!this.hasAttribute(attributeName)) {
        return null;
      }
      const value = this.getAttribute(attributeName);
      return {
        name: attributeName,
        nodeName: attributeName,
        localName: attributeName,
        value,
        nodeValue: value,
        textContent: value,
        ownerElement: this,
        nodeType: 2
      };
    }

    setAttribute(name, value) {
      native.elementSetAttribute(this[HANDLE], String(name), toStringValue(value));
    }

    removeAttribute(name) {
      native.elementRemoveAttribute(this[HANDLE], String(name));
    }

    hasAttribute(name) {
      return Boolean(native.elementHasAttribute(this[HANDLE], String(name)));
    }

    toggleAttribute(name, force) {
      const key = String(name);
      const has = this.hasAttribute(key);
      if (force === true || (!has && force !== false)) {
        this.setAttribute(key, "");
        return true;
      }
      if (has) {
        this.removeAttribute(key);
      }
      return false;
    }

    getAttributeNames() {
      return parseAttributes(this).map((entry) => String(entry.name));
    }

    get attributes() {
      return this.getAttributeNames().map((name) => this.getAttributeNode(name));
    }

    get dataset() {
      if (!this._dataset) {
        const element = this;
        this._dataset = new Proxy(
          {},
          {
            get(_target, property) {
              if (typeof property !== "string") {
                return undefined;
              }
              const attr = element.getAttribute(dataAttrFromProp(property));
              return attr == null ? undefined : attr;
            },
            set(_target, property, value) {
              if (typeof property !== "string") {
                return false;
              }
              element.setAttribute(dataAttrFromProp(property), toStringValue(value));
              return true;
            },
            deleteProperty(_target, property) {
              if (typeof property !== "string") {
                return false;
              }
              element.removeAttribute(dataAttrFromProp(property));
              return true;
            },
            ownKeys() {
              return element
                .getAttributeNames()
                .filter((name) => name.startsWith("data-"))
                .map((name) => propFromDataAttr(name));
            },
            getOwnPropertyDescriptor(_target, property) {
              if (typeof property !== "string") {
                return undefined;
              }
              const value = element.getAttribute(dataAttrFromProp(property));
              if (value == null) {
                return undefined;
              }
              return {
                configurable: true,
                enumerable: true,
                writable: true,
                value
              };
            }
          }
        );
      }
      return this._dataset;
    }

    get innerHTML() {
      return this.childNodes
        .toArray()
        .map((child) => child.outerHTML || child.textContent || "")
        .join("");
    }

    set innerHTML(value) {
      native.nodeSetInnerHtml(this[HANDLE], toStringValue(value));
    }

    get outerHTML() {
      return native.nodeOuterHtml(this[HANDLE]);
    }

    set outerHTML(value) {
      const parent = this.parentNode;
      if (!parent) {
        return;
      }
      this.insertAdjacentHTML("beforebegin", toStringValue(value));
      parent.removeChild(this);
    }

    insertAdjacentHTML(position, html) {
      const where = String(position).toLowerCase();
      const documentRef = this.ownerDocument || document;
      const fragment = documentRef.createDocumentFragment();
      fragment.innerHTML = toStringValue(html);
      const moving = fragment.childNodes.toArray();

      switch (where) {
        case "beforebegin": {
          if (!this.parentNode) {
            throw new Error("Cannot insert beforebegin without parent");
          }
          for (const node of moving) {
            this.parentNode.insertBefore(node, this);
          }
          return;
        }
        case "afterbegin": {
          const reference = this.firstChild;
          for (const node of moving) {
            this.insertBefore(node, reference);
          }
          return;
        }
        case "beforeend": {
          for (const node of moving) {
            this.appendChild(node);
          }
          return;
        }
        case "afterend": {
          if (!this.parentNode) {
            throw new Error("Cannot insert afterend without parent");
          }
          const reference = this.nextSibling;
          for (const node of moving) {
            this.parentNode.insertBefore(node, reference);
          }
          return;
        }
        default:
          throw new Error("Unsupported position for insertAdjacentHTML");
      }
    }

    matches(selector) {
      const localMatch = elementMatchesSelectorList(this, selector);
      if (localMatch !== null) {
        return localMatch;
      }

      const scope = this.parentNode || this.ownerDocument || document;
      return scope
        .querySelectorAll(String(selector))
        .toArray()
        .includes(this);
    }

    closest(selector) {
      const query = String(selector);
      let cursor = this;
      while (cursor) {
        if (cursor.nodeType === Node.ELEMENT_NODE && cursor.matches(query)) {
          return cursor;
        }
        cursor = cursor.parentElement;
      }
      return null;
    }

    getElementsByClassName(name) {
      const query = "." + String(name).trim().replace(/\s+/g, ".");
      return new HTMLCollection(() => this.querySelectorAll(query).toArray().filter((node) => node.nodeType === Node.ELEMENT_NODE));
    }

    getElementsByTagName(name) {
      const query = String(name).toLowerCase();
      return new HTMLCollection(() => this.querySelectorAll(query === "*" ? "*" : query).toArray().filter((node) => node.nodeType === Node.ELEMENT_NODE));
    }

    getBoundingClientRect() {
      return new DOMRect(0, 0, 0, 0);
    }

    getClientRects() {
      return [];
    }
  }

  class HTMLElement extends Element {
    constructor(handleOrName = "div", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(handleOrName, ownerDocumentHandle, marker);
    }

    get disabled() {
      return this.hasAttribute("disabled");
    }

    set disabled(value) {
      this.toggleAttribute("disabled", Boolean(value));
    }

    get name() {
      return this.getAttribute("name") || "";
    }

    set name(value) {
      this.setAttribute("name", toStringValue(value));
    }

    get type() {
      return this.getAttribute("type") || "";
    }

    set type(value) {
      this.setAttribute("type", toStringValue(value));
    }

    get value() {
      if (this.localName === "textarea") {
        return this.textContent || "";
      }
      return this.getAttribute("value") || "";
    }

    set value(next) {
      if (this.localName === "textarea") {
        this.textContent = toStringValue(next);
        return;
      }
      this.setAttribute("value", toStringValue(next));
    }

    get checked() {
      return this.hasAttribute("checked");
    }

    set checked(value) {
      this.toggleAttribute("checked", Boolean(value));
    }

    get form() {
      let cursor = this.parentElement;
      while (cursor) {
        if (cursor.localName === "form") {
          return cursor;
        }
        cursor = cursor.parentElement;
      }
      return null;
    }
  }

  class HTMLInputElement extends HTMLElement {
    constructor(handleOrName = "input", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(marker === INTERNAL ? handleOrName : "input", ownerDocumentHandle, marker);
    }
  }

  class HTMLButtonElement extends HTMLElement {
    constructor(handleOrName = "button", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(marker === INTERNAL ? handleOrName : "button", ownerDocumentHandle, marker);
    }
  }

  class HTMLSelectElement extends HTMLElement {
    constructor(handleOrName = "select", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(marker === INTERNAL ? handleOrName : "select", ownerDocumentHandle, marker);
    }

    get options() {
      return new HTMLCollection(() => this.getElementsByTagName("option").toArray());
    }
  }

  class HTMLOptionElement extends HTMLElement {
    constructor(handleOrName = "option", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(marker === INTERNAL ? handleOrName : "option", ownerDocumentHandle, marker);
    }
  }

  class HTMLTextAreaElement extends HTMLElement {
    constructor(handleOrName = "textarea", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(marker === INTERNAL ? handleOrName : "textarea", ownerDocumentHandle, marker);
    }
  }

  class HTMLLabelElement extends HTMLElement {
    constructor(handleOrName = "label", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(marker === INTERNAL ? handleOrName : "label", ownerDocumentHandle, marker);
    }
  }

  class HTMLFormElement extends HTMLElement {
    constructor(handleOrName = "form", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(marker === INTERNAL ? handleOrName : "form", ownerDocumentHandle, marker);
    }

    get elements() {
      const self = this;
      return new HTMLCollection(() => {
        const values = [];
        walkDescendants(self, (node) => {
          if (node.nodeType !== Node.ELEMENT_NODE) {
            return;
          }
          const name = node.localName;
          if (name === "input" || name === "button" || name === "select" || name === "option" || name === "textarea" || name === "label") {
            values.push(node);
          }
        });
        return values;
      });
    }
  }

  class SVGElement extends Element {
    constructor(handleOrName = "svg", ownerDocumentHandle = initialDocumentHandle, marker = null) {
      super(marker === INTERNAL ? handleOrName : "svg", ownerDocumentHandle, marker);
    }
  }

  class DOMRect {
    constructor(x = 0, y = 0, width = 0, height = 0) {
      this.x = Number(x);
      this.y = Number(y);
      this.width = Number(width);
      this.height = Number(height);
      this.top = this.y;
      this.left = this.x;
      this.right = this.x + this.width;
      this.bottom = this.y + this.height;
    }

    toJSON() {
      return {
        x: this.x,
        y: this.y,
        width: this.width,
        height: this.height,
        top: this.top,
        right: this.right,
        bottom: this.bottom,
        left: this.left
      };
    }
  }

  class MutationObserver {
    constructor(callback) {
      this._callback = typeof callback === "function" ? callback : null;
      this._records = [];
    }

    observe() {}

    disconnect() {
      this._records = [];
    }

    takeRecords() {
      const records = this._records;
      this._records = [];
      return records;
    }
  }

  class ResizeObserver {
    constructor(callback) {
      this._callback = typeof callback === "function" ? callback : null;
    }

    observe() {}

    unobserve() {}

    disconnect() {}
  }

  class DOMImplementation {
    constructor(ownerDocument) {
      this._ownerDocument = ownerDocument;
    }

    createDocument(_namespace, qualifiedName, doctype) {
      const created = this.createHTMLDocument("");
      if (qualifiedName) {
        const root = created.createElement(String(qualifiedName));
        created.body.appendChild(root);
      }
      if (doctype) {
        created.appendChild(doctype);
      }
      return created;
    }

    createHTMLDocument(title = "") {
      const createdWindow = createNativeWindow();
      const created = createdWindow.document;
      if (title) {
        const titleElement = created.createElement("title");
        titleElement.textContent = String(title);
        created.head.appendChild(titleElement);
      }
      return created;
    }

    createDocumentType(qualifiedName, publicId = "", systemId = "") {
      return this._ownerDocument.createDocumentType(qualifiedName, publicId, systemId);
    }

    hasFeature() {
      return true;
    }
  }

  class Document extends Node {
    constructor(handle, windowHandle) {
      super(Number(handle), Number(handle), Node.DOCUMENT_NODE, "#document");
      this._windowHandle = Number(windowHandle);
      this.implementation = new DOMImplementation(this);
    }

    get defaultView() {
      return WINDOW_CACHE.get(this._windowHandle) || null;
    }

    get documentElement() {
      return wrapNode(native.windowDocumentElement(this._windowHandle));
    }

    get head() {
      return wrapNode(native.windowHead(this._windowHandle));
    }

    get body() {
      return wrapNode(native.windowBody(this._windowHandle));
    }

    createElement(name) {
      const handle = native.documentCreateElement(this[HANDLE], String(name).toLowerCase());
      return wrapNode(handle);
    }

    createElementNS(_namespace, qualifiedName) {
      const value = String(qualifiedName);
      const localName = value.includes(":") ? value.split(":").pop() : value;
      return this.createElement(localName);
    }

    createTextNode(data) {
      const handle = native.documentCreateTextNode(this[HANDLE], toStringValue(data));
      return wrapNode(handle);
    }

    createComment(data) {
      const handle = native.documentCreateComment(this[HANDLE], toStringValue(data));
      return wrapNode(handle);
    }

    createDocumentFragment() {
      const handle = native.documentCreateDocumentFragment(this[HANDLE]);
      return wrapNode(handle);
    }

    createDocumentType(name, publicId = "", systemId = "") {
      return new DocumentType(name, publicId, systemId, this[HANDLE]);
    }

    getElementById(id) {
      return wrapNode(native.documentGetElementById(this[HANDLE], String(id)));
    }

    querySelector(selector) {
      const local = this.querySelectorAll(selector);
      if (String(selector).includes(",") && local.length > 0) {
        return local.item(0);
      }
      return wrapNode(native.documentQuerySelector(this[HANDLE], String(selector)));
    }

    querySelectorAll(selector) {
      if (String(selector).includes(",")) {
        const matches = [];
        walkDescendants(this, (node) => {
          if (node.nodeType === Node.ELEMENT_NODE && node.matches(selector)) {
            matches.push(node);
          }
        });
        return new NodeList(() => matches, { static: true });
      }
      const handles = native.documentQuerySelectorAll(this[HANDLE], String(selector));
      return new NodeList(() => wrapHandleArray(handles), { static: true });
    }

    getElementsByClassName(name) {
      const query = "." + String(name).trim().replace(/\s+/g, ".");
      return new HTMLCollection(() => this.querySelectorAll(query).toArray().filter((node) => node.nodeType === Node.ELEMENT_NODE));
    }

    getElementsByTagName(name) {
      const query = String(name).toLowerCase();
      return new HTMLCollection(() => this.querySelectorAll(query === "*" ? "*" : query).toArray().filter((node) => node.nodeType === Node.ELEMENT_NODE));
    }
  }

  class Window extends EventTarget {
    constructor(handle, doc) {
      if (handle == null || (typeof handle === "object" && doc == null)) {
        const options = handle && typeof handle === "object" ? handle : {};
        const created = createNativeWindow();
        if (options.url && created.happyDOM && typeof created.happyDOM.setURL === "function") {
          created.happyDOM.setURL(options.url);
        }
        return created;
      }

      super();
      this[HANDLE] = Number(handle);
      this.document = doc;
      this.window = this;
      this.self = this;
      this.globalThis = globalThis;
      this.closed = false;
      this.navigator = globalThis.navigator || { userAgent: "zig-dom" };
      this.location = {
        href: "http://localhost/",
        protocol: "http:",
        host: "localhost",
        hostname: "localhost",
        port: "",
        pathname: "/",
        search: "",
        hash: ""
      };
      this.happyDOM = {
        reset: () => {
          if (this.document && this.document.body) {
            this.document.body.innerHTML = "";
          }
        },
        setURL: (url) => {
          const next = new URL(String(url), this.location.href);
          this.location.href = next.href;
          this.location.protocol = next.protocol;
          this.location.host = next.host;
          this.location.hostname = next.hostname;
          this.location.port = next.port;
          this.location.pathname = next.pathname;
          this.location.search = next.search;
          this.location.hash = next.hash;
        },
        whenAsyncComplete: () => Promise.resolve(),
        abort() {}
      };
    }

    close() {
      this.closed = true;
    }

    getComputedStyle(element) {
      const source = element && typeof element.getAttribute === "function" ? element.getAttribute("style") || "" : "";
      const declarations = new Map();
      for (const piece of source.split(";")) {
        const split = piece.split(":");
        if (split.length < 2) {
          continue;
        }
        const key = split[0].trim();
        const value = split.slice(1).join(":").trim();
        if (key.length > 0) {
          declarations.set(key, value);
        }
      }
      return {
        getPropertyValue(name) {
          return declarations.get(String(name)) || "";
        }
      };
    }

    matchMedia(query) {
      return {
        media: String(query),
        matches: false,
        onchange: null,
        addListener() {},
        removeListener() {},
        addEventListener() {},
        removeEventListener() {},
        dispatchEvent() {
          return false;
        }
      };
    }
  }

  function wrapHandleArray(handles) {
    if (!Array.isArray(handles)) {
      return [];
    }
    const out = [];
    for (const handle of handles) {
      const wrapped = wrapNode(handle);
      if (wrapped) {
        out.push(wrapped);
      }
    }
    return out;
  }

  function elementConstructorByName(localName) {
    switch (String(localName).toLowerCase()) {
      case "input":
        return HTMLInputElement;
      case "button":
        return HTMLButtonElement;
      case "form":
        return HTMLFormElement;
      case "select":
        return HTMLSelectElement;
      case "option":
        return HTMLOptionElement;
      case "textarea":
        return HTMLTextAreaElement;
      case "label":
        return HTMLLabelElement;
      case "svg":
        return SVGElement;
      default:
        return HTMLElement;
    }
  }

  function wrapElementHandle(handle, ownerDocumentHandle) {
    const localName = native.nodeName(handle).toLowerCase();
    const Ctor = elementConstructorByName(localName);
    return new Ctor(Number(handle), Number(ownerDocumentHandle), INTERNAL);
  }

  function wrapNode(handle) {
    const numericHandle = Number(handle || 0);
    if (!numericHandle) {
      return null;
    }
    const cached = NODE_CACHE.get(numericHandle);
    if (cached) {
      return cached;
    }

    const nodeType = Number(native.nodeType(numericHandle));
    const ownerDocumentHandle = Number(native.nodeOwnerDocument(numericHandle) || numericHandle);
    let wrapped;

    switch (nodeType) {
      case Node.DOCUMENT_NODE: {
        const windowHandle = asWindowHandleFromNode(numericHandle);
        wrapped = new Document(numericHandle, windowHandle);
        break;
      }
      case Node.ELEMENT_NODE:
        wrapped = wrapElementHandle(numericHandle, ownerDocumentHandle);
        break;
      case Node.TEXT_NODE:
        wrapped = new Text(numericHandle, ownerDocumentHandle, INTERNAL);
        break;
      case Node.COMMENT_NODE:
        wrapped = new Comment(numericHandle, ownerDocumentHandle, INTERNAL);
        break;
      case Node.DOCUMENT_FRAGMENT_NODE:
        wrapped = new DocumentFragment(ownerDocumentHandle, INTERNAL, numericHandle);
        break;
      default:
        wrapped = new Node(numericHandle, ownerDocumentHandle, nodeType, native.nodeName(numericHandle));
        break;
    }

    NODE_CACHE.set(numericHandle, wrapped);
    return wrapped;
  }

  function cloneNodeValue(source, deep) {
    const owner = source.ownerDocument || document;
    let clone;
    switch (source.nodeType) {
      case Node.ELEMENT_NODE: {
        clone = owner.createElement(source.localName);
        for (const name of source.getAttributeNames()) {
          clone.setAttribute(name, source.getAttribute(name));
        }
        break;
      }
      case Node.TEXT_NODE:
        clone = owner.createTextNode(source.data || source.textContent || "");
        break;
      case Node.COMMENT_NODE:
        clone = owner.createComment(source.data || source.textContent || "");
        break;
      case Node.DOCUMENT_FRAGMENT_NODE:
        clone = owner.createDocumentFragment();
        break;
      case Node.DOCUMENT_TYPE_NODE:
        clone = owner.createDocumentType(source.name || source.nodeName || "html", source.publicId || "", source.systemId || "");
        break;
      default:
        clone = owner.createTextNode(source.textContent || "");
        break;
    }

    if (deep) {
      for (const child of source.childNodes.toArray()) {
        clone.appendChild(cloneNodeValue(child, true));
      }
    }
    return clone;
  }

  function createNativeWindow() {
    const windowHandle = native.createWindow();
    const documentHandle = native.windowDocument(windowHandle);
    const doc = wrapNode(documentHandle);
    const win = new Window(windowHandle, doc);
    WINDOW_CACHE.set(windowHandle, win);
    if (doc && doc.nodeType === Node.DOCUMENT_NODE) {
      doc._windowHandle = windowHandle;
    }
    return win;
  }

  const document = wrapNode(initialDocumentHandle);
  const window = new Window(initialWindowHandle, document);
  WINDOW_CACHE.set(initialWindowHandle, window);
  if (document && document.nodeType === Node.DOCUMENT_NODE) {
    document._windowHandle = initialWindowHandle;
  }

  Object.assign(globalThis, {
    EventTarget,
    Event,
    CustomEvent,
    MouseEvent,
    Node,
    NodeList,
    HTMLCollection,
    CharacterData,
    Text,
    Comment,
    DocumentType,
    DocumentFragment,
    Element,
    HTMLElement,
    HTMLInputElement,
    HTMLButtonElement,
    HTMLFormElement,
    HTMLSelectElement,
    HTMLOptionElement,
    HTMLTextAreaElement,
    HTMLLabelElement,
    SVGElement,
    DOMRect,
    MutationObserver,
    ResizeObserver,
    Window,
    Document,
    window,
    self: window,
    document
  });

  window.Node = Node;
  window.Element = Element;
  window.HTMLElement = HTMLElement;
  window.SVGElement = SVGElement;
  window.EventTarget = EventTarget;
  window.Event = Event;
  window.CustomEvent = CustomEvent;
  window.MouseEvent = MouseEvent;
  window.NodeList = NodeList;
  window.HTMLCollection = HTMLCollection;
  window.DocumentFragment = DocumentFragment;
  window.Text = Text;
  window.Comment = Comment;
  window.DocumentType = DocumentType;
  window.DOMRect = DOMRect;
  window.MutationObserver = MutationObserver;
  window.ResizeObserver = ResizeObserver;

  delete globalThis.__zigDomNative;
  delete globalThis.__zigDomWindowHandle;
  delete globalThis.__zigDomDocumentHandle;
})();

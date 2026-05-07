import { GlobalRegistrator } from "zig-dom/global-registrator";

const PropertySymbol = Object.freeze({
  ownerWindow: Symbol.for("zig-dom.ownerWindow"),
  ownerDocument: Symbol.for("zig-dom.ownerDocument"),
  nodeArray: Symbol.for("zig-dom.nodeArray"),
  classList: Symbol.for("zig-dom.classList"),
});

const pick = (name) => globalThis[name];

const Window = pick("Window");
const Document = pick("Document");
const Node = pick("Node");
const Element = pick("Element");
const HTMLElement = pick("HTMLElement");
const DocumentFragment = pick("DocumentFragment");
const DocumentType = pick("DocumentType");
const CharacterData = pick("CharacterData");
const Text = pick("Text");
const Comment = pick("Comment");
const NodeList = pick("NodeList");
const HTMLCollection = pick("HTMLCollection");
const EventTarget = pick("EventTarget");
const Event = pick("Event");
const CustomEvent = pick("CustomEvent");
const MouseEvent = pick("MouseEvent");
const MutationObserver = pick("MutationObserver");
const ResizeObserver = pick("ResizeObserver");
const DOMException = pick("DOMException");
const DOMRect = pick("DOMRect");

const HTMLAnchorElement = pick("HTMLAnchorElement") || HTMLElement;
const HTMLButtonElement = pick("HTMLButtonElement") || HTMLElement;
const HTMLFormElement = pick("HTMLFormElement") || HTMLElement;
const HTMLIFrameElement = pick("HTMLIFrameElement") || HTMLElement;
const HTMLInputElement = pick("HTMLInputElement") || HTMLElement;
const HTMLLabelElement = pick("HTMLLabelElement") || HTMLElement;
const HTMLLIElement = pick("HTMLLIElement") || HTMLElement;
const HTMLOListElement = pick("HTMLOListElement") || HTMLElement;
const HTMLOptionElement = pick("HTMLOptionElement") || HTMLElement;
const HTMLSelectElement = pick("HTMLSelectElement") || HTMLElement;
const HTMLTextAreaElement = pick("HTMLTextAreaElement") || HTMLElement;
const HTMLUListElement = pick("HTMLUListElement") || HTMLElement;

class Page {
  constructor(options) {
    this.window = new Window(options);
    this.mainFrame = { document: this.window.document };
  }

  get content() {
    return this.window.document.documentElement?.outerHTML ?? "";
  }

  set content(value) {
    this.window.document.body.innerHTML = String(value ?? "");
  }

  get url() {
    return this.window.location?.href ?? globalThis.location?.href ?? "";
  }

  set url(next) {
    if (this.window.happyDOM && typeof this.window.happyDOM.setURL === "function") {
      this.window.happyDOM.setURL(next);
    } else if (this.window.location) {
      this.window.location.href = String(next);
    }
  }

  async waitUntilComplete() {}

  abort() {}

  close() {}
}

class BrowserContext {
  #pages = [];

  newPage(options) {
    const page = new Page(options);
    this.#pages.push(page);
    return page;
  }

  close() {
    this.#pages.length = 0;
  }
}

class Browser {
  #context = new BrowserContext();

  static async create() {
    return new Browser();
  }

  newPage(options) {
    return this.#context.newPage(options);
  }

  defaultContext() {
    return this.#context;
  }

  close() {
    this.#context.close();
  }
}

export {
  Browser,
  BrowserContext,
  CharacterData,
  Comment,
  CustomEvent,
  Document,
  DocumentFragment,
  DocumentType,
  DOMException,
  DOMRect,
  Element,
  Event,
  EventTarget,
  GlobalRegistrator,
  HTMLAnchorElement,
  HTMLButtonElement,
  HTMLCollection,
  HTMLElement,
  HTMLFormElement,
  HTMLIFrameElement,
  HTMLInputElement,
  HTMLLabelElement,
  HTMLLIElement,
  HTMLOListElement,
  HTMLOptionElement,
  HTMLSelectElement,
  HTMLTextAreaElement,
  HTMLUListElement,
  MouseEvent,
  MutationObserver,
  Node,
  NodeList,
  Page,
  PropertySymbol,
  ResizeObserver,
  Text,
  Window,
};

export default {
  Browser,
  BrowserContext,
  CharacterData,
  Comment,
  CustomEvent,
  Document,
  DocumentFragment,
  DocumentType,
  DOMException,
  DOMRect,
  Element,
  Event,
  EventTarget,
  GlobalRegistrator,
  HTMLAnchorElement,
  HTMLButtonElement,
  HTMLCollection,
  HTMLElement,
  HTMLFormElement,
  HTMLIFrameElement,
  HTMLInputElement,
  HTMLLabelElement,
  HTMLLIElement,
  HTMLOListElement,
  HTMLOptionElement,
  HTMLSelectElement,
  HTMLTextAreaElement,
  HTMLUListElement,
  MouseEvent,
  MutationObserver,
  Node,
  NodeList,
  Page,
  PropertySymbol,
  ResizeObserver,
  Text,
  Window,
};

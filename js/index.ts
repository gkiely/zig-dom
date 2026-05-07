import { GlobalRegistrator } from "./global-registrator.ts";

export const PropertySymbol = Object.freeze({
  ownerWindow: Symbol.for("zig-dom.ownerWindow"),
  ownerDocument: Symbol.for("zig-dom.ownerDocument"),
  nodeArray: Symbol.for("zig-dom.nodeArray"),
  classList: Symbol.for("zig-dom.classList")
});

type NativeExports = Record<string, unknown>;

const globals = globalThis as unknown as NativeExports;

const nativeDOM: NativeExports = {
  GlobalRegistrator,
  PropertySymbol,
  Window: globals.Window,
  Document: globals.Document,
  DocumentType: globals.DocumentType,
  DocumentFragment: globals.DocumentFragment,
  Node: globals.Node,
  Element: globals.Element,
  HTMLElement: globals.HTMLElement,
  SVGElement: globals.SVGElement,
  CharacterData: globals.CharacterData,
  Text: globals.Text,
  Comment: globals.Comment,
  NodeList: globals.NodeList,
  HTMLCollection: globals.HTMLCollection,
  EventTarget: globals.EventTarget,
  Event: globals.Event,
  CustomEvent: globals.CustomEvent,
  MouseEvent: globals.MouseEvent,
  DOMRect: globals.DOMRect,
  DOMException: globals.DOMException,
  MutationObserver: globals.MutationObserver,
  ResizeObserver: globals.ResizeObserver,
  HTMLAnchorElement: globals.HTMLAnchorElement,
  HTMLButtonElement: globals.HTMLButtonElement,
  HTMLFormElement: globals.HTMLFormElement,
  HTMLIFrameElement: globals.HTMLIFrameElement,
  HTMLInputElement: globals.HTMLInputElement,
  HTMLLabelElement: globals.HTMLLabelElement,
  HTMLLIElement: globals.HTMLLIElement,
  HTMLOListElement: globals.HTMLOListElement,
  HTMLOptionElement: globals.HTMLOptionElement,
  HTMLSelectElement: globals.HTMLSelectElement,
  HTMLTextAreaElement: globals.HTMLTextAreaElement,
  HTMLUListElement: globals.HTMLUListElement
};

export const {
  Window,
  Document,
  DocumentType,
  DocumentFragment,
  Node,
  Element,
  HTMLElement,
  SVGElement,
  CharacterData,
  Text,
  Comment,
  NodeList,
  HTMLCollection,
  EventTarget,
  Event,
  CustomEvent,
  MouseEvent,
  DOMRect,
  DOMException,
  MutationObserver,
  ResizeObserver,
  HTMLAnchorElement,
  HTMLButtonElement,
  HTMLFormElement,
  HTMLIFrameElement,
  HTMLInputElement,
  HTMLLabelElement,
  HTMLLIElement,
  HTMLOListElement,
  HTMLOptionElement,
  HTMLSelectElement,
  HTMLTextAreaElement,
  HTMLUListElement
} = nativeDOM;

export { GlobalRegistrator };
export default nativeDOM;

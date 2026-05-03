import { Node } from "./Node.ts";
import type { Window } from "./Window.ts";

export class DocumentFragment extends Node {
  constructor(window: Window, handle: number, nodeType = Node.DOCUMENT_FRAGMENT_NODE) {
    super(window, handle, nodeType);
  }
}

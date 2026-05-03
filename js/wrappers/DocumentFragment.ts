import { Node } from "./Node.js";
import type { Window } from "./Window.js";

export class DocumentFragment extends Node {
  constructor(window: Window, handle: number) {
    super(window, handle);
  }
}

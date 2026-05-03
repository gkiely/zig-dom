import { Node } from "./Node.ts";
import type { Window } from "./Window.ts";

export class DocumentFragment extends Node {
  constructor(window: Window, handle: number) {
    super(window, handle);
  }
}

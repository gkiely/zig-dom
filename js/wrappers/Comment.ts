import { Node } from "./Node.ts";
import type { Window } from "./Window.ts";

export class Comment extends Node {
  constructor(window: Window, handle: number, nodeType = Node.COMMENT_NODE) {
    super(window, handle, nodeType);
  }

  get data(): string {
    return this.textContent;
  }

  set data(value: string) {
    this.textContent = value;
  }
}

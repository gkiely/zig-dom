import { Node } from "./Node.ts";
import type { Window } from "./Window.ts";

export class Comment extends Node {
  constructor(window: Window, handle: number) {
    super(window, handle);
  }

  get data(): string {
    return this.textContent;
  }

  set data(value: string) {
    this.textContent = value;
  }
}

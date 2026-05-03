import { CharacterData } from "./CharacterData.ts";
import { Node } from "./Node.ts";
import type { Window } from "./Window.ts";

export class Comment extends CharacterData {
  constructor(window: Window, handle: number, nodeType = Node.COMMENT_NODE) {
    super(window, handle, nodeType);
  }
}

import { CharacterData } from "./CharacterData.ts";
import { ZigDOMException } from "./DOMException.ts";
import { Node } from "./Node.ts";
import { notifySplitTextMutation } from "./Range.ts";
import type { Window } from "./Window.ts";

export class Text extends CharacterData {
  constructor(window: Window, handle: number, nodeType = Node.TEXT_NODE) {
    super(window, handle, nodeType);
  }

  splitText(offset: number): Text {
    if (!Number.isInteger(offset) || offset < 0 || offset > this.data.length) {
      throw new ZigDOMException("The index is not in the allowed range.", "IndexSizeError", 1);
    }

    const original = this.data;
    const originalLength = original.length;
    const head = original.slice(0, offset);
    const tail = original.slice(offset);
    const parent = this.parentNode;
    const oldIndex = parent ? parent.childNodes.toArray().indexOf(this) : -1;
    this._setTextContentWithoutRangeNotification(head);

    const document = this.ownerDocument;
    if (!document) {
      throw new Error("splitText() requires an owner document");
    }

    const sibling = document.createTextNode(tail) as Text;
    if (parent) {
      parent.insertBefore(sibling, this.nextSibling);
    }

    notifySplitTextMutation(this, sibling, offset, originalLength, parent, oldIndex);

    return sibling;
  }

  get wholeText(): string {
    let start: Node = this;
    while (start.previousSibling && start.previousSibling.nodeType === Node.TEXT_NODE) {
      start = start.previousSibling;
    }

    const parts: string[] = [];
    let cursor: Node | null = start;
    while (cursor && cursor.nodeType === Node.TEXT_NODE) {
      parts.push((cursor as Text).data);
      cursor = cursor.nextSibling;
    }

    return parts.join("");
  }
}

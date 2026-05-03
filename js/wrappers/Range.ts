import type { Node } from "./Node.ts";

type SerializableNode = {
  nodeType: number;
  textContent: string;
  childNodes?: { toArray?: () => unknown[] };
};

export class Range {
  #startContainer: Node | null = null;
  #endContainer: Node | null = null;
  #startOffset = 0;
  #endOffset = 0;

  get startContainer(): Node {
    if (!this.#startContainer) {
      throw new Error("Range startContainer is not set");
    }
    return this.#startContainer;
  }

  get endContainer(): Node {
    if (!this.#endContainer) {
      throw new Error("Range endContainer is not set");
    }
    return this.#endContainer;
  }

  get startOffset(): number {
    return this.#startOffset;
  }

  get endOffset(): number {
    return this.#endOffset;
  }

  get collapsed(): boolean {
    return this.#startContainer === this.#endContainer && this.#startOffset === this.#endOffset;
  }

  setStart(node: Node, offset: number): void {
    this.#startContainer = node;
    this.#startOffset = offset;
    if (!this.#endContainer) {
      this.#endContainer = node;
      this.#endOffset = offset;
    }
  }

  setEnd(node: Node, offset: number): void {
    this.#endContainer = node;
    this.#endOffset = offset;
    if (!this.#startContainer) {
      this.#startContainer = node;
      this.#startOffset = offset;
    }
  }

  selectNodeContents(node: Node): void {
    const childCount = node.childNodes.length;
    this.setStart(node, 0);
    this.setEnd(node, childCount);
  }

  cloneRange(): Range {
    const clone = new Range();
    if (this.#startContainer) {
      clone.setStart(this.#startContainer, this.#startOffset);
    }
    if (this.#endContainer) {
      clone.setEnd(this.#endContainer, this.#endOffset);
    }
    return clone;
  }

  toString(): string {
    if (!this.#startContainer || !this.#endContainer) {
      return "";
    }

    if (this.#startContainer !== this.#endContainer) {
      const startContainer = this.#startContainer as unknown as {
        nodeType: number;
        textContent: string;
        getRootNode: () => {
          nodeType: number;
          textContent: string;
          childNodes?: { toArray?: () => unknown[] };
        };
      };
      const endContainer = this.#endContainer as unknown as {
        nodeType: number;
        textContent: string;
        getRootNode: () => {
          nodeType: number;
          textContent: string;
          childNodes?: { toArray?: () => unknown[] };
        };
      };

      if ((startContainer.nodeType !== 3 && startContainer.nodeType !== 8) ||
        (endContainer.nodeType !== 3 && endContainer.nodeType !== 8)) {
        return "";
      }

      const startRoot = startContainer.getRootNode();
      const endRoot = endContainer.getRootNode();
      if (startRoot !== endRoot) {
        return "";
      }

      const textNodes = collectTextNodes(startRoot as SerializableNode);
      const startIndex = textNodes.indexOf(startContainer as unknown as SerializableNode);
      const endIndex = textNodes.indexOf(endContainer as unknown as SerializableNode);
      if (startIndex === -1 || endIndex === -1 || startIndex > endIndex) {
        return "";
      }

      const parts: string[] = [];
      for (let index = startIndex; index <= endIndex; index += 1) {
        const textNode = textNodes[index];
        if (!textNode) {
          continue;
        }

        const text = textNode.textContent ?? "";
        if (index === startIndex && index === endIndex) {
          const start = Math.max(0, Math.min(this.#startOffset, text.length));
          const end = Math.max(start, Math.min(this.#endOffset, text.length));
          parts.push(text.slice(start, end));
        } else if (index === startIndex) {
          const start = Math.max(0, Math.min(this.#startOffset, text.length));
          parts.push(text.slice(start));
        } else if (index === endIndex) {
          const end = Math.max(0, Math.min(this.#endOffset, text.length));
          parts.push(text.slice(0, end));
        } else {
          parts.push(text);
        }
      }

      return parts.join("");
    }

    const container = this.#startContainer as unknown as {
      nodeType: number;
      textContent: string;
      childNodes?: { toArray?: () => Array<{ textContent: string }> };
    };

    if (container.nodeType === 3 || container.nodeType === 8) {
      const text = container.textContent ?? "";
      const start = Math.max(0, Math.min(this.#startOffset, text.length));
      const end = Math.max(start, Math.min(this.#endOffset, text.length));
      return text.slice(start, end);
    }

    const children = container.childNodes?.toArray?.() ?? [];
    if (children.length === 0) {
      return container.textContent ?? "";
    }

    const start = Math.max(0, Math.min(this.#startOffset, children.length));
    const end = Math.max(start, Math.min(this.#endOffset, children.length));
    return children.slice(start, end).map((child) => child.textContent ?? "").join("");
  }
}

function collectTextNodes(node: SerializableNode): SerializableNode[] {
  if (node.nodeType === 3 || node.nodeType === 8) {
    return [node];
  }

  const children = node.childNodes?.toArray?.() ?? [];
  const textNodes: SerializableNode[] = [];
  for (const child of children) {
    textNodes.push(...collectTextNodes(child as SerializableNode));
  }
  return textNodes;
}

export class Selection {
  #ranges: Range[] = [];

  get rangeCount(): number {
    return this.#ranges.length;
  }

  addRange(range: Range): void {
    this.#ranges = [range];
  }

  removeAllRanges(): void {
    this.#ranges = [];
  }

  getRangeAt(index: number): Range {
    const range = this.#ranges[index];
    if (!range) {
      throw new Error(`No range at index ${index}`);
    }
    return range;
  }

  toString(): string {
    return this.#ranges.map((range) => range.toString()).join("");
  }
}

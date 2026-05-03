import type { Node } from "./Node.ts";

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
    return "";
  }
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
    return "";
  }
}

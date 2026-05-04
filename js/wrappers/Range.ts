import { ZigDOMException } from "./DOMException.ts";
import type { Node } from "./Node.ts";

type SerializableNode = {
  nodeType: number;
  textContent: string;
  childNodes?: { toArray?: () => unknown[] };
};

export class Range {
  static readonly START_TO_START = 0;
  static readonly START_TO_END = 1;
  static readonly END_TO_END = 2;
  static readonly END_TO_START = 3;

  #startContainer: Node | null = null;
  #endContainer: Node | null = null;
  #startOffset = 0;
  #endOffset = 0;

  readonly START_TO_START = Range.START_TO_START;
  readonly START_TO_END = Range.START_TO_END;
  readonly END_TO_END = Range.END_TO_END;
  readonly END_TO_START = Range.END_TO_START;

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

  get commonAncestorContainer(): Node {
    if (!this.#startContainer || !this.#endContainer) {
      throw new Error("Range boundaries are not set");
    }

    const startAncestors = collectAncestorChain(this.#startContainer);
    const endAncestors = new Set(collectAncestorChain(this.#endContainer));
    for (const ancestor of startAncestors) {
      if (endAncestors.has(ancestor)) {
        return ancestor;
      }
    }

    return this.#startContainer;
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

  setStartBefore(node: Node): void {
    const parent = parentOf(node);
    if (!parent) {
      throw new ZigDOMException("The object can not be found here.", "InvalidNodeTypeError", 24);
    }
    this.setStart(parent, childIndex(node));
  }

  setStartAfter(node: Node): void {
    const parent = parentOf(node);
    if (!parent) {
      throw new ZigDOMException("The object can not be found here.", "InvalidNodeTypeError", 24);
    }
    this.setStart(parent, childIndex(node) + 1);
  }

  setEndBefore(node: Node): void {
    const parent = parentOf(node);
    if (!parent) {
      throw new ZigDOMException("The object can not be found here.", "InvalidNodeTypeError", 24);
    }
    this.setEnd(parent, childIndex(node));
  }

  setEndAfter(node: Node): void {
    const parent = parentOf(node);
    if (!parent) {
      throw new ZigDOMException("The object can not be found here.", "InvalidNodeTypeError", 24);
    }
    this.setEnd(parent, childIndex(node) + 1);
  }

  selectNode(node: Node): void {
    this.setStartBefore(node);
    this.setEndAfter(node);
  }

  selectNodeContents(node: Node): void {
    const childCount = node.childNodes.length;
    this.setStart(node, 0);
    this.setEnd(node, childCount);
  }

  collapse(toStart = false): void {
    if (!this.#startContainer || !this.#endContainer) {
      return;
    }

    if (toStart) {
      this.#endContainer = this.#startContainer;
      this.#endOffset = this.#startOffset;
    } else {
      this.#startContainer = this.#endContainer;
      this.#startOffset = this.#endOffset;
    }
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

  comparePoint(node: Node, offset: number): -1 | 0 | 1 {
    if (!this.#startContainer || !this.#endContainer) {
      throw new Error("Range boundaries are not set");
    }

    if (rootOf(node) !== rootOf(this.#startContainer)) {
      throw new ZigDOMException("The object is in the wrong document.", "WrongDocumentError", 4);
    }

    if ((node as unknown as { nodeType?: number }).nodeType === 10) {
      throw new ZigDOMException("The object is in an invalid state.", "InvalidNodeTypeError", 24);
    }

    const normalizedOffset = normalizeOffset(offset, nodeLength(node));

    const beforeStart = compareBoundaryPointPositions(node, normalizedOffset, this.#startContainer, this.#startOffset) < 0;
    if (beforeStart) {
      return -1;
    }

    const afterEnd = compareBoundaryPointPositions(node, normalizedOffset, this.#endContainer, this.#endOffset) > 0;
    if (afterEnd) {
      return 1;
    }

    return 0;
  }

  isPointInRange(node: Node, offset: number): boolean {
    if (!node || typeof node !== "object" || typeof (node as unknown as { nodeType?: unknown }).nodeType !== "number") {
      throw new TypeError("Failed to execute 'isPointInRange' on 'Range': parameter 1 is not of type 'Node'.");
    }

    try {
      return this.comparePoint(node, offset) === 0;
    } catch (error) {
      const name = (error as { name?: string }).name ?? "";
      if (name === "WrongDocumentError" || name === "InvalidNodeTypeError") {
        return false;
      }
      if (name === "IndexSizeError") {
        throw error;
      }
      return false;
    }
  }

  intersectsNode(node: Node): boolean {
    if (!node || typeof node !== "object" || typeof (node as unknown as { nodeType?: unknown }).nodeType !== "number") {
      throw new TypeError("Failed to execute 'intersectsNode' on 'Range': parameter 1 is not of type 'Node'.");
    }

    if (!this.#startContainer || !this.#endContainer) {
      return false;
    }

    if (rootOf(node) !== rootOf(this.#startContainer)) {
      return false;
    }

    const parent = node.parentNode;
    if (!parent) {
      return true;
    }

    const offset = childIndex(node);
    if (this.comparePoint(parent, offset) === 1) {
      return false;
    }
    if (this.comparePoint(parent, offset + 1) === -1) {
      return false;
    }

    return true;
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

function collectAncestorChain(node: Node): Node[] {
  const chain: Node[] = [];
  let cursor: Node | null = node;
  while (cursor) {
    chain.push(cursor);
    cursor = parentOf(cursor);
  }
  return chain;
}

function rootOf(node: Node): Node {
  let cursor: Node = node;
  while (parentOf(cursor)) {
    cursor = parentOf(cursor) as Node;
  }
  return cursor;
}

function childIndex(node: Node): number {
  const parent = parentOf(node);
  if (!parent) {
    return 0;
  }
  return parent.childNodes.toArray().indexOf(node);
}

function nodeLength(node: Node): number {
  const nodeType = (node as unknown as { nodeType?: number }).nodeType ?? 0;
  if (nodeType === 3 || nodeType === 4 || nodeType === 7 || nodeType === 8) {
    const text = (node as unknown as { textContent?: string | null }).textContent ?? "";
    return text.length;
  }
  return node.childNodes.length;
}

function normalizeOffset(offset: number, max: number): number {
  if (!Number.isFinite(offset) || offset < 0 || offset > max) {
    throw new ZigDOMException("The index is not in the allowed range.", "IndexSizeError", 1);
  }
  return Math.floor(offset);
}

function isInclusiveAncestor(ancestor: Node, node: Node): boolean {
  let cursor: Node | null = node;
  while (cursor) {
    if (cursor === ancestor) {
      return true;
    }
    cursor = parentOf(cursor);
  }
  return false;
}

function compareBoundaryPointPositions(nodeA: Node, offsetA: number, nodeB: Node, offsetB: number): -1 | 0 | 1 {
  if (nodeA === nodeB) {
    if (offsetA < offsetB) return -1;
    if (offsetA > offsetB) return 1;
    return 0;
  }

  if (isInclusiveAncestor(nodeA, nodeB)) {
    let child = nodeB;
    while (parentOf(child) && parentOf(child) !== nodeA) {
      child = parentOf(child) as Node;
    }
    const index = childIndex(child);
    return index < offsetA ? 1 : -1;
  }

  if (isInclusiveAncestor(nodeB, nodeA)) {
    const inverted = compareBoundaryPointPositions(nodeB, offsetB, nodeA, offsetA);
    if (inverted === 0) return 0;
    return inverted === -1 ? 1 : -1;
  }

  const chainA = collectAncestorChain(nodeA);
  const chainB = collectAncestorChain(nodeB);
  let indexA = chainA.length - 1;
  let indexB = chainB.length - 1;

  while (indexA >= 0 && indexB >= 0 && chainA[indexA] === chainB[indexB]) {
    indexA -= 1;
    indexB -= 1;
  }

  const siblingA = chainA[Math.max(0, indexA)];
  const siblingB = chainB[Math.max(0, indexB)];
  const siblingAParent = siblingA ? parentOf(siblingA) : null;
  const siblingBParent = siblingB ? parentOf(siblingB) : null;
  if (!siblingA || !siblingB || !siblingAParent || siblingAParent !== siblingBParent) {
    return 0;
  }

  const siblings = siblingAParent.childNodes.toArray();
  const siblingAIndex = siblings.indexOf(siblingA);
  const siblingBIndex = siblings.indexOf(siblingB);
  if (siblingAIndex < siblingBIndex) {
    return -1;
  }
  return 1;
}

function parentOf(node: Node | null | undefined): Node | null {
  if (!node || typeof node !== "object") {
    return null;
  }
  return ((node as unknown as { parentNode?: Node | null }).parentNode ?? null) as Node | null;
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

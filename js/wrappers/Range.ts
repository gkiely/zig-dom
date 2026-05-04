import { ZigDOMException } from "./DOMException.ts";
import { Node } from "./Node.ts";

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

  constructor() {
    const trackedRef = new WeakRef(this);
    trackedRanges.add(trackedRef);
    trackedRangeFinalizer.register(this, trackedRef);
    trimTrackedRanges();
    const globalDocument = (globalThis as { document?: unknown }).document;
    if (isNodeLike(globalDocument) && globalDocument.nodeType === Node.DOCUMENT_NODE) {
      this.#startContainer = globalDocument;
      this.#endContainer = globalDocument;
      this.#startOffset = 0;
      this.#endOffset = 0;
    }
  }

  __applyCharacterDataMutation(node: Node, offset: number, count: number, dataLength: number): void {
    if (this.#startContainer === node) {
      this.#startOffset = adjustCharacterDataBoundary(this.#startOffset, offset, count, dataLength);
    }
    if (this.#endContainer === node) {
      this.#endOffset = adjustCharacterDataBoundary(this.#endOffset, offset, count, dataLength);
    }
  }

  __applySplitTextMutation(oldNode: Node, newNode: Node, offset: number, oldLength: number, parent: Node | null, oldIndex: number): void {
    const originalStartContainer = this.#startContainer;
    const originalStartOffset = this.#startOffset;
    const originalEndContainer = this.#endContainer;
    const originalEndOffset = this.#endOffset;

    if (originalStartContainer === oldNode) {
      this.#startOffset = adjustCharacterDataBoundary(originalStartOffset, offset, oldLength - offset, 0);
    }
    if (originalEndContainer === oldNode) {
      this.#endOffset = adjustCharacterDataBoundary(originalEndOffset, offset, oldLength - offset, 0);
    }

    if (parent && oldIndex >= 0) {
      if (this.#startContainer === parent && this.#startOffset >= oldIndex + 1) {
        this.#startOffset += 1;
      }
      if (this.#endContainer === parent && this.#endOffset >= oldIndex + 1) {
        this.#endOffset += 1;
      }

      if (originalStartContainer === oldNode && originalStartOffset > offset) {
        this.#startContainer = newNode;
        this.#startOffset = originalStartOffset - offset;
      }
      if (originalEndContainer === oldNode && originalEndOffset > offset) {
        this.#endContainer = newNode;
        this.#endOffset = originalEndOffset - offset;
      }
    }
  }

  __applyNodeRemoval(removedNode: Node, oldParent: Node, oldIndex: number): void {
    if (this.#startContainer && isInclusiveAncestor(removedNode, this.#startContainer)) {
      this.#startContainer = oldParent;
      this.#startOffset = oldIndex;
    } else if (this.#startContainer === oldParent && this.#startOffset > oldIndex) {
      this.#startOffset -= 1;
    }

    if (this.#endContainer && isInclusiveAncestor(removedNode, this.#endContainer)) {
      this.#endContainer = oldParent;
      this.#endOffset = oldIndex;
    } else if (this.#endContainer === oldParent && this.#endOffset > oldIndex) {
      this.#endOffset -= 1;
    }
  }

  __applyNodeInsertion(insertedNode: Node, newParent: Node, newIndex: number): void {
    if (this.#startContainer === newParent && this.#startOffset > newIndex) {
      this.#startOffset += 1;
    }
    if (this.#endContainer === newParent && this.#endOffset > newIndex) {
      this.#endOffset += 1;
    }
  }

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
    if (!isNodeLike(node)) {
      throw new TypeError("Failed to execute 'setStart' on 'Range': parameter 1 is not of type 'Node'.");
    }
    if (node.nodeType === Node.DOCUMENT_TYPE_NODE || node.nodeType === Node.ATTRIBUTE_NODE) {
      throw new ZigDOMException("The object is in an invalid state.", "InvalidNodeTypeError", 24);
    }

    const normalizedOffset = normalizeOffset(offset, nodeLength(node));
    this.#startContainer = node;
    this.#startOffset = normalizedOffset;
    if (!this.#endContainer || rootOf(node) !== rootOf(this.#endContainer) || compareBoundaryPointPositions(node, normalizedOffset, this.#endContainer, this.#endOffset) === 1) {
      this.#endContainer = node;
      this.#endOffset = normalizedOffset;
    }
  }

  setEnd(node: Node, offset: number): void {
    if (!isNodeLike(node)) {
      throw new TypeError("Failed to execute 'setEnd' on 'Range': parameter 1 is not of type 'Node'.");
    }
    if (node.nodeType === Node.DOCUMENT_TYPE_NODE || node.nodeType === Node.ATTRIBUTE_NODE) {
      throw new ZigDOMException("The object is in an invalid state.", "InvalidNodeTypeError", 24);
    }

    const normalizedOffset = normalizeOffset(offset, nodeLength(node));
    this.#endContainer = node;
    this.#endOffset = normalizedOffset;
    if (!this.#startContainer || rootOf(node) !== rootOf(this.#startContainer) || compareBoundaryPointPositions(node, normalizedOffset, this.#startContainer, this.#startOffset) === -1) {
      this.#startContainer = node;
      this.#startOffset = normalizedOffset;
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
    if (node.nodeType === Node.DOCUMENT_TYPE_NODE) {
      throw new ZigDOMException("The object is in an invalid state.", "InvalidNodeTypeError", 24);
    }
    const childCount = nodeLength(node);
    this.setStart(node, 0);
    this.setEnd(node, childCount);
  }

  deleteContents(): void {
    if (!this.#startContainer || !this.#endContainer || this.collapsed) {
      return;
    }

    if (this.#startContainer === this.#endContainer) {
      if (isCharacterDataNode(this.#startContainer)) {
        const text = (this.#startContainer as unknown as { textContent?: string | null }).textContent ?? "";
        const start = Math.max(0, Math.min(this.#startOffset, text.length));
        const end = Math.max(start, Math.min(this.#endOffset, text.length));
        (this.#startContainer as unknown as { textContent: string }).textContent = `${text.slice(0, start)}${text.slice(end)}`;
        const collapseOffset = Math.max(0, Math.min(start, ((this.#startContainer as unknown as { textContent?: string | null }).textContent ?? "").length));
        this.setStart(this.#startContainer, collapseOffset);
        this.setEnd(this.#startContainer, collapseOffset);
        return;
      }

      const children = this.#startContainer.childNodes.toArray();
      const start = Math.max(0, Math.min(this.#startOffset, children.length));
      const end = Math.max(start, Math.min(this.#endOffset, children.length));
      for (let index = end - 1; index >= start; index -= 1) {
        const child = children[index];
        if (child) {
          this.#startContainer.removeChild(child);
        }
      }
      this.setEnd(this.#startContainer, start);
      return;
    }

    const startParent = parentOf(this.#startContainer);
    const endParent = parentOf(this.#endContainer);
    if (
      startParent &&
      startParent === endParent &&
      isCharacterDataNode(this.#startContainer) &&
      isCharacterDataNode(this.#endContainer)
    ) {
      const parentChildren = startParent.childNodes.toArray();
      const startIndex = parentChildren.indexOf(this.#startContainer);
      const endIndex = parentChildren.indexOf(this.#endContainer);

      if (startIndex >= 0 && endIndex >= startIndex) {
        const startText = (this.#startContainer as unknown as { textContent?: string | null }).textContent ?? "";
        const endText = (this.#endContainer as unknown as { textContent?: string | null }).textContent ?? "";
        const startOffset = Math.max(0, Math.min(this.#startOffset, startText.length));
        const endOffset = Math.max(0, Math.min(this.#endOffset, endText.length));

        (this.#startContainer as unknown as { textContent: string }).textContent = startText.slice(0, startOffset);
        (this.#endContainer as unknown as { textContent: string }).textContent = endText.slice(endOffset);

        for (let index = endIndex - 1; index > startIndex; index -= 1) {
          const child = parentChildren[index];
          if (child) {
            startParent.removeChild(child);
          }
        }

        const collapseOffset = startIndex + 1;
        this.setStart(startParent, collapseOffset);
        this.setEnd(startParent, collapseOffset);
        return;
      }
    }

    // Cross-container deletion is not fully modeled yet. Collapse to the start
    // boundary to preserve API invariants.
    this.collapse(true);
  }

  cloneContents(): Node {
    if (!this.#startContainer || !this.#endContainer) {
      throw new Error("Range boundaries are not set");
    }

    const ownerDocument = ownerDocumentForNode(this.#startContainer);
    const fragment = ownerDocument.createDocumentFragment();
    if (this.collapsed) {
      return fragment;
    }

    if (this.#startContainer === this.#endContainer) {
      if (isCharacterDataNode(this.#startContainer)) {
        const text = (this.#startContainer as unknown as { textContent?: string | null }).textContent ?? "";
        const start = Math.max(0, Math.min(this.#startOffset, text.length));
        const end = Math.max(start, Math.min(this.#endOffset, text.length));
        fragment.appendChild(ownerDocument.createTextNode(text.slice(start, end)));
        return fragment;
      }

      const children = this.#startContainer.childNodes.toArray();
      const start = Math.max(0, Math.min(this.#startOffset, children.length));
      const end = Math.max(start, Math.min(this.#endOffset, children.length));
      for (let index = start; index < end; index += 1) {
        const child = children[index];
        if (child) {
          fragment.appendChild(child.cloneNode(true));
        }
      }
      return fragment;
    }

    const startParent = parentOf(this.#startContainer);
    const endParent = parentOf(this.#endContainer);
    if (
      startParent &&
      startParent === endParent &&
      isCharacterDataNode(this.#startContainer) &&
      isCharacterDataNode(this.#endContainer)
    ) {
      const parentChildren = startParent.childNodes.toArray();
      const startIndex = parentChildren.indexOf(this.#startContainer);
      const endIndex = parentChildren.indexOf(this.#endContainer);

      if (startIndex >= 0 && endIndex >= startIndex) {
        const startText = (this.#startContainer as unknown as { textContent?: string | null }).textContent ?? "";
        const endText = (this.#endContainer as unknown as { textContent?: string | null }).textContent ?? "";
        const startOffset = Math.max(0, Math.min(this.#startOffset, startText.length));
        const endOffset = Math.max(0, Math.min(this.#endOffset, endText.length));

        const startSlice = startText.slice(startOffset);
        if (startSlice.length > 0) {
          appendTextToFragment(fragment, ownerDocument, startSlice);
        }

        for (let index = startIndex + 1; index < endIndex; index += 1) {
          const child = parentChildren[index];
          if (child) {
            fragment.appendChild(child.cloneNode(true));
          }
        }

        const endSlice = endText.slice(0, endOffset);
        if (endSlice.length > 0) {
          appendTextToFragment(fragment, ownerDocument, endSlice);
        }

        return fragment;
      }
    }

    return fragment;
  }

  extractContents(): Node {
    const fragment = this.cloneContents();
    this.deleteContents();
    return fragment;
  }

  insertNode(node: Node): void {
    if (!isNodeLike(node)) {
      throw new TypeError("Failed to execute 'insertNode' on 'Range': parameter 1 is not of type 'Node'.");
    }

    if (!this.#startContainer || !this.#endContainer) {
      throw new Error("Range boundaries are not set");
    }

    if (isCharacterDataNode(this.#startContainer)) {
      const textNode = this.#startContainer as unknown as {
        splitText?: (offset: number) => Node;
        parentNode?: Node | null;
      };

      const insertionParent = textNode.parentNode;
      if (!insertionParent) {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }

      if (node === insertionParent || isInclusiveAncestor(node, insertionParent)) {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }

      if (typeof textNode.splitText !== "function") {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }

      const reference = textNode.splitText(this.#startOffset);
      const parent = reference.parentNode;
      if (!parent) {
        throw new ZigDOMException("The operation would yield an incorrect node tree.", "HierarchyRequestError", 3);
      }
      parent.insertBefore(node, reference);
      return;
    }

    const children = this.#startContainer.childNodes.toArray();
    const offset = Math.max(0, Math.min(this.#startOffset, children.length));
    const reference = children[offset] ?? null;
    this.#startContainer.insertBefore(node, reference);
  }

  surroundContents(newParent: Node): void {
    if (!isNodeLike(newParent)) {
      throw new TypeError("Failed to execute 'surroundContents' on 'Range': parameter 1 is not of type 'Node'.");
    }

    const fragment = this.extractContents();
    this.insertNode(newParent);
    newParent.appendChild(fragment);
    this.selectNode(newParent);
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

  detach(): void {
    // Legacy API kept as a no-op for web compatibility.
  }

  compareBoundaryPoints(how: number, sourceRange: Range): -1 | 0 | 1 {
    if (!(sourceRange instanceof Range)) {
      throw new TypeError("Failed to execute 'compareBoundaryPoints' on 'Range': parameter 2 is not of type 'Range'.");
    }

    if (!this.#startContainer || !this.#endContainer) {
      throw new Error("Range boundaries are not set");
    }

    let thisNode: Node;
    let thisOffset: number;
    let otherNode: Node;
    let otherOffset: number;

    const normalizedHow = toUnsignedShort(how);
    const sourceStart = sourceRange.startContainer;
    const sourceEnd = sourceRange.endContainer;

    switch (normalizedHow) {
      case Range.START_TO_START:
        thisNode = this.#startContainer;
        thisOffset = this.#startOffset;
        otherNode = sourceStart;
        otherOffset = sourceRange.startOffset;
        break;
      case Range.START_TO_END:
        thisNode = this.#endContainer;
        thisOffset = this.#endOffset;
        otherNode = sourceStart;
        otherOffset = sourceRange.startOffset;
        break;
      case Range.END_TO_END:
        thisNode = this.#endContainer;
        thisOffset = this.#endOffset;
        otherNode = sourceEnd;
        otherOffset = sourceRange.endOffset;
        break;
      case Range.END_TO_START:
        thisNode = this.#startContainer;
        thisOffset = this.#startOffset;
        otherNode = sourceEnd;
        otherOffset = sourceRange.endOffset;
        break;
      default:
        throw new ZigDOMException("The operation is not supported.", "NotSupportedError", 9);
    }

    if (rootOf(this.#startContainer) !== rootOf(sourceStart)) {
      throw new ZigDOMException("The object is in the wrong document.", "WrongDocumentError", 4);
    }

    return compareBoundaryPointPositions(thisNode, thisOffset, otherNode, otherOffset);
  }

  comparePoint(node: Node, offset: number): -1 | 0 | 1 {
    if (!isNodeLike(node)) {
      throw new TypeError("Failed to execute 'comparePoint' on 'Range': parameter 1 is not of type 'Node'.");
    }

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
      if (name === "WrongDocumentError") {
        return false;
      }
      if (name === "InvalidNodeTypeError") {
        throw error;
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
    const startsBeforeEnd = compareBoundaryPointPositions(parent, offset, this.#endContainer, this.#endOffset) === -1;
    const endsAfterStart = compareBoundaryPointPositions(parent, offset + 1, this.#startContainer, this.#startOffset) === 1;
    return startsBeforeEnd && endsAfterStart;
  }

  toString(): string {
    if (!this.#startContainer || !this.#endContainer) {
      return "";
    }

    if (compareBoundaryPointPositions(this.#startContainer, this.#startOffset, this.#endContainer, this.#endOffset) !== -1) {
      return "";
    }

    if (rootOf(this.#startContainer) !== rootOf(this.#endContainer)) {
      return "";
    }

    const textNodes = collectTextNodesInTree(rootOf(this.#startContainer));
    const parts: string[] = [];

    for (const textNode of textNodes) {
      const text = (textNode as unknown as { textContent?: string | null }).textContent ?? "";
      const length = text.length;
      if (length === 0) {
        continue;
      }

      const endVsStart = compareBoundaryPointPositions(textNode, length, this.#startContainer, this.#startOffset);
      if (endVsStart <= 0) {
        continue;
      }

      const startVsEnd = compareBoundaryPointPositions(textNode, 0, this.#endContainer, this.#endOffset);
      if (startVsEnd >= 0) {
        continue;
      }

      let start = 0;
      let end = length;
      if (textNode === this.#startContainer) {
        start = Math.max(0, Math.min(this.#startOffset, length));
      }
      if (textNode === this.#endContainer) {
        end = Math.max(start, Math.min(this.#endOffset, length));
      }

      if (end > start) {
        parts.push(text.slice(start, end));
      }
    }

    return parts.join("");
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

function isCharacterDataNode(node: Node): boolean {
  return node.nodeType === Node.TEXT_NODE ||
    node.nodeType === Node.CDATA_SECTION_NODE ||
    node.nodeType === Node.PROCESSING_INSTRUCTION_NODE ||
    node.nodeType === Node.COMMENT_NODE;
}

function ownerDocumentForNode(node: Node): {
  createDocumentFragment(): Node;
  createTextNode(data: string): Node;
} {
  const documentLike = node.nodeType === Node.DOCUMENT_NODE
    ? node
    : (node as unknown as { ownerDocument?: unknown }).ownerDocument;

  if (!documentLike || typeof documentLike !== "object") {
    throw new Error("Unable to resolve owner document for Range operation");
  }

  return documentLike as {
    createDocumentFragment(): Node;
    createTextNode(data: string): Node;
  };
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

function collectTextNodesInTree(node: Node): Node[] {
  if (node.nodeType === Node.TEXT_NODE || node.nodeType === Node.CDATA_SECTION_NODE) {
    return [node];
  }

  const nodes: Node[] = [];
  for (const child of node.childNodes.toArray()) {
    nodes.push(...collectTextNodesInTree(child));
  }
  return nodes;
}

function appendTextToFragment(fragment: Node, ownerDocument: { createTextNode(data: string): Node }, text: string): void {
  const last = fragment.lastChild;
  if (last && isCharacterDataNode(last)) {
    const current = (last as unknown as { textContent?: string | null }).textContent ?? "";
    (last as unknown as { textContent: string }).textContent = `${current}${text}`;
    return;
  }
  fragment.appendChild(ownerDocument.createTextNode(text));
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

const trackedRanges = new Set<WeakRef<Range>>();
const MAX_TRACKED_RANGES = 128;
const trackedRangeFinalizer = new FinalizationRegistry<WeakRef<Range>>((trackedRef) => {
  trackedRanges.delete(trackedRef);
});

function trimTrackedRanges(): void {
  while (trackedRanges.size > MAX_TRACKED_RANGES) {
    const oldest = trackedRanges.values().next().value as WeakRef<Range> | undefined;
    if (!oldest) {
      break;
    }
    trackedRanges.delete(oldest);
  }
}

export function notifyCharacterDataMutation(target: Node, offset: number, count: number, dataLength: number): void {
  for (const trackedRef of trackedRanges) {
    const range = trackedRef.deref();
    if (!range) {
      trackedRanges.delete(trackedRef);
      continue;
    }
    range.__applyCharacterDataMutation(target, offset, count, dataLength);
  }
}

export function notifySplitTextMutation(oldNode: Node, newNode: Node, offset: number, oldLength: number, parent: Node | null, oldIndex: number): void {
  for (const trackedRef of trackedRanges) {
    const range = trackedRef.deref();
    if (!range) {
      trackedRanges.delete(trackedRef);
      continue;
    }
    range.__applySplitTextMutation(oldNode, newNode, offset, oldLength, parent, oldIndex);
  }
}

export function notifyNodeRemovalMutation(removedNode: Node, oldParent: Node, oldIndex: number): void {
  for (const trackedRef of trackedRanges) {
    const range = trackedRef.deref();
    if (!range) {
      trackedRanges.delete(trackedRef);
      continue;
    }
    range.__applyNodeRemoval(removedNode, oldParent, oldIndex);
  }
}

export function notifyNodeInsertionMutation(insertedNode: Node, newParent: Node, newIndex: number): void {
  for (const trackedRef of trackedRanges) {
    const range = trackedRef.deref();
    if (!range) {
      trackedRanges.delete(trackedRef);
      continue;
    }
    range.__applyNodeInsertion(insertedNode, newParent, newIndex);
  }
}

type RangeMutationHooks = {
  hasTrackedRanges?: () => boolean;
  notifyNodeRemovalMutation?: (removedNode: Node, oldParent: Node, oldIndex: number) => void;
  notifyNodeInsertionMutation?: (insertedNode: Node, newParent: Node, newIndex: number) => void;
};

const rangeHookGlobal = globalThis as typeof globalThis & {
  __zigDomRangeMutationHooks?: RangeMutationHooks;
};

rangeHookGlobal.__zigDomRangeMutationHooks = {
  hasTrackedRanges: () => trackedRanges.size > 0,
  notifyNodeRemovalMutation,
  notifyNodeInsertionMutation,
};

type StaticRangeInit = {
  startContainer: Node;
  startOffset: number;
  endContainer: Node;
  endOffset: number;
};

export class StaticRange {
  #startContainer: Node;
  #startOffset: number;
  #endContainer: Node;
  #endOffset: number;

  constructor(init: StaticRangeInit) {
    if (
      !init ||
      !isNodeLike((init as Partial<StaticRangeInit>).startContainer) ||
      !isNodeLike((init as Partial<StaticRangeInit>).endContainer) ||
      (init as Partial<StaticRangeInit>).startOffset == null ||
      (init as Partial<StaticRangeInit>).endOffset == null
    ) {
      throw new TypeError("Failed to construct 'StaticRange': Invalid range initializer.");
    }

    if (
      init.startContainer.nodeType === Node.DOCUMENT_TYPE_NODE ||
      init.endContainer.nodeType === Node.DOCUMENT_TYPE_NODE ||
      init.startContainer.nodeType === Node.ATTRIBUTE_NODE ||
      init.endContainer.nodeType === Node.ATTRIBUTE_NODE
    ) {
      throw new ZigDOMException("The object is in an invalid state.", "InvalidNodeTypeError", 24);
    }

    this.#startContainer = init.startContainer;
    this.#startOffset = toUnsignedLong(init.startOffset);
    this.#endContainer = init.endContainer;
    this.#endOffset = toUnsignedLong(init.endOffset);
  }

  get startContainer(): Node {
    return this.#startContainer;
  }

  get startOffset(): number {
    return this.#startOffset;
  }

  get endContainer(): Node {
    return this.#endContainer;
  }

  get endOffset(): number {
    return this.#endOffset;
  }

  get collapsed(): boolean {
    return this.#startContainer === this.#endContainer && this.#startOffset === this.#endOffset;
  }

  get commonAncestorContainer(): Node {
    const startAncestors = collectAncestorChain(this.#startContainer);
    const endAncestors = new Set(collectAncestorChain(this.#endContainer));
    for (const ancestor of startAncestors) {
      if (endAncestors.has(ancestor)) {
        return ancestor;
      }
    }
    return this.#startContainer;
  }
}

function isNodeLike(value: unknown): value is Node {
  return !!value && typeof value === "object" && typeof (value as { nodeType?: unknown }).nodeType === "number";
}

function toUnsignedLong(value: unknown): number {
  return Number(value) >>> 0;
}

function adjustCharacterDataBoundary(boundaryOffset: number, offset: number, count: number, dataLength: number): number {
  const end = offset + count;
  if (boundaryOffset > offset && boundaryOffset <= end) {
    return offset;
  }
  if (boundaryOffset > end) {
    return boundaryOffset + dataLength - count;
  }
  return boundaryOffset;
}

function toUnsignedShort(value: unknown): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric === 0) {
    return 0;
  }

  const posInt = (numeric < 0 ? -1 : 1) * Math.floor(Math.abs(numeric));
  let converted = posInt % 65536;
  if (converted < 0) {
    converted += 65536;
  }
  return converted;
}

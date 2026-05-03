import type { Node } from "./Node.js";

export class NodeList implements Iterable<Node> {
  constructor(private readonly getNodes: () => Node[]) {}

  get length(): number {
    return this.getNodes().length;
  }

  item(index: number): Node | null {
    return this.getNodes()[index] ?? null;
  }

  [Symbol.iterator](): Iterator<Node> {
    return this.getNodes()[Symbol.iterator]();
  }

  toArray(): Node[] {
    return this.getNodes();
  }
}

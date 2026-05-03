import type { Node } from "./Node.ts";

export class NodeList implements Iterable<Node> {
  constructor(private readonly getNodes: () => Node[]) {
    const readNodes = getNodes;
    return new Proxy(this, {
      get(target, property, receiver) {
        if (typeof property === "string" && /^\d+$/.test(property)) {
          return readNodes()[Number(property)];
        }
        return Reflect.get(target, property, receiver);
      },
      has(target, property) {
        if (typeof property === "string" && /^\d+$/.test(property)) {
          return Number(property) < readNodes().length;
        }
        return Reflect.has(target, property);
      },
      ownKeys(target) {
        const keys = Reflect.ownKeys(target);
        const numeric = readNodes().map((_, index) => String(index));
        return [...keys, ...numeric];
      },
      getOwnPropertyDescriptor(target, property) {
        if (typeof property === "string" && /^\d+$/.test(property)) {
          const index = Number(property);
          const nodes = readNodes();
          if (index < nodes.length) {
            return {
              configurable: true,
              enumerable: true,
              writable: false,
              value: nodes[index]
            };
          }
        }
        return Reflect.getOwnPropertyDescriptor(target, property);
      }
    });
  }

  get length(): number {
    return this.getNodes().length;
  }

  item(index: number): Node | null {
    return this.getNodes()[index] ?? null;
  }

  forEach(callback: (value: Node, index: number, parent: NodeList) => void): void {
    const nodes = this.getNodes();
    for (let index = 0; index < nodes.length; index += 1) {
      callback(nodes[index], index, this);
    }
  }

  keys(): IterableIterator<number> {
    const nodes = this.getNodes();
    return nodes.keys();
  }

  values(): IterableIterator<Node> {
    return this.getNodes().values();
  }

  entries(): IterableIterator<[number, Node]> {
    return this.getNodes().entries();
  }

  [Symbol.iterator](): Iterator<Node> {
    return this.getNodes()[Symbol.iterator]();
  }

  toArray(): Node[] {
    return this.getNodes();
  }
}

import type { Node } from "./Node.ts";

const GET_NODES = Symbol("getNodes");
const STATIC_LENGTH = Symbol("staticLength");

export class NodeList implements Iterable<Node> {
  declare readonly forEach: (callback: (value: Node, index: number, parent: NodeList) => void, thisArg?: unknown) => void;
  declare readonly keys: () => IterableIterator<number>;
  declare readonly values: () => IterableIterator<Node>;
  declare readonly entries: () => IterableIterator<[number, Node]>;
  declare readonly [Symbol.iterator]: () => Iterator<Node>;

  constructor(getNodes: () => Node[], options: { static?: boolean } = {}) {
    const staticNodes = options.static ? getNodes().slice() : null;
    const readNodes = staticNodes ? () => staticNodes : getNodes;

    Object.defineProperty(this, GET_NODES, {
      value: readNodes,
      configurable: false,
      writable: false,
      enumerable: false
    });

    if (staticNodes) {
      const nodes = staticNodes;
      Object.defineProperty(this, STATIC_LENGTH, {
        value: nodes.length,
        configurable: false,
        writable: false,
        enumerable: false
      });
      for (let index = 0; index < nodes.length; index += 1) {
        Object.defineProperty(this, String(index), {
          value: nodes[index],
          configurable: true,
          enumerable: true,
          writable: false
        });
      }
      return this;
    }

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
    const staticLength = (this as unknown as { [STATIC_LENGTH]?: number })[STATIC_LENGTH];
    if (typeof staticLength === "number") {
      return staticLength;
    }
    return (this as unknown as { [GET_NODES]: () => Node[] })[GET_NODES]().length;
  }

  item(index: number): Node | null {
    return (this as unknown as { [GET_NODES]: () => Node[] })[GET_NODES]()[index] ?? null;
  }

  toArray(): Node[] {
    return (this as unknown as { [GET_NODES]: () => Node[] })[GET_NODES]();
  }
}

Object.defineProperty(NodeList.prototype, "forEach", {
  value: Array.prototype.forEach,
  configurable: true,
  writable: true
});

Object.defineProperty(NodeList.prototype, "keys", {
  value: Array.prototype.keys,
  configurable: true,
  writable: true
});

Object.defineProperty(NodeList.prototype, "values", {
  value: Array.prototype.values,
  configurable: true,
  writable: true
});

Object.defineProperty(NodeList.prototype, "entries", {
  value: Array.prototype.entries,
  configurable: true,
  writable: true
});

Object.defineProperty(NodeList.prototype, Symbol.iterator, {
  value: Array.prototype[Symbol.iterator],
  configurable: true,
  writable: true
});

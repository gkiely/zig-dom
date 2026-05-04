import type { Node } from "./Node.ts";

const GET_NODES = Symbol("getNodes");
const STATIC_LENGTH = Symbol("staticLength");
const EAGER_STATIC_INDEX_LIMIT = 256;

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
      if (nodes.length <= EAGER_STATIC_INDEX_LIMIT) {
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
      return createIndexedNodeListProxy(this, readNodes);
    }

    return createIndexedNodeListProxy(this, readNodes);
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

function isArrayIndex(property: PropertyKey): property is string {
  return typeof property === "string" && /^\d+$/.test(property);
}

function createIndexedNodeListProxy(target: NodeList, readNodes: () => Node[]): NodeList {
  return new Proxy(target, {
    get(target, property, receiver) {
      if (isArrayIndex(property)) {
        return readNodes()[Number(property)];
      }
      return Reflect.get(target, property, receiver);
    },
    has(target, property) {
      if (isArrayIndex(property)) {
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
      if (isArrayIndex(property)) {
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

Object.defineProperty(NodeList.prototype, "forEach", {
  value: function(callback: (value: Node, index: number, parent: NodeList) => void, thisArg?: unknown): void {
    this.toArray().forEach((value: Node, index: number) => callback.call(thisArg, value, index, this));
  },
  configurable: true,
  writable: true
});

Object.defineProperty(NodeList.prototype, "keys", {
  value: function(): IterableIterator<number> {
    return this.toArray().keys();
  },
  configurable: true,
  writable: true
});

Object.defineProperty(NodeList.prototype, "values", {
  value: function(): IterableIterator<Node> {
    return this.toArray().values();
  },
  configurable: true,
  writable: true
});

Object.defineProperty(NodeList.prototype, "entries", {
  value: function(): IterableIterator<[number, Node]> {
    return this.toArray().entries();
  },
  configurable: true,
  writable: true
});

Object.defineProperty(NodeList.prototype, Symbol.iterator, {
  value: function(): Iterator<Node> {
    return this.values();
  },
  configurable: true,
  writable: true
});

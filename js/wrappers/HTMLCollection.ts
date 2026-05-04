import type { Element } from "./Element.ts";

const GET_ELEMENTS = Symbol("getElements");

export class HTMLCollection implements Iterable<Element> {
  constructor(getElements: () => Element[]) {
    Object.defineProperty(this, GET_ELEMENTS, {
      value: getElements,
      configurable: false,
      writable: false,
      enumerable: false
    });

    const readElements = () => this._snapshot();
    return new Proxy(this, {
      get(target, property, receiver) {
        if (typeof property === "string") {
          if (/^\d+$/.test(property)) {
            return readElements()[Number(property)];
          }

          const named = findNamedElement(readElements(), property);
          if (named) {
            return named;
          }
        }

        return Reflect.get(target, property, receiver);
      },
      has(target, property) {
        if (typeof property === "string") {
          if (/^\d+$/.test(property)) {
            return Number(property) < readElements().length;
          }

          if (findNamedElement(readElements(), property)) {
            return true;
          }
        }

        return Reflect.has(target, property);
      },
      set(target, property, value, receiver) {
        if (typeof property === "string" && /^\d+$/.test(property)) {
          return false;
        }

        return Reflect.set(target, property, value, receiver);
      },
      ownKeys(target) {
        const elements = readElements();
        const keys = Reflect.ownKeys(target);
        const numeric = elements.map((_, index) => String(index));
        const named = exposedNames(elements);
        return [...keys, ...numeric, ...named];
      },
      getOwnPropertyDescriptor(target, property) {
        if (typeof property === "string") {
          if (/^\d+$/.test(property)) {
            const index = Number(property);
            const elements = readElements();
            if (index < elements.length) {
              return {
                configurable: true,
                enumerable: true,
                writable: false,
                value: elements[index]
              };
            }
          }

          const named = findNamedElement(readElements(), property);
          if (named) {
            return {
              configurable: true,
              enumerable: false,
              writable: false,
              value: named
            };
          }
        }

        return Reflect.getOwnPropertyDescriptor(target, property);
      }
    });
  }

  _snapshot(): Element[] {
    const values = (this as unknown as { [GET_ELEMENTS]: () => Element[] })[GET_ELEMENTS]() as unknown;
    if (Array.isArray(values)) {
      return values;
    }

    if (values && typeof (values as { [Symbol.iterator]?: () => Iterator<Element> })[Symbol.iterator] === "function") {
      return Array.from(values as Iterable<Element>);
    }

    const listLike = values as { length?: number; [index: number]: Element };
    const length = Number(listLike?.length ?? 0);
    const out: Element[] = [];
    for (let index = 0; index < length; index += 1) {
      const value = listLike[index];
      if (value) {
        out.push(value);
      }
    }
    return out;
  }

  get length(): number {
    return this._snapshot().length;
  }

  item(index: number): Element | null {
    const numericIndex = Number(index);
    const convertedIndex = Number.isFinite(numericIndex) ? Math.trunc(numericIndex) >>> 0 : 0;
    return this._snapshot()[convertedIndex] ?? null;
  }

  namedItem(name: string): Element | null {
    return findNamedElement(this._snapshot(), name);
  }

  [Symbol.iterator](): Iterator<Element> {
    return this._snapshot()[Symbol.iterator]();
  }

  toArray(): Element[] {
    return this._snapshot();
  }
}

function exposedNames(elements: Element[]): string[] {
  const names: string[] = [];
  const seen = new Set<string>();
  for (const element of elements) {
    const id = element.id;
    if (id !== "" && !seen.has(id)) {
      seen.add(id);
      names.push(id);
    }

    const htmlName = element.namespaceURI === "http://www.w3.org/1999/xhtml" ? element.getAttribute("name") ?? "" : "";
    if (htmlName !== "" && !seen.has(htmlName)) {
      seen.add(htmlName);
      names.push(htmlName);
    }
  }
  return names;
}

function findNamedElement(elements: Element[], name: string): Element | null {
  if (name === "") {
    return null;
  }

  return elements.find((element) => {
    if (element.id === name) {
      return true;
    }

    return element.namespaceURI === "http://www.w3.org/1999/xhtml" && element.getAttribute("name") === name;
  }) ?? null;
}

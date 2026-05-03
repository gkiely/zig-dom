import type { Element } from "./Element.ts";

export class HTMLCollection implements Iterable<Element> {
  constructor(private readonly getElements: () => Element[]) {}

  _snapshot(): Element[] {
    const values = this.getElements() as unknown;
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
    return this._snapshot()[index] ?? null;
  }

  namedItem(name: string): Element | null {
    if (name === "") {
      return null;
    }

    return this._snapshot().find((element) => element.id === name || element.getAttribute("name") === name) ?? null;
  }

  [Symbol.iterator](): Iterator<Element> {
    return this._snapshot()[Symbol.iterator]();
  }

  toArray(): Element[] {
    return this._snapshot();
  }
}

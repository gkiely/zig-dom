import type { Element } from "./Element.ts";

export class HTMLCollection implements Iterable<Element> {
  constructor(private readonly getElements: () => Element[]) {}

  get length(): number {
    return this.getElements().length;
  }

  item(index: number): Element | null {
    return this.getElements()[index] ?? null;
  }

  namedItem(name: string): Element | null {
    return this.getElements().find((element) => element.id === name || element.getAttribute("name") === name) ?? null;
  }

  [Symbol.iterator](): Iterator<Element> {
    return this.getElements()[Symbol.iterator]();
  }

  toArray(): Element[] {
    return this.getElements();
  }
}

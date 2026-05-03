import { Element } from "./Element.ts";
import { Event } from "./Event.ts";

class CSSStyleDeclaration {
  #values = new Map<string, string>();

  setProperty(name: string, value: string): void {
    this.#values.set(name, value);
  }

  removeProperty(name: string): string {
    const current = this.#values.get(name) ?? "";
    this.#values.delete(name);
    return current;
  }

  getPropertyValue(name: string): string {
    return this.#values.get(name) ?? "";
  }

  get cssText(): string {
    return [...this.#values.entries()].map(([name, value]) => `${name}: ${value};`).join(" ");
  }

  set cssText(value: string) {
    this.#values.clear();
    for (const declaration of value.split(";")) {
      const [rawName, rawValue] = declaration.split(":");
      const name = rawName?.trim();
      const nextValue = rawValue?.trim();
      if (name && nextValue) {
        this.#values.set(name, nextValue);
      }
    }
  }
}

export class HTMLElement extends Element {
  onclick: ((event: Event) => void) | null = null;
  onchange: ((event: Event) => void) | null = null;
  oninput: ((event: Event) => void) | null = null;
  readonly style: CSSStyleDeclaration;

  constructor(window: Element["_window"], handle: number) {
    super(window, handle);
    this.style = new CSSStyleDeclaration();
    const inlineStyle = this.getAttribute("style");
    if (inlineStyle) {
      this.style.cssText = inlineStyle;
    }
  }
}

export class HTMLButtonElement extends HTMLElement {
  get type(): string {
    return this.getAttribute("type")?.toLowerCase() ?? "submit";
  }

  set type(value: string) {
    this.setAttribute("type", value);
  }

  override dispatchEvent(event: Event): boolean {
    const result = super.dispatchEvent(event);
    if (event.type === "click" && !event.defaultPrevented && this.type === "submit") {
      const form = this.closestForm();
      if (form) {
        form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
      }
    }
    return result;
  }

  private closestForm(): HTMLFormElement | null {
    let cursor = this.parentNode;
    while (cursor) {
      if (cursor instanceof HTMLFormElement) {
        return cursor;
      }
      cursor = cursor.parentNode;
    }
    return null;
  }
}

export class HTMLIFrameElement extends HTMLElement {}

export class HTMLInputElement extends HTMLElement {
  get value(): string {
    return this.getAttribute("value") ?? "";
  }

  set value(next: string) {
    this.setAttribute("value", next);
  }

  get checked(): boolean {
    return this.hasAttribute("checked");
  }

  set checked(next: boolean) {
    if (next) {
      this.setAttribute("checked", "");
    } else {
      this.removeAttribute("checked");
    }
  }
}

export class HTMLFormElement extends HTMLElement {
  submit(): void {
    const event = new Event("submit", { bubbles: true, cancelable: true });
    this.dispatchEvent(event);
  }
}

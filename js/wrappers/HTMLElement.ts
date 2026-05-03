import type { DocumentFragment } from "./DocumentFragment.ts";
import { Element } from "./Element.ts";
import { Event } from "./Event.ts";

class CSSStyleDeclaration {
  readonly #onChange: (cssText: string) => void;
  #values = new Map<string, string>();

  constructor(onChange: (cssText: string) => void) {
    this.#onChange = onChange;
  }

  setProperty(name: string, value: string): void {
    this.#values.set(name, value);
    this.#onChange(this.cssText);
  }

  removeProperty(name: string): string {
    const current = this.#values.get(name) ?? "";
    this.#values.delete(name);
    this.#onChange(this.cssText);
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
    this.#onChange(this.cssText);
  }
}

export class HTMLElement extends Element {
  onclick: ((event: Event) => void) | null = null;
  onchange: ((event: Event) => void) | null = null;
  oninput: ((event: Event) => void) | null = null;
  #style: CSSStyleDeclaration | null = null;
  #syncingStyleAttribute = false;
  #shadowRootValue: DocumentFragment | null = null;
  #shadowRootMode: ShadowRootMode | null = null;

  #ensureStyle(): CSSStyleDeclaration {
    if (this.#style) {
      return this.#style;
    }

    this.#style = new CSSStyleDeclaration((cssText) => {
      if (this.#syncingStyleAttribute) {
        return;
      }

      this.#syncingStyleAttribute = true;
      if (cssText.length === 0) {
        super.removeAttribute("style");
      } else {
        super.setAttribute("style", cssText);
      }
      this.#syncingStyleAttribute = false;
    });

    const inlineStyle = this.getAttribute("style");
    if (inlineStyle) {
      this.#syncingStyleAttribute = true;
      this.#style.cssText = inlineStyle;
      this.#syncingStyleAttribute = false;
    }

    return this.#style;
  }

  get style(): CSSStyleDeclaration {
    return this.#ensureStyle();
  }

  constructor(window: Element["_window"], handle: number, _skipInitialStyleSync = false) {
    super(window, handle);
  }

  override setAttribute(name: string, value: string): void {
    super.setAttribute(name, value);
    if (name.toLowerCase() === "style" && !this.#syncingStyleAttribute && this.#style) {
      this.#syncingStyleAttribute = true;
      this.#style.cssText = value;
      this.#syncingStyleAttribute = false;
    }
  }

  override removeAttribute(name: string): void {
    super.removeAttribute(name);
    if (name.toLowerCase() === "style" && !this.#syncingStyleAttribute && this.#style) {
      this.#syncingStyleAttribute = true;
      this.#style.cssText = "";
      this.#syncingStyleAttribute = false;
    }
  }

  attachShadow(init: ShadowRootInit): DocumentFragment {
    if (this.#shadowRootValue) {
      throw new Error("Shadow root already attached");
    }

    const root = (this.ownerDocument ?? this._window.document).createDocumentFragment();
    this.#shadowRootValue = root;
    this.#shadowRootMode = init.mode;

    const shadowRootMeta = root as unknown as { host: HTMLElement; mode: ShadowRootMode };
    shadowRootMeta.host = this;
    shadowRootMeta.mode = init.mode;
    return root;
  }

  get shadowRoot(): DocumentFragment | null {
    if (this.#shadowRootMode !== "open") {
      return null;
    }
    return this.#shadowRootValue;
  }

  focus(): void {
    this._window.setActiveElement(this);
    this.dispatchEvent(new Event("focus"));
  }

  blur(): void {
    if (this._window.document.activeElement === this) {
      this._window.setActiveElement(null);
    }
    this.dispatchEvent(new Event("blur"));
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

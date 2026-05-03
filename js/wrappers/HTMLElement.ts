import type { DocumentFragment } from "./DocumentFragment.ts";
import { Element } from "./Element.ts";
import { Event } from "./Event.ts";
import { HTMLCollection } from "./HTMLCollection.ts";

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

  constructor(window: Element["_window"], handle: number, nodeType = 1, _skipInitialStyleSync = false) {
    super(window, handle, nodeType);
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
    if (this.disabled) {
      return;
    }
    this._window.setActiveElement(this);
    this.dispatchEvent(new Event("focus"));
  }

  blur(): void {
    if (this._window.document.activeElement === this) {
      this._window.setActiveElement(null);
    }
    this.dispatchEvent(new Event("blur"));
  }

  get disabled(): boolean {
    return this.hasAttribute("disabled");
  }

  set disabled(next: boolean) {
    if (next) {
      this.setAttribute("disabled", "");
    } else {
      this.removeAttribute("disabled");
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
    if (event.type === "click" && this.disabled) {
      return true;
    }

    const result = super.dispatchEvent(event);
    if (event.type === "click" && !event.defaultPrevented && this.type === "submit") {
      const form = this.closestForm();
      if (form) {
        form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
      }
    }
    if (event.type === "click" && !event.defaultPrevented && this.type === "reset") {
      const form = this.closestForm();
      form?.reset();
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
  #value: string | null = null;
  #checked: boolean | null = null;

  get value(): string {
    return this.#value ?? this.defaultValue;
  }

  set value(next: string) {
    this.#value = String(next);
  }

  get defaultValue(): string {
    return this.getAttribute("value") ?? "";
  }

  set defaultValue(next: string) {
    this.setAttribute("value", String(next));
  }

  get checked(): boolean {
    return this.#checked ?? this.defaultChecked;
  }

  set checked(next: boolean) {
    this.#checked = Boolean(next);
  }

  get defaultChecked(): boolean {
    return this.hasAttribute("checked");
  }

  set defaultChecked(next: boolean) {
    if (next) {
      this.setAttribute("checked", "");
    } else {
      this.removeAttribute("checked");
    }
  }

  _resetForForm(): void {
    this.#value = null;
    this.#checked = null;
  }
}

export class HTMLFormElement extends HTMLElement {
  get elements(): HTMLCollection {
    return createIndexedCollection(() => collectFormControls(this));
  }

  reset(): void {
    const event = new Event("reset", { bubbles: true, cancelable: true });
    this.dispatchEvent(event);
    if (event.defaultPrevented) {
      return;
    }

    for (const element of this.elements) {
      const maybeResettable = element as unknown as { _resetForForm?: () => void };
      maybeResettable._resetForForm?.();
    }
  }

  submit(): void {
    const event = new Event("submit", { bubbles: true, cancelable: true });
    this.dispatchEvent(event);
  }
}

export class HTMLTextAreaElement extends HTMLElement {
  #value: string | null = null;

  get value(): string {
    return this.#value ?? this.defaultValue;
  }

  set value(next: string) {
    this.#value = String(next);
  }

  get defaultValue(): string {
    return this.getAttribute("value") ?? this.textContent;
  }

  set defaultValue(next: string) {
    this.setAttribute("value", String(next));
  }

  _resetForForm(): void {
    this.#value = null;
  }
}

export class HTMLOptionElement extends HTMLElement {
  #selected: boolean | null = null;

  get value(): string {
    return this.getAttribute("value") ?? this.textContent;
  }

  set value(next: string) {
    this.setAttribute("value", String(next));
  }

  get selected(): boolean {
    return this.#selected ?? this.defaultSelected;
  }

  set selected(next: boolean) {
    this.#selected = Boolean(next);
  }

  get defaultSelected(): boolean {
    return this.hasAttribute("selected");
  }

  set defaultSelected(next: boolean) {
    if (next) {
      this.setAttribute("selected", "");
    } else {
      this.removeAttribute("selected");
    }
  }

  _resetForForm(): void {
    this.#selected = null;
  }
}

export class HTMLSelectElement extends HTMLElement {
  get options(): HTMLCollection {
    return createIndexedCollection(() => collectOptionElements(this));
  }

  get value(): string {
    for (const option of this.options) {
      if ((option as HTMLOptionElement).selected) {
        return (option as HTMLOptionElement).value;
      }
    }

    const first = this.options.item(0) as HTMLOptionElement | null;
    return first?.value ?? "";
  }

  set value(next: string) {
    let matched = false;
    for (const option of this.options) {
      const opt = option as HTMLOptionElement;
      const shouldSelect = opt.value === next;
      opt.selected = shouldSelect;
      if (shouldSelect) {
        matched = true;
      }
    }

    if (!matched) {
      for (const option of this.options) {
        (option as HTMLOptionElement).selected = false;
      }
    }
  }

  _resetForForm(): void {
    for (const option of this.options) {
      (option as HTMLOptionElement)._resetForForm();
    }
  }
}

export class HTMLLabelElement extends HTMLElement {
  get control(): HTMLElement | null {
    const htmlFor = this.getAttribute("for");
    if (htmlFor) {
      const found = this.ownerDocument?.getElementById(htmlFor);
      return found as HTMLElement | null;
    }

    for (const candidate of collectFormControls(this)) {
      return candidate as HTMLElement;
    }

    return null;
  }
}

function collectFormControls(root: Element): Element[] {
  const controls: Element[] = [];
  const stack = root.childNodes.toArray();

  while (stack.length > 0) {
    const current = stack.shift();
    if (!current) {
      continue;
    }

    if (current.nodeType === current._window.Node.ELEMENT_NODE) {
      const element = current as unknown as Element;
      if (isFormControlTag(element.tagName.toLowerCase())) {
        controls.push(element);
      }
    }

    for (const child of current.childNodes.toArray()) {
      stack.push(child);
    }
  }

  return controls;
}

function collectOptionElements(root: Element): Element[] {
  return collectFormControls(root).filter((element) => element.tagName.toLowerCase() === "option");
}

function isFormControlTag(tagName: string): boolean {
  return tagName === "input" || tagName === "button" || tagName === "select" || tagName === "option" || tagName === "textarea";
}

function createIndexedCollection(getElements: () => Element[]): HTMLCollection {
  const collection = new HTMLCollection(getElements);
  return new Proxy(collection, {
    get(target, property, receiver) {
      if (typeof property === "string" && /^\d+$/.test(property)) {
        return getElements()[Number(property)];
      }
      return Reflect.get(target, property, receiver);
    },
    has(target, property) {
      if (typeof property === "string" && /^\d+$/.test(property)) {
        return Number(property) < getElements().length;
      }
      return Reflect.has(target, property);
    },
    ownKeys(target) {
      const keys = Reflect.ownKeys(target);
      const numeric = getElements().map((_, index) => String(index));
      return [...keys, ...numeric];
    },
    getOwnPropertyDescriptor(target, property) {
      if (typeof property === "string" && /^\d+$/.test(property)) {
        const index = Number(property);
        const elements = getElements();
        if (index < elements.length) {
          return {
            configurable: true,
            enumerable: true,
            writable: false,
            value: elements[index]
          };
        }
      }
      return Reflect.getOwnPropertyDescriptor(target, property);
    }
  });
}

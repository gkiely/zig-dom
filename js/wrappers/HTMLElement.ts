import type { DocumentFragment } from "./DocumentFragment.ts";
import { Element } from "./Element.ts";
import { Event, FocusEvent } from "./Event.ts";
import { HTMLCollection } from "./HTMLCollection.ts";
import type { Window } from "./Window.ts";

type CSSStyleSheetLike = {
  cssRules: Array<{ cssText: string }>;
  insertRule(rule: string, index?: number): number;
};

function retargetFocusRelatedTarget(target: unknown): unknown {
  const maybeNode = target as unknown as { parentNode?: Node | null };
  let cursor = maybeNode?.parentNode ?? null;
  while (cursor) {
    const shadowRoot = cursor as unknown as { host?: HTMLElement };
    if (shadowRoot.host) {
      return shadowRoot.host;
    }
    cursor = cursor.parentNode;
  }
  return target;
}

export class HTMLElement extends Element {
  declare onclick: ((event: Event) => void) | null;
  declare onchange: ((event: Event) => void) | null;
  declare oninput: ((event: Event) => void) | null;
  declare onanimationend: ((event: Event) => void) | null;
  declare onanimationiteration: ((event: Event) => void) | null;
  declare onanimationstart: ((event: Event) => void) | null;
  declare ontransitionend: ((event: Event) => void) | null;
  #styleSheet: CSSStyleSheetLike | null = null;
  #shadowRootValue: DocumentFragment | null = null;
  #shadowRootMode: ShadowRootMode | null = null;
  #templateContent: DocumentFragment | null = null;
  #scrollLeftValue = 0;
  #scrollTopValue = 0;

  get sheet(): CSSStyleSheetLike | undefined {
    if (this.tagName !== "STYLE") {
      return undefined;
    }

    if (this.#styleSheet) {
      return this.#styleSheet;
    }

    const cssRules: Array<{ cssText: string }> = [];
    this.#styleSheet = {
      cssRules,
      insertRule(rule: string, index?: number): number {
        const nextIndex = typeof index === "number" ? Math.max(0, Math.min(index, cssRules.length)) : cssRules.length;
        cssRules.splice(nextIndex, 0, { cssText: rule });
        return nextIndex;
      }
    };

    return this.#styleSheet;
  }

  get content(): DocumentFragment | undefined {
    if (this.tagName !== "TEMPLATE") {
      return undefined;
    }

    if (this.#templateContent) {
      return this.#templateContent;
    }

    const fragment = (this.ownerDocument ?? this._window.document).createDocumentFragment();
    while (this.firstChild) {
      fragment.appendChild(this.removeChild(this.firstChild));
    }

    this.#templateContent = fragment;
    return this.#templateContent;
  }

  get scrollLeft(): number {
    return this.#scrollLeftValue;
  }

  set scrollLeft(value: number) {
    this.#scrollLeftValue = Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  get scrollTop(): number {
    return this.#scrollTopValue;
  }

  set scrollTop(value: number) {
    this.#scrollTopValue = Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  scrollTo(x: number | { left?: number; top?: number }, y?: number): void {
    if (typeof x === "object") {
      if (typeof x.left === "number") {
        this.scrollLeft = x.left;
      }
      if (typeof x.top === "number") {
        this.scrollTop = x.top;
      }
      return;
    }

    this.scrollLeft = x;
    this.scrollTop = typeof y === "number" ? y : this.scrollTop;
  }

  scrollIntoView(_arg?: boolean | ScrollIntoViewOptions): void {
    // No layout engine yet; this exists for compatibility with callers that expect the API.
  }

  click(): void {
    this.dispatchEvent(new Event("click", { bubbles: true, cancelable: true }));
  }

  constructor(window: Element["_window"], handle: number, nodeType = 1, _skipInitialStyleSync = false) {
    super(window, handle, nodeType);
  }

  override setAttribute(name: string, value: string): void {
    super.setAttribute(name, value);
    const normalizedName = name.toLowerCase();

    if (normalizedName.startsWith("on")) {
      const handlerBody = String(value);
      const compiled = new Function("event", "window", `with (this) { with (window) { ${handlerBody} } }`);
      const windowScope = this._window as unknown as Record<string | symbol, unknown> & {
        __scriptContext?: Record<string, unknown>;
      };
      const scriptContext = windowScope.__scriptContext;
      const handlerScope = scriptContext
        ? new Proxy(scriptContext as Record<string | symbol, unknown>, {
            has: (target, property) => Reflect.has(target, property) || Reflect.has(windowScope, property),
            get: (target, property, receiver) => Reflect.has(target, property)
              ? Reflect.get(target, property, receiver)
              : Reflect.get(windowScope, property),
            set: (target, property, nextValue, receiver) => {
              if (Reflect.has(target, property) || !Reflect.has(windowScope, property)) {
                return Reflect.set(target, property, nextValue);
              }
              return Reflect.set(windowScope, property, nextValue);
            },
            getOwnPropertyDescriptor: (target, property) => Reflect.getOwnPropertyDescriptor(target, property) ?? Reflect.getOwnPropertyDescriptor(windowScope, property),
            ownKeys: (target) => {
              const keySet = new Set([...Reflect.ownKeys(windowScope), ...Reflect.ownKeys(target)]);
              return [...keySet];
            }
          })
        : windowScope;
      (this as unknown as Record<string, unknown>)[normalizedName] = (event: Event) => {
        compiled.call(this, event, handlerScope as unknown as Record<string, unknown>);
      };
    }

  }

  override removeAttribute(name: string): void {
    super.removeAttribute(name);
    const normalizedName = name.toLowerCase();

    if (normalizedName.startsWith("on")) {
      (this as unknown as Record<string, unknown>)[normalizedName] = null;
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
    const previous = this._window.document.activeElement;
    this._window.setActiveElement(this);
    const event = new FocusEvent("focus");
    (event as unknown as { relatedTarget: unknown }).relatedTarget = retargetFocusRelatedTarget(previous);
    this.dispatchEvent(event);
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

  get title(): string {
    return this.getAttribute("title") ?? "";
  }

  set title(next: string) {
    const value = String(next);
    if (value.length === 0) {
      this.removeAttribute("title");
    } else {
      this.setAttribute("title", value);
    }
  }
}

Object.assign(HTMLElement.prototype, {
  onclick: null,
  onchange: null,
  oninput: null,
  onanimationend: null,
  onanimationiteration: null,
  onanimationstart: null,
  ontransitionend: null
});

export class HTMLSpanElement extends HTMLElement {}

export class HTMLAnchorElement extends HTMLElement {}

export class HTMLLIElement extends HTMLElement {}

export class HTMLOListElement extends HTMLElement {}

export class HTMLUListElement extends HTMLElement {}

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

export class HTMLIFrameElement extends HTMLElement {
  #contentWindow: Window | null = null;

  get contentWindow(): Window {
    if (this.#contentWindow) {
      return this.#contentWindow;
    }

    const WindowCtor = this._window.constructor as {
      new (options?: { url?: string }): Window;
    };
    this.#contentWindow = new WindowCtor({ url: this._window.location.href });
    return this.#contentWindow;
  }

  get contentDocument(): Window["document"] {
    return this.contentWindow.document;
  }
}

export class HTMLInputElement extends HTMLElement {
  #value: string | null = null;
  #checked: boolean | null = null;

  #isDefaultCheckedRadioWinner(): boolean {
    const name = this.getAttribute("name");
    if (!name) {
      return true;
    }

    const document = this.ownerDocument;
    if (!document) {
      return true;
    }

    const form = this.closestForm();
    let winner: HTMLInputElement | null = null;
    for (const candidate of document.querySelectorAll("input")) {
      if (!(candidate instanceof HTMLInputElement)) {
        continue;
      }
      if (candidate.type !== "radio") {
        continue;
      }
      if ((candidate.getAttribute("name") ?? "") !== name) {
        continue;
      }
      if (candidate.closestForm() !== form) {
        continue;
      }
      if (!candidate.defaultChecked) {
        continue;
      }
      winner = candidate;
    }

    return winner ? winner === this : true;
  }

  #uncheckSameGroupRadios(): void {
    const name = this.getAttribute("name");
    if (!name) {
      return;
    }

    const document = this.ownerDocument;
    if (!document) {
      return;
    }

    const form = this.closestForm();
    for (const candidate of document.querySelectorAll("input")) {
      if (!(candidate instanceof HTMLInputElement)) {
        continue;
      }
      if (candidate === this || candidate.type !== "radio") {
        continue;
      }
      if ((candidate.getAttribute("name") ?? "") !== name) {
        continue;
      }
      if (candidate.closestForm() !== form) {
        continue;
      }

      candidate.checked = false;
    }
  }

  get type(): string {
    return this.getAttribute("type")?.toLowerCase() ?? "text";
  }

  set type(value: string) {
    this.setAttribute("type", value);
  }

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
    if (this.#checked !== null) {
      return this.#checked;
    }

    if (this.type === "radio" && this.defaultChecked) {
      return this.#isDefaultCheckedRadioWinner();
    }

    return this.defaultChecked;
  }

  set checked(next: boolean) {
    this.#checked = Boolean(next);
    if (this.#checked && this.type === "radio") {
      this.#uncheckSameGroupRadios();
    }
  }

  get defaultChecked(): boolean {
    return this.hasAttribute("checked");
  }

  set defaultChecked(next: boolean) {
    if (next) {
      this.setAttribute("checked", "");
      if (this.#checked === null && this.type === "radio") {
        this.#uncheckSameGroupRadios();
      }
    } else {
      this.removeAttribute("checked");
    }
  }

  override dispatchEvent(event: Event): boolean {
    if (event.type === "click" && this.disabled) {
      return true;
    }

    const inputType = this.type;
    const radioAlreadyChecked = inputType === "radio" && this.checked;
    const togglesChecked = event.type === "click" && (inputType === "checkbox" || (inputType === "radio" && !radioAlreadyChecked));
    const previousChecked = this.checked;

    if (togglesChecked) {
      this.#checked = inputType === "checkbox" ? !this.checked : true;
    }

    const result = super.dispatchEvent(event);
    if (event.type !== "click") {
      return result;
    }

    if (event.defaultPrevented) {
      if (togglesChecked) {
        this.#checked = previousChecked;
      }
      return result;
    }

    if (inputType === "radio" && togglesChecked && this.checked) {
      this.#uncheckSameGroupRadios();
    }

    if (togglesChecked) {
      super.dispatchEvent(new Event("input", { bubbles: true }));
      super.dispatchEvent(new Event("change", { bubbles: true }));
    }

    if (inputType === "submit") {
      this.closestForm()?.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    } else if (inputType === "reset") {
      this.closestForm()?.reset();
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

  #closestSelect(): HTMLSelectElement | null {
    let cursor = this.parentNode;
    while (cursor) {
      if (cursor instanceof HTMLSelectElement) {
        return cursor;
      }
      cursor = cursor.parentNode;
    }
    return null;
  }

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
    if (!this.#selected) {
      return;
    }

    const select = this.#closestSelect();
    if (!select) {
      return;
    }

    select._clearExplicitClearedValueState();

    if (select.multiple) {
      return;
    }

    for (const option of select.options) {
      if (option === this) {
        continue;
      }
      (option as HTMLOptionElement).#selected = false;
    }
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
  #valueExplicitlyCleared = false;

  _clearExplicitClearedValueState(): void {
    this.#valueExplicitlyCleared = false;
  }

  get multiple(): boolean {
    return this.hasAttribute("multiple");
  }

  set multiple(next: boolean) {
    if (next) {
      this.setAttribute("multiple", "");
    } else {
      this.removeAttribute("multiple");
    }
  }

  get options(): HTMLCollection {
    return createIndexedCollection(() => collectOptionElements(this));
  }

  get value(): string {
    for (const option of this.options) {
      if ((option as HTMLOptionElement).selected) {
        return (option as HTMLOptionElement).value;
      }
    }

    if (this.#valueExplicitlyCleared) {
      return "";
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
      this.#valueExplicitlyCleared = true;
      return;
    }

    this.#valueExplicitlyCleared = false;
  }

  _resetForForm(): void {
    for (const option of this.options) {
      (option as HTMLOptionElement)._resetForForm();
    }
    this.#valueExplicitlyCleared = false;
  }
}

export class HTMLLabelElement extends HTMLElement {
  constructor(window: Element["_window"], handle: number, nodeType = 1, skipInitialStyleSync = false) {
    super(window, handle, nodeType, skipInitialStyleSync);

    this.addEventListener("click", (event) => {
      if (event.defaultPrevented) {
        return;
      }

      const control = this.control;
      if (!control || control.disabled) {
        return;
      }

      const target = event.target;
      if (target === control) {
        return;
      }

      if (target instanceof Element && target !== this) {
        let cursor: Element | null = target;
        while (cursor && cursor !== this) {
          if (cursor !== control && isInteractiveDescendantTag(cursor.tagName.toLowerCase())) {
            return;
          }
          cursor = cursor.parentNode as Element | null;
        }
      }

      if (target instanceof Element && control.contains(target)) {
        return;
      }

      control.dispatchEvent(new Event("click", { bubbles: true, cancelable: true }));
    });
  }

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

function isInteractiveDescendantTag(tagName: string): boolean {
  return tagName === "a" ||
    tagName === "button" ||
    tagName === "input" ||
    tagName === "select" ||
    tagName === "textarea" ||
    tagName === "option";
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

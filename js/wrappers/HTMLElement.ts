import { Element } from "./Element.js";
import { Event } from "./Event.js";

export class HTMLElement extends Element {
  onclick: ((event: Event) => void) | null = null;
  onchange: ((event: Event) => void) | null = null;
  oninput: ((event: Event) => void) | null = null;
}

export class HTMLButtonElement extends HTMLElement {}

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

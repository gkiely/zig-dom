import { PropertySymbol } from "./compatibility/happy-dom-symbols.ts";
import { GlobalRegistrator } from "./global-registrator.ts";
import { Comment } from "./wrappers/Comment.ts";
import { CustomElementRegistry } from "./wrappers/CustomElementRegistry.ts";
import { ZigDOMException } from "./wrappers/DOMException.ts";
import { Document } from "./wrappers/Document.ts";
import { DocumentFragment } from "./wrappers/DocumentFragment.ts";
import { Element } from "./wrappers/Element.ts";
import { CustomEvent, Event, InputEvent, KeyboardEvent, MouseEvent } from "./wrappers/Event.ts";
import { HTMLCollection } from "./wrappers/HTMLCollection.ts";
import {
  HTMLButtonElement,
  HTMLElement,
  HTMLFormElement,
  HTMLIFrameElement,
  HTMLInputElement,
  HTMLLabelElement,
  HTMLOptionElement,
  HTMLSelectElement,
  HTMLTextAreaElement
} from "./wrappers/HTMLElement.ts";
import { MutationObserver } from "./wrappers/MutationObserver.ts";
import { Node } from "./wrappers/Node.ts";
import { NodeList } from "./wrappers/NodeList.ts";
import { Range, Selection } from "./wrappers/Range.ts";
import { Storage } from "./wrappers/Storage.ts";
import { Text } from "./wrappers/Text.ts";
import { Window, type WindowOptions } from "./wrappers/Window.ts";

class Page {
  readonly window: Window;
  readonly mainFrame: { document: Document };

  constructor(options?: WindowOptions) {
    this.window = new Window(options);
    this.mainFrame = {
      document: this.window.document
    };
  }

  get content(): string {
    return this.window.document.documentElement.outerHTML;
  }

  set content(value: string) {
    this.window.document.body.innerHTML = value;
  }

  get url(): string {
    return this.window.location.href;
  }

  set url(next: string) {
    this.window.location.href = next;
  }

  async waitUntilComplete(): Promise<void> {
    await Promise.resolve();
  }

  abort(): void {
    this.window.happyDOM.abort();
  }

  close(): void {
    this.window.close();
  }
}

class BrowserContext {
  readonly #pages: Page[] = [];

  newPage(options?: WindowOptions): Page {
    const page = new Page(options);
    this.#pages.push(page);
    return page;
  }

  close(): void {
    for (const page of this.#pages) {
      page.close();
    }
    this.#pages.length = 0;
  }
}

class Browser {
  readonly #context = new BrowserContext();

  static async create(): Promise<Browser> {
    return new Browser();
  }

  newPage(options?: WindowOptions): Page {
    return this.#context.newPage(options);
  }

  defaultContext(): BrowserContext {
    return this.#context;
  }

  close(): void {
    this.#context.close();
  }
}

export {
  Browser,
  BrowserContext,
  Comment,
  CustomElementRegistry,
  CustomEvent,
  Document,
  DocumentFragment,
  ZigDOMException as DOMException,
  Element,
  Event,
  GlobalRegistrator,
  HTMLButtonElement,
  HTMLCollection,
  HTMLElement,
  HTMLFormElement,
  HTMLIFrameElement,
  HTMLInputElement,
  HTMLLabelElement,
  HTMLOptionElement,
  HTMLSelectElement,
  HTMLTextAreaElement,
  InputEvent,
  KeyboardEvent,
  MouseEvent,
  MutationObserver,
  Node,
  NodeList,
  Page,
  PropertySymbol,
  Range,
  Selection,
  Storage,
  Text,
  Window
};

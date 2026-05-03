import { PropertySymbol } from "./compatibility/happy-dom-symbols.js";
import { GlobalRegistrator } from "./global-registrator.js";
import { Comment } from "./wrappers/Comment.js";
import { Document } from "./wrappers/Document.js";
import { DocumentFragment } from "./wrappers/DocumentFragment.js";
import { Element } from "./wrappers/Element.js";
import { CustomEvent, Event, MouseEvent } from "./wrappers/Event.js";
import { HTMLCollection } from "./wrappers/HTMLCollection.js";
import { HTMLButtonElement, HTMLElement, HTMLFormElement, HTMLIFrameElement, HTMLInputElement } from "./wrappers/HTMLElement.js";
import { Node } from "./wrappers/Node.js";
import { NodeList } from "./wrappers/NodeList.js";
import { Text } from "./wrappers/Text.js";
import { Window, type WindowOptions } from "./wrappers/Window.js";

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
  CustomEvent,
  Document,
  DocumentFragment,
  Element,
  Event,
  GlobalRegistrator,
  HTMLButtonElement,
  HTMLCollection,
  HTMLElement,
  HTMLFormElement,
  HTMLIFrameElement,
  HTMLInputElement,
  MouseEvent,
  Node,
  NodeList,
  Page,
  PropertySymbol,
  Text,
  Window
};

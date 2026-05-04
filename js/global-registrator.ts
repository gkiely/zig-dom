import { Comment } from "./wrappers/Comment.ts";
import { ZigDOMException } from "./wrappers/DOMException.ts";
import { Document } from "./wrappers/Document.ts";
import { DocumentFragment } from "./wrappers/DocumentFragment.ts";
import { Element } from "./wrappers/Element.ts";
import { CompositionEvent, CustomEvent, Event, EventTargetBase, FocusEvent, InputEvent, KeyboardEvent, MouseEvent, UIEvent, WheelEvent } from "./wrappers/Event.ts";
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
import { Range, Selection } from "./wrappers/Range.ts";
import { Text } from "./wrappers/Text.ts";
import { Window, type WindowOptions } from "./wrappers/Window.ts";

export class GlobalRegistrator {
  static #registeredWindow: Window | null = null;

  static register(options?: WindowOptions & { forceNewWindow?: boolean }): Window {
    if (!options?.forceNewWindow && GlobalRegistrator.#registeredWindow && !GlobalRegistrator.#registeredWindow.closed) {
      return GlobalRegistrator.#registeredWindow;
    }

    const window = new Window(options);
    GlobalRegistrator.#registeredWindow = window;

    const assignments: Record<string, unknown> = {
      window,
      self: window,
      document: window.document,
      Node,
      Element,
      HTMLElement,
      HTMLButtonElement,
      HTMLIFrameElement,
      HTMLInputElement,
      HTMLFormElement,
      HTMLLabelElement,
      HTMLSelectElement,
      HTMLOptionElement,
      HTMLTextAreaElement,
      Text,
      Comment,
      DocumentFragment,
      Event,
      EventTarget: EventTargetBase,
      UIEvent,
      FocusEvent,
      CustomEvent,
      MouseEvent,
      WheelEvent,
      InputEvent,
      CompositionEvent,
      KeyboardEvent,
      MutationObserver,
      DOMException: ZigDOMException,
      Range,
      Selection,
      Document,
      navigator: { userAgent: "zig-dom" },
      happyDOM: window.happyDOM,
      getSelection: () => window.getSelection(),
      localStorage: window.localStorage,
      sessionStorage: window.sessionStorage,
      location: window.location,
      history: window.history,
      customElements: window.customElements,
      getComputedStyle: window.getComputedStyle,
      requestAnimationFrame: window.requestAnimationFrame,
      cancelAnimationFrame: window.cancelAnimationFrame,
      queueMicrotask: window.queueMicrotask,
      performance: window.performance,
      fetch: window.fetch,
      Headers: window.Headers,
      Request: window.Request,
      Response: window.Response,
      FormData: window.FormData,
      Blob: window.Blob,
      File: window.File,
      URL: window.URL,
      URLSearchParams: globalThis.URLSearchParams,
      AbortController: window.AbortController,
      AbortSignal: window.AbortSignal,
      DOMParser: (window as unknown as { DOMParser?: unknown }).DOMParser
    };

    for (const [key, value] of Object.entries(assignments)) {
      Object.defineProperty(globalThis, key, {
        value,
        writable: true,
        configurable: true,
        enumerable: true
      });
    }

    Object.defineProperty(globalThis, "setTimeout", {
      value: window.setTimeout,
      writable: true,
      configurable: true
    });
    Object.defineProperty(globalThis, "clearTimeout", {
      value: window.clearTimeout,
      writable: true,
      configurable: true
    });
    Object.defineProperty(globalThis, "setInterval", {
      value: window.setInterval,
      writable: true,
      configurable: true
    });
    Object.defineProperty(globalThis, "clearInterval", {
      value: window.clearInterval,
      writable: true,
      configurable: true
    });

    return window;
  }

  static reset(): void {
    if (!GlobalRegistrator.#registeredWindow || GlobalRegistrator.#registeredWindow.closed) {
      return;
    }
    GlobalRegistrator.#registeredWindow.happyDOM.reset();
  }

  static unregister(): void {
    if (!GlobalRegistrator.#registeredWindow) {
      return;
    }

    if (!GlobalRegistrator.#registeredWindow.closed) {
      GlobalRegistrator.#registeredWindow.close();
    }

    GlobalRegistrator.#registeredWindow = null;
  }

  static currentWindow(): Window | null {
    return GlobalRegistrator.#registeredWindow;
  }
}

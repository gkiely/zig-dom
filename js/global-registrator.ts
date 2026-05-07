export type WindowOptions = {
  url?: string;
  forceNewWindow?: boolean;
};

function assignWindowUrl(windowObject: Window, url: string | undefined): void {
  if (!url) return;
  try {
    windowObject.location.href = url;
  } catch {
    // Native test environments may expose a partially implemented Location.
  }
}

export class GlobalRegistrator {
  static #registeredWindow: Window | null = null;

  static register(options?: WindowOptions): Window {
    if (!options?.forceNewWindow && GlobalRegistrator.#registeredWindow && !GlobalRegistrator.#registeredWindow.closed) {
      return GlobalRegistrator.#registeredWindow;
    }

    const windowObject = globalThis.window ?? new Window();
    assignWindowUrl(windowObject, options?.url);
    GlobalRegistrator.#registeredWindow = windowObject;

    const assignments: Record<string, unknown> = {
      window: windowObject,
      self: windowObject,
      document: windowObject.document,
      navigator: windowObject.navigator,
      location: windowObject.location,
      history: windowObject.history,
      customElements: (windowObject as unknown as { customElements?: unknown }).customElements,
      localStorage: windowObject.localStorage,
      sessionStorage: windowObject.sessionStorage,
      getSelection: windowObject.getSelection?.bind(windowObject),
      getComputedStyle: windowObject.getComputedStyle?.bind(windowObject),
      addEventListener: windowObject.addEventListener?.bind(windowObject),
      removeEventListener: windowObject.removeEventListener?.bind(windowObject),
      dispatchEvent: windowObject.dispatchEvent?.bind(windowObject),
      requestAnimationFrame: windowObject.requestAnimationFrame?.bind(windowObject),
      cancelAnimationFrame: windowObject.cancelAnimationFrame?.bind(windowObject)
    };

    for (const [key, value] of Object.entries(assignments)) {
      if (value === undefined) continue;
      Object.defineProperty(globalThis, key, {
        value,
        writable: true,
        configurable: true,
        enumerable: true
      });
    }

    return windowObject;
  }

  static reset(): void {
    const happyDOM = (GlobalRegistrator.#registeredWindow as unknown as { happyDOM?: { reset?: () => void } } | null)?.happyDOM;
    if (happyDOM && typeof happyDOM.reset === "function") {
      happyDOM.reset();
    }
  }

  static unregister(): void {
    const windowObject = GlobalRegistrator.#registeredWindow;
    if (windowObject && typeof windowObject.close === "function") {
      windowObject.close();
    }
    GlobalRegistrator.#registeredWindow = null;
  }

  static currentWindow(): Window | null {
    return GlobalRegistrator.#registeredWindow;
  }
}

export default { GlobalRegistrator };

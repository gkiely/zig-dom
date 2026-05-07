const GLOBAL_KEYS_TO_SYNC = [
  "window",
  "self",
  "document",
  "location",
  "history",
  "navigator",
  "Node",
  "Element",
  "HTMLElement",
  "Document",
  "DocumentFragment",
  "Text",
  "Comment",
  "Event",
  "CustomEvent",
  "MutationObserver",
  "DOMException",
  "URL",
  "URLSearchParams",
  "fetch",
  "Headers",
  "Request",
  "Response",
  "FormData",
  "Blob",
  "File",
  "Image",
  "DOMParser",
  "customElements",
  "localStorage",
  "sessionStorage",
  "getSelection",
  "getComputedStyle",
  "addEventListener",
  "removeEventListener",
  "dispatchEvent",
  "scrollTo",
  "scroll",
  "scrollBy",
  "requestAnimationFrame",
  "cancelAnimationFrame",
  "crypto",
  "CSS",
  "AbortController",
  "AbortSignal",
  "performance",
  "setTimeout",
  "clearTimeout",
  "setInterval",
  "clearInterval",
  "queueMicrotask",
  "atob",
  "btoa",
];

const BIND_WINDOW_METHOD_KEYS = new Set([
  "fetch",
  "getSelection",
  "getComputedStyle",
  "addEventListener",
  "removeEventListener",
  "dispatchEvent",
  "scrollTo",
  "scroll",
  "scrollBy",
  "requestAnimationFrame",
  "cancelAnimationFrame",
]);

let trackedWindow = null;

function getNativeWindow() {
  if (globalThis.window && typeof globalThis.window === "object") {
    return globalThis.window;
  }
  return globalThis;
}

function syncCommonGlobals(windowObject) {
  for (const key of GLOBAL_KEYS_TO_SYNC) {
    if (key in windowObject) {
      const value = windowObject[key];
      if (typeof value === "function" && BIND_WINDOW_METHOD_KEYS.has(key)) {
        globalThis[key] = value.bind(windowObject);
      } else {
        globalThis[key] = value;
      }
    }
  }
}

function createLocation(initialHref) {
  let current = new URL(initialHref || "http://localhost/");

  const location = {
    get href() {
      return current.href;
    },
    set href(next) {
      current = new URL(String(next ?? ""), current.href);
    },
    get protocol() {
      return current.protocol;
    },
    set protocol(next) {
      const updated = new URL(current.href);
      updated.protocol = String(next ?? "");
      current = updated;
    },
    get host() {
      return current.host;
    },
    set host(next) {
      const updated = new URL(current.href);
      updated.host = String(next ?? "");
      current = updated;
    },
    get hostname() {
      return current.hostname;
    },
    set hostname(next) {
      const updated = new URL(current.href);
      updated.hostname = String(next ?? "");
      current = updated;
    },
    get port() {
      return current.port;
    },
    set port(next) {
      const updated = new URL(current.href);
      updated.port = String(next ?? "");
      current = updated;
    },
    get pathname() {
      return current.pathname;
    },
    set pathname(next) {
      const updated = new URL(current.href);
      updated.pathname = String(next ?? "");
      current = updated;
    },
    get search() {
      return current.search;
    },
    set search(next) {
      const updated = new URL(current.href);
      updated.search = String(next ?? "");
      current = updated;
    },
    get hash() {
      return current.hash;
    },
    set hash(next) {
      const updated = new URL(current.href);
      updated.hash = String(next ?? "");
      current = updated;
    },
    get origin() {
      return current.origin;
    },
    assign(next) {
      this.href = next;
    },
    replace(next) {
      this.href = next;
    },
    toString() {
      return this.href;
    },
  };

  return location;
}

function ensureLocation(windowObject) {
  const existing = windowObject.location;
  const initialHref = existing && typeof existing.href === "string" ? existing.href : "http://localhost/";
  if (existing && typeof existing.assign === "function" && typeof existing.toString === "function") {
    return;
  }

  windowObject.location = createLocation(initialHref);
}

function ensureSelection(windowObject) {
  if (typeof windowObject.getSelection === "function") {
    return;
  }

  const selection = {
    isCollapsed: true,
    rangeCount: 0,
    removeAllRanges() {
      this.isCollapsed = true;
      this.rangeCount = 0;
    },
    addRange() {
      this.isCollapsed = false;
      this.rangeCount = 1;
    },
    toString() {
      return "";
    },
  };

  windowObject.getSelection = () => selection;
}

function ensureHistory(windowObject) {
  if (windowObject.history && typeof windowObject.history.pushState === "function") {
    return;
  }

  const entries = [{ state: null, href: windowObject.location.href }];
  let index = 0;

  const emitPopState = () => {
    const target = windowObject.dispatchEvent ? windowObject : globalThis;
    try {
      const event = new Event("popstate");
      event.state = entries[index]?.state ?? null;
      target.dispatchEvent(event);
    } catch {
      // Ignore dispatch errors in lightweight shim mode.
    }
  };

  const history = {
    state: null,
    pushState(state, _unused, url) {
      const href = url == null ? windowObject.location.href : new URL(String(url), windowObject.location.href).href;
      entries.splice(index + 1);
      entries.push({ state, href });
      index = entries.length - 1;
      this.state = state;
      windowObject.location.href = href;
    },
    replaceState(state, _unused, url) {
      const href = url == null ? windowObject.location.href : new URL(String(url), windowObject.location.href).href;
      entries[index] = { state, href };
      this.state = state;
      windowObject.location.href = href;
    },
    go(delta = 0) {
      const nextIndex = index + Number(delta || 0);
      if (!Number.isInteger(nextIndex) || nextIndex < 0 || nextIndex >= entries.length) {
        return;
      }
      index = nextIndex;
      const entry = entries[index];
      this.state = entry?.state ?? null;
      windowObject.location.href = entry?.href ?? windowObject.location.href;
      emitPopState();
    },
    back() {
      this.go(-1);
    },
    forward() {
      this.go(1);
    },
  };

  Object.defineProperty(history, "length", {
    configurable: true,
    enumerable: true,
    get() {
      return entries.length;
    },
  });

  windowObject.history = history;
}

function applyURL(nextUrl) {
  if (!nextUrl) {
    return;
  }

  const windowObject = getNativeWindow();
  const location = windowObject.location || globalThis.location;
  if (!location) {
    return;
  }

  try {
    const value = String(nextUrl);
    const next = new URL(value, location.href || undefined);
    const assign = (key, part) => {
      try {
        location[key] = part;
      } catch {
        // Ignore read-only location fields.
      }
    };

    assign("href", next.href);
    assign("protocol", next.protocol);
    assign("host", next.host);
    assign("hostname", next.hostname);
    assign("port", next.port);
    assign("pathname", next.pathname);
    assign("search", next.search);
    assign("hash", next.hash);
  } catch {
    // Ignore invalid URL input to keep setup resilient.
  }
}

function clearBody() {
  const doc = globalThis.document;
  if (doc && doc.body) {
    doc.body.innerHTML = "";
  }
}

function ensureHappyDOM(windowObject) {
  const existing = windowObject.happyDOM;
  if (!existing || typeof existing !== "object") {
    windowObject.happyDOM = {
      reset() {
        clearBody();
      },
      setURL(url) {
        applyURL(url);
      },
      whenAsyncComplete() {
        return Promise.resolve();
      },
    };
    return;
  }

  if (typeof existing.reset !== "function") {
    existing.reset = () => {
      clearBody();
    };
  }

  if (typeof existing.setURL !== "function") {
    existing.setURL = (url) => {
      applyURL(url);
    };
  }

  if (typeof existing.whenAsyncComplete !== "function") {
    existing.whenAsyncComplete = () => Promise.resolve();
  }
}

class GlobalRegistrator {
  static register(options = {}) {
    const windowObject = getNativeWindow();
    const originalDocument = globalThis.document;

    ensureLocation(windowObject);
    ensureSelection(windowObject);
    ensureHistory(windowObject);

    trackedWindow = windowObject;

    globalThis.window = windowObject;
    globalThis.self = windowObject;
    if (windowObject.document) {
      globalThis.document = windowObject.document;
    }

    syncCommonGlobals(windowObject);

    if (originalDocument !== undefined && windowObject.document === originalDocument) {
      globalThis.document = originalDocument;
    }

    ensureHappyDOM(windowObject);

    if (options && typeof options === "object" && "url" in options) {
      windowObject.happyDOM.setURL(options.url);
    }

    return windowObject;
  }

  static reset() {
    clearBody();
  }

  static unregister() {
    trackedWindow = null;
  }

  static currentWindow() {
    return trackedWindow || getNativeWindow();
  }
}

export { GlobalRegistrator };
export default { GlobalRegistrator };

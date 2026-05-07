const GLOBAL_KEYS_TO_SYNC = [
  "window",
  "self",
  "document",
  "location",
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
  "crypto",
  "performance",
  "setTimeout",
  "clearTimeout",
  "setInterval",
  "clearInterval",
  "queueMicrotask",
  "atob",
  "btoa",
];

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
      globalThis[key] = windowObject[key];
    }
  }
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

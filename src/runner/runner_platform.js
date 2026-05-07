(() => {
  if (typeof globalThis.queueMicrotask !== "function") {
    globalThis.queueMicrotask = function queueMicrotask(callback) {
      Promise.resolve().then(() => {
        if (typeof callback === "function") {
          callback();
        }
      });
    };
  }

  if (typeof globalThis.TextEncoder !== "function") {
    globalThis.TextEncoder = class TextEncoder {
      encode(input = "") {
        const text = String(input);
        const encoded = unescape(encodeURIComponent(text));
        const bytes = new Uint8Array(encoded.length);
        for (let index = 0; index < encoded.length; index += 1) {
          bytes[index] = encoded.charCodeAt(index);
        }
        return bytes;
      }
    };
  }

  if (typeof globalThis.TextDecoder !== "function") {
    globalThis.TextDecoder = class TextDecoder {
      decode(input) {
        if (!input) {
          return "";
        }

        const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
        let encoded = "";
        for (let index = 0; index < bytes.length; index += 1) {
          encoded += String.fromCharCode(bytes[index]);
        }
        try {
          return decodeURIComponent(escape(encoded));
        } catch {
          return encoded;
        }
      }
    };
  }

  if (typeof globalThis.Buffer !== "function") {
    function decodeBase64(input) {
      const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      const cleaned = String(input || "").replace(/=+$/, "").replace(/\s+/g, "");
      const output = [];
      let bits = 0;
      let value = 0;

      for (let index = 0; index < cleaned.length; index += 1) {
        const code = alphabet.indexOf(cleaned[index]);
        if (code < 0) {
          continue;
        }
        value = (value << 6) | code;
        bits += 6;
        if (bits >= 8) {
          bits -= 8;
          output.push((value >> bits) & 0xff);
        }
      }

      return new Uint8Array(output);
    }

    class BufferImpl extends Uint8Array {
      static from(input, encoding) {
        if (typeof input === "string") {
          if (encoding === "base64") {
            return new BufferImpl(decodeBase64(input));
          }
          return new BufferImpl(new globalThis.TextEncoder().encode(input));
        }

        if (input instanceof ArrayBuffer) {
          return new BufferImpl(new Uint8Array(input));
        }

        if (ArrayBuffer.isView(input) || Array.isArray(input)) {
          return new BufferImpl(input);
        }

        return new BufferImpl(0);
      }

      static alloc(size, fill = 0) {
        const next = new BufferImpl(Number(size) || 0);
        next.fill(fill);
        return next;
      }

      static allocUnsafe(size) {
        return new BufferImpl(Number(size) || 0);
      }

      static isBuffer(value) {
        return value instanceof Uint8Array;
      }

      static get [Symbol.species]() {
        return BufferImpl;
      }

      toString(encoding) {
        if (encoding === "base64") {
          const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
          let output = "";
          for (let index = 0; index < this.length; index += 3) {
            const b0 = this[index] ?? 0;
            const b1 = this[index + 1] ?? 0;
            const b2 = this[index + 2] ?? 0;
            const chunk = (b0 << 16) | (b1 << 8) | b2;
            output += alphabet[(chunk >> 18) & 63];
            output += alphabet[(chunk >> 12) & 63];
            output += index + 1 < this.length ? alphabet[(chunk >> 6) & 63] : "=";
            output += index + 2 < this.length ? alphabet[chunk & 63] : "=";
          }
          return output;
        }

        return new globalThis.TextDecoder().decode(this);
      }
    }

    globalThis.Buffer = BufferImpl;
  }

  if (typeof globalThis.setTimeout !== "function") {
    let timeoutIdCounter = 1;
    const cancelledTimeouts = new Set();

    globalThis.setTimeout = function setTimeout(callback, _delay, ...args) {
      const id = timeoutIdCounter;
      timeoutIdCounter += 1;

      Promise.resolve().then(() => {
        if (cancelledTimeouts.has(id)) {
          cancelledTimeouts.delete(id);
          return;
        }

        if (typeof callback === "function") {
          callback(...args);
          return;
        }

        if (typeof callback === "string") {
          Function(callback)();
        }
      });

      return id;
    };

    globalThis.clearTimeout = function clearTimeout(id) {
      cancelledTimeouts.add(Number(id));
    };
  }

  if (typeof globalThis.setInterval !== "function") {
    globalThis.setInterval = function setInterval(callback, delay, ...args) {
      const schedule = () => {
        const timeoutId = globalThis.setTimeout(() => {
          if (typeof callback === "function") {
            callback(...args);
          }
          schedule();
        }, delay);
        return timeoutId;
      };

      return schedule();
    };
  }

  if (typeof globalThis.clearInterval !== "function") {
    globalThis.clearInterval = function clearInterval(id) {
      globalThis.clearTimeout(id);
    };
  }

  if (typeof globalThis.setImmediate !== "function") {
    let immediateIdCounter = 1;
    const cancelledImmediates = new Set();

    globalThis.setImmediate = function setImmediate(callback, ...args) {
      const id = immediateIdCounter;
      immediateIdCounter += 1;

      Promise.resolve().then(() => {
        if (cancelledImmediates.has(id)) {
          cancelledImmediates.delete(id);
          return;
        }

        if (typeof callback === "function") {
          callback(...args);
        }
      });

      return id;
    };

    globalThis.clearImmediate = function clearImmediate(id) {
      cancelledImmediates.add(Number(id));
    };
  }

  if (globalThis.window && typeof globalThis.window === "object") {
    if (!globalThis.window.queueMicrotask) {
      globalThis.window.queueMicrotask = globalThis.queueMicrotask;
    }
    if (!globalThis.window.setTimeout) {
      globalThis.window.setTimeout = globalThis.setTimeout;
    }
    if (!globalThis.window.clearTimeout) {
      globalThis.window.clearTimeout = globalThis.clearTimeout;
    }
    if (!globalThis.window.setInterval) {
      globalThis.window.setInterval = globalThis.setInterval;
    }
    if (!globalThis.window.clearInterval) {
      globalThis.window.clearInterval = globalThis.clearInterval;
    }
    if (!globalThis.window.setImmediate) {
      globalThis.window.setImmediate = globalThis.setImmediate;
    }
    if (!globalThis.window.clearImmediate) {
      globalThis.window.clearImmediate = globalThis.clearImmediate;
    }
    if (!globalThis.window.Buffer) {
      globalThis.window.Buffer = globalThis.Buffer;
    }
  }



})();

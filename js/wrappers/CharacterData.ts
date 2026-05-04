import { ZigDOMException } from "./DOMException.ts";
import { Node } from "./Node.ts";
import { notifyCharacterDataMutation } from "./Range.ts";
import type { Window } from "./Window.ts";

export class CharacterData extends Node {
  #suppressRangeTextContentNotification = false;

  constructor(window: Window, handle: number, nodeType = Node.TEXT_NODE) {
    super(window, handle, nodeType);
  }

  get textContent(): string {
    return super.textContent;
  }

  set textContent(value: string | null) {
    const previous = super.textContent ?? "";
    const next = value === null ? "" : String(value);
    super.textContent = next;
    if (!this.#suppressRangeTextContentNotification) {
      notifyCharacterDataMutation(this, 0, previous.length, next.length);
    }
  }

  get data(): string {
    return this.textContent;
  }

  set data(value: string) {
    this.textContent = value === null ? "" : String(value);
  }

  get length(): number {
    return this.data.length;
  }

  substringData(offset: number, count: number): string {
    if (arguments.length < 2) {
      throw new TypeError("Failed to execute 'substringData': 2 arguments required.");
    }
    const start = normalizeOffset(offset, this.length);
    const size = normalizeCount(count);
    return this.data.slice(start, start + size);
  }

  appendData(data: string): void {
    if (arguments.length < 1) {
      throw new TypeError("Failed to execute 'appendData': 1 argument required.");
    }
    const source = this.data;
    const text = String(data);
    this._setTextContentWithoutRangeNotification(`${source}${text}`);
    notifyCharacterDataMutation(this, source.length, 0, text.length);
  }

  insertData(offset: number, data: string): void {
    if (arguments.length < 2) {
      throw new TypeError("Failed to execute 'insertData': 2 arguments required.");
    }
    const start = normalizeOffset(offset, this.length);
    const source = this.data;
    const text = String(data);
    this._setTextContentWithoutRangeNotification(`${source.slice(0, start)}${text}${source.slice(start)}`);
    notifyCharacterDataMutation(this, start, 0, text.length);
  }

  deleteData(offset: number, count: number): void {
    if (arguments.length < 2) {
      throw new TypeError("Failed to execute 'deleteData': 2 arguments required.");
    }
    const start = normalizeOffset(offset, this.length);
    const size = normalizeCount(count);
    const source = this.data;
    const removed = Math.min(size, Math.max(0, source.length - start));
    this._setTextContentWithoutRangeNotification(`${source.slice(0, start)}${source.slice(start + size)}`);
    notifyCharacterDataMutation(this, start, removed, 0);
  }

  replaceData(offset: number, count: number, data: string): void {
    if (arguments.length < 3) {
      throw new TypeError("Failed to execute 'replaceData': 3 arguments required.");
    }
    const start = normalizeOffset(offset, this.length);
    const size = normalizeCount(count);
    const source = this.data;
    const text = String(data);
    const removed = Math.min(size, Math.max(0, source.length - start));
    this._setTextContentWithoutRangeNotification(`${source.slice(0, start)}${text}${source.slice(start + size)}`);
    notifyCharacterDataMutation(this, start, removed, text.length);
  }

  protected _setTextContentWithoutRangeNotification(value: string): void {
    this.#suppressRangeTextContentNotification = true;
    try {
      this.textContent = value;
    } finally {
      this.#suppressRangeTextContentNotification = false;
    }
  }
}

function normalizeOffset(offset: number, max: number): number {
  const value = toUnsignedLong(offset);
  if (value > max) {
    throw new ZigDOMException("The index is not in the allowed range.", "IndexSizeError", 1);
  }
  return value;
}

function normalizeCount(count: number): number {
  return toUnsignedLong(count);
}

function toUnsignedLong(value: unknown): number {
  return Number(value) >>> 0;
}

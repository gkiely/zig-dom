import { ZigDOMException } from "./DOMException.ts";
import { Node } from "./Node.ts";
import type { Window } from "./Window.ts";

export class CharacterData extends Node {
  constructor(window: Window, handle: number, nodeType = Node.TEXT_NODE) {
    super(window, handle, nodeType);
  }

  get data(): string {
    return this.textContent;
  }

  set data(value: string) {
    this.textContent = value;
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
    this.data = `${this.data}${String(data)}`;
  }

  insertData(offset: number, data: string): void {
    if (arguments.length < 2) {
      throw new TypeError("Failed to execute 'insertData': 2 arguments required.");
    }
    const start = normalizeOffset(offset, this.length);
    const source = this.data;
    const text = String(data);
    this.data = `${source.slice(0, start)}${text}${source.slice(start)}`;
  }

  deleteData(offset: number, count: number): void {
    if (arguments.length < 2) {
      throw new TypeError("Failed to execute 'deleteData': 2 arguments required.");
    }
    const start = normalizeOffset(offset, this.length);
    const size = normalizeCount(count);
    const source = this.data;
    this.data = `${source.slice(0, start)}${source.slice(start + size)}`;
  }

  replaceData(offset: number, count: number, data: string): void {
    if (arguments.length < 3) {
      throw new TypeError("Failed to execute 'replaceData': 3 arguments required.");
    }
    const start = normalizeOffset(offset, this.length);
    const size = normalizeCount(count);
    const source = this.data;
    const text = String(data);
    this.data = `${source.slice(0, start)}${text}${source.slice(start + size)}`;
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

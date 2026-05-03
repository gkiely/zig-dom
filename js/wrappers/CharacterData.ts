import { Node } from "./Node.ts";
import { ZigDOMException } from "./DOMException.ts";
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
    const start = normalizeOffset(offset, this.length);
    const size = normalizeCount(count);
    return this.data.slice(start, start + size);
  }

  appendData(data: string): void {
    this.data = `${this.data}${String(data)}`;
  }

  insertData(offset: number, data: string): void {
    const start = normalizeOffset(offset, this.length);
    const source = this.data;
    const text = String(data);
    this.data = `${source.slice(0, start)}${text}${source.slice(start)}`;
  }

  deleteData(offset: number, count: number): void {
    const start = normalizeOffset(offset, this.length);
    const size = normalizeCount(count);
    const source = this.data;
    this.data = `${source.slice(0, start)}${source.slice(start + size)}`;
  }

  replaceData(offset: number, count: number, data: string): void {
    const start = normalizeOffset(offset, this.length);
    const size = normalizeCount(count);
    const source = this.data;
    const text = String(data);
    this.data = `${source.slice(0, start)}${text}${source.slice(start + size)}`;
  }
}

function normalizeOffset(offset: number, max: number): number {
  const value = Number(offset);
  if (!Number.isFinite(value) || value < 0 || value > max) {
    throw new ZigDOMException("The index is not in the allowed range.", "IndexSizeError", 1);
  }
  return Math.floor(value);
}

function normalizeCount(count: number): number {
  const value = Number(count);
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.floor(value));
}

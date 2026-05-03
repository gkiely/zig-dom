import type { Node } from "./Node.ts";

export type MutationObserverCallback = (records: MutationRecord[], observer: MutationObserver) => void;

export class MutationObserver {
  readonly #callback: MutationObserverCallback;
  #records: MutationRecord[] = [];

  constructor(callback: MutationObserverCallback) {
    this.#callback = callback;
  }

  observe(_target: Node, _options?: MutationObserverInit): void {
    void this.#callback;
  }

  disconnect(): void {
    this.#records = [];
  }

  takeRecords(): MutationRecord[] {
    const records = this.#records;
    this.#records = [];
    return records;
  }
}

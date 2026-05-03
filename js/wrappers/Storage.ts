export class Storage {
  #items = new Map<string, string>();

  get length(): number {
    return this.#items.size;
  }

  key(index: number): string | null {
    return [...this.#items.keys()][index] ?? null;
  }

  getItem(key: string): string | null {
    return this.#items.get(String(key)) ?? null;
  }

  setItem(key: string, value: string): void {
    this.#items.set(String(key), String(value));
  }

  removeItem(key: string): void {
    this.#items.delete(String(key));
  }

  clear(): void {
    this.#items.clear();
  }
}

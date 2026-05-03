type CustomElementConstructor = {
  prototype: Element;
  new (): Element;
};

export class CustomElementRegistry {
  #definitions = new Map<string, CustomElementConstructor>();
  #pending = new Map<string, Array<() => void>>();
  readonly #onDefine?: (name: string) => void;

  constructor(onDefine?: (name: string) => void) {
    this.#onDefine = onDefine;
  }

  get hasDefinitions(): boolean {
    return this.#definitions.size > 0;
  }

  define(name: string, constructor: CustomElementConstructor): void {
    const normalized = name.toLowerCase();
    if (!normalized.includes("-")) {
      throw new Error("Custom element name must contain a hyphen");
    }
    if (this.#definitions.has(normalized)) {
      throw new Error(`Custom element already defined: ${normalized}`);
    }

    this.#definitions.set(normalized, constructor);
    this.#onDefine?.(normalized);
    const waiters = this.#pending.get(normalized) ?? [];
    this.#pending.delete(normalized);
    for (const resolve of waiters) {
      resolve();
    }
  }

  get(name: string): CustomElementConstructor | undefined {
    return this.#definitions.get(name.toLowerCase());
  }

  whenDefined(name: string): Promise<void> {
    const normalized = name.toLowerCase();
    if (this.#definitions.has(normalized)) {
      return Promise.resolve();
    }

    return new Promise<void>((resolve) => {
      const waiters = this.#pending.get(normalized) ?? [];
      waiters.push(resolve);
      this.#pending.set(normalized, waiters);
    });
  }
}

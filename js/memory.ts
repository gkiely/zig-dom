export interface HandleReleaser {
  releaseHandle(handle: number): void;
}

export class NativeHandleRegistry {
  #registry: FinalizationRegistry<number>;

  constructor(private readonly releaser: HandleReleaser) {
    this.#registry = new FinalizationRegistry<number>((handle) => {
      this.releaser.releaseHandle(handle);
    });
  }

  track(target: object, handle: number): void {
    this.#registry.register(target, handle, target);
  }

  untrack(target: object): void {
    this.#registry.unregister(target);
  }
}

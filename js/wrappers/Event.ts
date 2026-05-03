export type EventListenerCallback = (event: Event) => void;

export interface EventListenerObjectLike {
  handleEvent(event: Event): void;
}

export interface EventListenerOptionsLike {
  capture?: boolean;
}

export interface AddEventListenerOptionsLike extends EventListenerOptionsLike {
  once?: boolean;
}

type ListenerEntry = {
  callback: EventListenerCallback;
  capture: boolean;
  once: boolean;
};

export class Event {
  static readonly NONE = 0;
  static readonly CAPTURING_PHASE = 1;
  static readonly AT_TARGET = 2;
  static readonly BUBBLING_PHASE = 3;

  readonly type: string;
  readonly bubbles: boolean;
  readonly cancelable: boolean;

  target: EventTargetBase | null = null;
  currentTarget: EventTargetBase | null = null;
  eventPhase = Event.NONE;
  defaultPrevented = false;

  #propagationStopped = false;
  #immediatePropagationStopped = false;

  constructor(type: string, init?: EventInit) {
    this.type = type;
    this.bubbles = Boolean(init?.bubbles);
    this.cancelable = Boolean(init?.cancelable);
  }

  preventDefault(): void {
    if (this.cancelable) {
      this.defaultPrevented = true;
    }
  }

  stopPropagation(): void {
    this.#propagationStopped = true;
  }

  stopImmediatePropagation(): void {
    this.#propagationStopped = true;
    this.#immediatePropagationStopped = true;
  }

  get propagationStopped(): boolean {
    return this.#propagationStopped;
  }

  get immediatePropagationStopped(): boolean {
    return this.#immediatePropagationStopped;
  }
}

export class CustomEvent<T = unknown> extends Event {
  readonly detail: T;

  constructor(type: string, init?: CustomEventInit<T>) {
    super(type, init);
    this.detail = (init?.detail ?? null) as T;
  }
}

export class MouseEvent extends Event {
  readonly clientX: number;
  readonly clientY: number;
  readonly button: number;

  constructor(type: string, init?: MouseEventInit) {
    super(type, init);
    this.clientX = init?.clientX ?? 0;
    this.clientY = init?.clientY ?? 0;
    this.button = init?.button ?? 0;
  }
}

export class InputEvent extends Event {
  readonly data: string | null;
  readonly inputType: string;

  constructor(type: string, init?: InputEventInit) {
    super(type, init);
    this.data = init?.data ?? null;
    this.inputType = init?.inputType ?? "";
  }
}

export class KeyboardEvent extends Event {
  readonly key: string;
  readonly code: string;
  readonly ctrlKey: boolean;
  readonly shiftKey: boolean;
  readonly altKey: boolean;
  readonly metaKey: boolean;
  readonly repeat: boolean;

  constructor(type: string, init?: KeyboardEventInit) {
    super(type, init);
    this.key = init?.key ?? "";
    this.code = init?.code ?? "";
    this.ctrlKey = Boolean(init?.ctrlKey);
    this.shiftKey = Boolean(init?.shiftKey);
    this.altKey = Boolean(init?.altKey);
    this.metaKey = Boolean(init?.metaKey);
    this.repeat = Boolean(init?.repeat);
  }
}

export class EventTargetBase {
  #listeners = new Map<string, ListenerEntry[]>();

  addEventListener(type: string, callback: EventListenerCallback | EventListenerObjectLike | null, options?: boolean | AddEventListenerOptionsLike): void {
    if (!callback) return;

    const listenerCallback: EventListenerCallback = typeof callback === "function" ? callback : (event) => callback.handleEvent(event);
    const capture = typeof options === "boolean" ? options : Boolean(options?.capture);
    const once = Boolean(typeof options === "object" && options?.once);

    const existing = this.#listeners.get(type) ?? [];
    if (existing.some((entry) => entry.callback === listenerCallback && entry.capture === capture)) {
      return;
    }

    existing.push({ callback: listenerCallback, capture, once });
    this.#listeners.set(type, existing);
  }

  removeEventListener(type: string, callback: EventListenerCallback | EventListenerObjectLike | null, options?: boolean | EventListenerOptionsLike): void {
    if (!callback) return;

    const listenerCallback: EventListenerCallback = typeof callback === "function" ? callback : (event) => callback.handleEvent(event);
    const capture = typeof options === "boolean" ? options : Boolean(options?.capture);

    const existing = this.#listeners.get(type);
    if (!existing || existing.length === 0) return;

    const filtered = existing.filter((entry) => !(entry.callback === listenerCallback && entry.capture === capture));
    if (filtered.length === 0) {
      this.#listeners.delete(type);
      return;
    }

    this.#listeners.set(type, filtered);
  }

  dispatchEvent(event: Event): boolean {
    if (!event.target) {
      event.target = this;
    }
    event.currentTarget = this;
    event.eventPhase = Event.AT_TARGET;
    this.#invoke(event, false);
    this.#invoke(event, true);
    return !event.defaultPrevented;
  }

  protected invokeListeners(event: Event, capturePhase: boolean): void {
    this.#invoke(event, capturePhase);
  }

  #invoke(event: Event, capturePhase: boolean): void {
    const listeners = this.#listeners.get(event.type);
    if (!listeners || listeners.length === 0) {
      return;
    }

    for (const listener of [...listeners]) {
      if (listener.capture !== capturePhase) {
        continue;
      }
      listener.callback(event);
      if (listener.once) {
        this.removeEventListener(event.type, listener.callback, { capture: listener.capture });
      }
      if (event.immediatePropagationStopped) {
        break;
      }
    }
  }
}

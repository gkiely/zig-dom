export type EventListenerCallback = (event: Event) => void;

export interface EventListenerObjectLike {
  handleEvent(event: Event): void;
}

export interface EventListenerOptionsLike {
  capture?: boolean;
  passive?: boolean;
}

export interface AddEventListenerOptionsLike extends EventListenerOptionsLike {
  once?: boolean;
}

type ListenerEntry = {
  original: EventListenerCallback | EventListenerObjectLike;
  callback: EventListenerCallback;
  capture: boolean;
  once: boolean;
  passive: boolean;
};

export class Event {
  static readonly NONE = 0;
  static readonly CAPTURING_PHASE = 1;
  static readonly AT_TARGET = 2;
  static readonly BUBBLING_PHASE = 3;

  type: string;
  bubbles: boolean;
  cancelable: boolean;
  composed: boolean;

  target: EventTargetBase | null = null;
  currentTarget: EventTargetBase | null = null;
  eventPhase = Event.NONE;
  defaultPrevented = false;

  #propagationStopped = false;
  #immediatePropagationStopped = false;
  #path: EventTargetBase[] = [];

  constructor(type: string, init?: EventInit) {
    this.type = type;
    this.bubbles = Boolean(init?.bubbles);
    this.cancelable = Boolean(init?.cancelable);
    this.composed = Boolean(init?.composed);
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

  get cancelBubble(): boolean {
    return this.#propagationStopped;
  }

  set cancelBubble(value: boolean) {
    if (value) {
      this.stopPropagation();
    }
  }

  initEvent(type: string, bubbles = false, cancelable = false): void {
    this.type = type;
    this.bubbles = Boolean(bubbles);
    this.cancelable = Boolean(cancelable);
    this.defaultPrevented = false;
    this.#propagationStopped = false;
    this.#immediatePropagationStopped = false;
  }

  get propagationStopped(): boolean {
    return this.#propagationStopped;
  }

  get immediatePropagationStopped(): boolean {
    return this.#immediatePropagationStopped;
  }

  composedPath(): EventTarget[] {
    return [...this.#path] as unknown as EventTarget[];
  }

  setPath(path: EventTargetBase[]): void {
    this.#path = path;
  }
}

export class CustomEvent<T = unknown> extends Event {
  detail: T;

  constructor(type: string, init?: CustomEventInit<T>) {
    super(type, init);
    this.detail = (init?.detail ?? null) as T;
  }

  initCustomEvent(type: string, bubbles = false, cancelable = false, detail?: T): void {
    this.initEvent(type, bubbles, cancelable);
    this.detail = (detail ?? null) as T;
  }
}

export class MouseEvent extends Event {
  readonly clientX: number;
  readonly clientY: number;
  readonly button: number;
  readonly relatedTarget: EventTarget | null;

  constructor(type: string, init?: MouseEventInit) {
    super(type, init);
    this.clientX = init?.clientX ?? 0;
    this.clientY = init?.clientY ?? 0;
    this.button = init?.button ?? 0;
    this.relatedTarget = (init?.relatedTarget as EventTarget | null) ?? null;
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

export class CompositionEvent extends Event {
  readonly data: string;

  constructor(type: string, init?: CompositionEventInit) {
    super(type, init);
    this.data = init?.data ?? "";
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
  readonly location: number;

  constructor(type: string, init?: KeyboardEventInit) {
    super(type, init);
    this.key = init?.key ?? "";
    this.code = init?.code ?? "";
    this.ctrlKey = Boolean(init?.ctrlKey);
    this.shiftKey = Boolean(init?.shiftKey);
    this.altKey = Boolean(init?.altKey);
    this.metaKey = Boolean(init?.metaKey);
    this.repeat = Boolean(init?.repeat);
    this.location = init?.location ?? 0;
  }
}

export class EventTargetBase {
  #listeners = new Map<string, ListenerEntry[]>();

  addEventListener(type: string, callback: EventListenerCallback | EventListenerObjectLike | null, options?: boolean | AddEventListenerOptionsLike): void {
    if (!callback) return;

    const listenerCallback: EventListenerCallback = typeof callback === "function" ? callback : (event) => callback.handleEvent(event);
    const capture = typeof options === "boolean" ? options : Boolean(options?.capture);
    const once = Boolean(typeof options === "object" && options?.once);
    const passive = Boolean(typeof options === "object" && options?.passive);

    const existing = this.#listeners.get(type) ?? [];
    if (existing.some((entry) => entry.original === callback && entry.capture === capture)) {
      return;
    }

    existing.push({ original: callback, callback: listenerCallback, capture, once, passive });
    this.#listeners.set(type, existing);
  }

  removeEventListener(type: string, callback: EventListenerCallback | EventListenerObjectLike | null, options?: boolean | EventListenerOptionsLike): void {
    if (!callback) return;
    const capture = typeof options === "boolean" ? options : Boolean(options?.capture);

    const existing = this.#listeners.get(type);
    if (!existing || existing.length === 0) return;

    const filtered = existing.filter((entry) => !(entry.original === callback && entry.capture === capture));
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
        this.removeEventListener(event.type, listener.original, { capture: listener.capture });
      }
      if (event.immediatePropagationStopped) {
        break;
      }
    }
  }
}

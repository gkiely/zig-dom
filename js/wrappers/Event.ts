import { ZigDOMException } from "./DOMException.ts";

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
  readonly isTrusted = false;
  readonly timeStamp = globalThis.performance?.now?.() ?? Date.now();

  #propagationStopped = false;
  #immediatePropagationStopped = false;
  #path: EventTargetBase[] = [];
  #dispatchFlag = false;

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
    if (arguments.length === 0) {
      throw new TypeError("Failed to execute 'initEvent': 1 argument required.");
    }
    if (this.eventPhase !== Event.NONE) {
      return;
    }
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

  get returnValue(): boolean {
    return !this.defaultPrevented;
  }

  set returnValue(value: boolean) {
    if (value === false) {
      this.preventDefault();
    }
  }

  get srcElement(): EventTarget | null {
    return this.target as unknown as EventTarget | null;
  }

  composedPath(): EventTarget[] {
    return [...this.#path] as unknown as EventTarget[];
  }

  setPath(path: EventTargetBase[]): void {
    this.#path = path;
  }

  resetAfterDispatch(): void {
    this.#propagationStopped = false;
    this.#immediatePropagationStopped = false;
  }

  get dispatching(): boolean {
    return this.#dispatchFlag;
  }

  setDispatchFlag(value: boolean): void {
    this.#dispatchFlag = value;
  }
}

export class CustomEvent<T = unknown> extends Event {
  detail: T;

  constructor(type: string, init?: CustomEventInit<T>) {
    super(type, init);
    this.detail = (init?.detail ?? null) as T;
  }

  initCustomEvent(type: string, bubbles = false, cancelable = false, detail?: T): void {
    if (arguments.length === 0) {
      throw new TypeError("Failed to execute 'initCustomEvent': 1 argument required.");
    }
    if (this.eventPhase !== Event.NONE) {
      return;
    }
    this.initEvent(type, bubbles, cancelable);
    this.detail = (detail ?? null) as T;
  }
}

export class UIEvent extends Event {
  view: EventTarget | null;
  detail: number;

  constructor(type: string, init?: UIEventInit) {
    super(type, init);
    this.view = (init?.view as EventTarget | null) ?? null;
    this.detail = init?.detail ?? 0;
  }

  initUIEvent(type: string, bubbles = false, cancelable = false, view: EventTarget | null = null, detail = 0): void {
    if (this.eventPhase !== Event.NONE) {
      return;
    }
    this.initEvent(type, bubbles, cancelable);
    this.view = view;
    this.detail = detail;
  }
}

export class FocusEvent extends UIEvent {
  relatedTarget: EventTarget | null;

  constructor(type: string, init?: FocusEventInit) {
    super(type, init);
    this.relatedTarget = (init?.relatedTarget as EventTarget | null) ?? null;
  }
}

export class MouseEvent extends UIEvent {
  readonly clientX: number;
  readonly clientY: number;
  readonly screenX: number;
  readonly screenY: number;
  readonly ctrlKey: boolean;
  readonly shiftKey: boolean;
  readonly altKey: boolean;
  readonly metaKey: boolean;
  readonly button: number;
  readonly buttons: number;
  readonly relatedTarget: EventTarget | null;

  constructor(type: string, init?: MouseEventInit) {
    super(type, init);
    this.clientX = init?.clientX ?? 0;
    this.clientY = init?.clientY ?? 0;
    this.screenX = init?.screenX ?? 0;
    this.screenY = init?.screenY ?? 0;
    this.ctrlKey = Boolean(init?.ctrlKey);
    this.shiftKey = Boolean(init?.shiftKey);
    this.altKey = Boolean(init?.altKey);
    this.metaKey = Boolean(init?.metaKey);
    this.button = init?.button ?? 0;
    this.buttons = init?.buttons ?? 0;
    this.relatedTarget = (init?.relatedTarget as EventTarget | null) ?? null;
  }

  initMouseEvent(
    type: string,
    bubbles = false,
    cancelable = false,
    view: EventTarget | null = null,
    _detail = 0,
    screenX = 0,
    screenY = 0,
    clientX = 0,
    clientY = 0,
    ctrlKey = false,
    altKey = false,
    shiftKey = false,
    metaKey = false,
    button = 0,
    relatedTarget: EventTarget | null = null
  ): void {
    if (this.eventPhase !== Event.NONE) {
      return;
    }
    this.initUIEvent(type, bubbles, cancelable, view, 0);
    (this as { screenX: number }).screenX = screenX;
    (this as { screenY: number }).screenY = screenY;
    (this as { clientX: number }).clientX = clientX;
    (this as { clientY: number }).clientY = clientY;
    (this as { ctrlKey: boolean }).ctrlKey = ctrlKey;
    (this as { altKey: boolean }).altKey = altKey;
    (this as { shiftKey: boolean }).shiftKey = shiftKey;
    (this as { metaKey: boolean }).metaKey = metaKey;
    (this as { button: number }).button = button;
    (this as { relatedTarget: EventTarget | null }).relatedTarget = relatedTarget;
  }
}

export class WheelEvent extends MouseEvent {
  readonly deltaX: number;
  readonly deltaY: number;
  readonly deltaZ: number;
  readonly deltaMode: number;

  constructor(type: string, init?: WheelEventInit) {
    super(type, init);
    this.deltaX = init?.deltaX ?? 0;
    this.deltaY = init?.deltaY ?? 0;
    this.deltaZ = init?.deltaZ ?? 0;
    this.deltaMode = init?.deltaMode ?? 0;
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

export class CompositionEvent extends UIEvent {
  readonly data: string;

  constructor(type: string, init?: CompositionEventInit) {
    super(type, init);
    this.data = init?.data ?? "";
  }
}

export class KeyboardEvent extends UIEvent {
  readonly key: string;
  readonly code: string;
  readonly ctrlKey: boolean;
  readonly shiftKey: boolean;
  readonly altKey: boolean;
  readonly metaKey: boolean;
  readonly repeat: boolean;
  readonly location: number;
  readonly isComposing: boolean;

  constructor(type: string, init?: KeyboardEventInit) {
    super(type, init as unknown as UIEventInit);
    this.key = init?.key ?? "";
    this.code = init?.code ?? "";
    this.ctrlKey = Boolean(init?.ctrlKey);
    this.shiftKey = Boolean(init?.shiftKey);
    this.altKey = Boolean(init?.altKey);
    this.metaKey = Boolean(init?.metaKey);
    this.repeat = Boolean(init?.repeat);
    this.location = init?.location ?? 0;
    this.isComposing = Boolean(init?.isComposing);
  }

  initKeyboardEvent(
    type: string,
    bubbles = false,
    cancelable = false,
    _view: EventTarget | null = null,
    key = "",
    location = 0,
    _modifiers = "",
    repeat = false,
    _locale = ""
  ): void {
    if (this.eventPhase !== Event.NONE) {
      return;
    }
    this.initEvent(type, bubbles, cancelable);
    (this as { key: string }).key = key;
    (this as { location: number }).location = location;
    (this as { repeat: boolean }).repeat = repeat;
  }
}

export class EventTargetBase {
  #listeners = new Map<string, ListenerEntry[]>();

  addEventListener(type: string, callback: EventListenerCallback | EventListenerObjectLike | null, options?: boolean | AddEventListenerOptionsLike): void {
    if (!callback) return;

    const listenerCallback: EventListenerCallback = typeof callback === "function"
      ? callback
      : (event) => callback.handleEvent.call(callback, event);
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
    if (!(event instanceof Event)) {
      throw new TypeError("Failed to execute 'dispatchEvent': parameter 1 is not of type 'Event'.");
    }
    if (event.dispatching) {
      throw new ZigDOMException("The event is already being dispatched.", "InvalidStateError", 11);
    }
    if (event.type === "") {
      throw new ZigDOMException("The event has no type.", "InvalidStateError", 11);
    }

    event.setDispatchFlag(true);
    if (!event.target) {
      event.target = this;
    }
    try {
      event.currentTarget = this;
      event.eventPhase = Event.AT_TARGET;
      this.#invoke(event, false);
      this.#invoke(event, true);
      return !event.defaultPrevented;
    } finally {
      event.currentTarget = null;
      event.eventPhase = Event.NONE;
      event.setDispatchFlag(false);
      event.resetAfterDispatch();
    }
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
      const globalScope = this.#resolveGlobalScope();
      const previousEvent = globalScope ? (globalScope as { event?: Event }).event : undefined;
      if (globalScope) {
        (globalScope as { event?: Event }).event = event;
      }

      try {
        listener.callback.call(this, event);
      } catch {
        // testharness expects listener exceptions to be reported, not thrown through dispatchEvent.
      } finally {
        if (globalScope) {
          (globalScope as { event?: Event }).event = previousEvent;
        }
      }

      if (listener.once) {
        this.removeEventListener(event.type, listener.original, { capture: listener.capture });
      }
      if (event.immediatePropagationStopped) {
        break;
      }
    }
  }

  #resolveGlobalScope(): Record<string, unknown> | null {
    const maybeNode = this as unknown as { _window?: Record<string, unknown> };
    if (maybeNode._window && typeof maybeNode._window === "object") {
      return maybeNode._window;
    }

    const maybeWindow = this as unknown as { window?: Record<string, unknown> };
    if (maybeWindow.window && typeof maybeWindow.window === "object") {
      return maybeWindow.window;
    }

    return null;
  }
}

for (const [name, value] of Object.entries({
  NONE: Event.NONE,
  CAPTURING_PHASE: Event.CAPTURING_PHASE,
  AT_TARGET: Event.AT_TARGET,
  BUBBLING_PHASE: Event.BUBBLING_PHASE
})) {
  Object.defineProperty(Event.prototype, name, {
    value,
    writable: false,
    enumerable: true,
    configurable: true
  });
}

import type { Node } from "./Node.ts";
import type { Window } from "./Window.ts";

export type MutationObserverCallback = (records: MutationRecord[], observer: MutationObserver) => void;

export type InternalMutationRecord = {
  type: MutationRecordType;
  target: Node;
  addedNodes: Node[];
  removedNodes: Node[];
  previousSibling: Node | null;
  nextSibling: Node | null;
  attributeName: string | null;
  attributeNamespace: string | null;
  oldValue: string | null;
};

type NormalizedObserverOptions = {
  childList: boolean;
  attributes: boolean;
  characterData: boolean;
  subtree: boolean;
  attributeOldValue: boolean;
  characterDataOldValue: boolean;
  attributeFilter: string[] | null;
};

type Observation = {
  target: Node;
  options: NormalizedObserverOptions;
};

export class MutationObserver {
  readonly #callback: MutationObserverCallback;
  #records: InternalMutationRecord[] = [];
  #observations: Observation[] = [];
  #scheduled = false;
  #window: Window | null = null;

  constructor(callback: MutationObserverCallback) {
    this.#callback = callback;
  }

  observe(target: Node, options?: MutationObserverInit): void {
    const normalized = normalizeOptions(options);
    const existingIndex = this.#observations.findIndex((entry) => entry.target === target);
    if (existingIndex >= 0) {
      this.#observations[existingIndex] = { target, options: normalized };
    } else {
      this.#observations.push({ target, options: normalized });
    }

    this.#window = target._window;
    this.#window.registerMutationObserver(this);
  }

  disconnect(): void {
    this.#records = [];
    this.#observations = [];
    if (this.#window) {
      this.#window.unregisterMutationObserver(this);
      this.#window = null;
    }
  }

  takeRecords(): MutationRecord[] {
    const records = this.#records;
    this.#records = [];
    return records.map(toDomMutationRecord);
  }

  enqueueRecord(record: InternalMutationRecord): void {
    if (this.#observations.length === 0) {
      return;
    }

    for (const observation of this.#observations) {
      if (!matchesObservation(observation, record)) {
        continue;
      }

      this.#records.push(adaptRecordForOptions(record, observation.options));
    }

    if (this.#records.length === 0 || this.#scheduled) {
      return;
    }

    this.#scheduled = true;
    queueMicrotask(() => {
      this.#scheduled = false;
      if (this.#records.length === 0) {
        return;
      }

      const records = this.takeRecords();
      this.#callback(records, this);
    });
  }
}

function normalizeOptions(options: MutationObserverInit | undefined): NormalizedObserverOptions {
  const attributeFilter = options?.attributeFilter?.map((name) => name.toLowerCase()) ?? null;
  const attributes = Boolean(options?.attributes || options?.attributeOldValue || (attributeFilter && attributeFilter.length > 0));
  const characterData = Boolean(options?.characterData || options?.characterDataOldValue);
  const childList = Boolean(options?.childList);

  if (!childList && !attributes && !characterData) {
    throw new TypeError("MutationObserver.observe requires childList, attributes, or characterData");
  }

  return {
    childList,
    attributes,
    characterData,
    subtree: Boolean(options?.subtree),
    attributeOldValue: Boolean(options?.attributeOldValue),
    characterDataOldValue: Boolean(options?.characterDataOldValue),
    attributeFilter: attributeFilter && attributeFilter.length > 0 ? attributeFilter : null
  };
}

function matchesObservation(observation: Observation, record: InternalMutationRecord): boolean {
  const target = record.target;
  const sameTarget = observation.target === target;
  const inSubtree = observation.options.subtree && observation.target.contains(target);

  if (!sameTarget && !inSubtree) {
    return false;
  }

  if (record.type === "attributes") {
    if (!observation.options.attributes) {
      return false;
    }
    if (observation.options.attributeFilter && record.attributeName) {
      return observation.options.attributeFilter.includes(record.attributeName.toLowerCase());
    }
    return true;
  }

  if (record.type === "characterData") {
    return observation.options.characterData;
  }

  if (record.type === "childList") {
    return observation.options.childList;
  }

  return false;
}

function adaptRecordForOptions(record: InternalMutationRecord, options: NormalizedObserverOptions): InternalMutationRecord {
  const oldValue =
    record.type === "attributes"
      ? options.attributeOldValue
        ? record.oldValue
        : null
      : record.type === "characterData"
        ? options.characterDataOldValue
          ? record.oldValue
          : null
        : null;

  return {
    type: record.type,
    target: record.target,
    addedNodes: record.addedNodes,
    removedNodes: record.removedNodes,
    previousSibling: record.previousSibling,
    nextSibling: record.nextSibling,
    attributeName: record.attributeName,
    attributeNamespace: record.attributeNamespace,
    oldValue
  };
}

function toDomMutationRecord(record: InternalMutationRecord): MutationRecord {
  return {
    type: record.type,
    target: record.target as unknown as globalThis.Node,
    addedNodes: record.addedNodes as unknown as NodeList,
    removedNodes: record.removedNodes as unknown as NodeList,
    previousSibling: record.previousSibling as unknown as globalThis.Node | null,
    nextSibling: record.nextSibling as unknown as globalThis.Node | null,
    attributeName: record.attributeName,
    attributeNamespace: record.attributeNamespace,
    oldValue: record.oldValue
  } as unknown as MutationRecord;
}

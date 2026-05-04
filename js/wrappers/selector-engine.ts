import type { Document } from "./Document.ts";
import type { Element } from "./Element.ts";
import { Node } from "./Node.ts";

type Combinator = "descendant" | "child" | "adjacent" | "sibling";
type AttributeOperator = "=" | "~=" | "|=" | "^=" | "$=" | "*=";

type AttributeSelector = {
  namespaceAny: boolean;
  name: string;
  operator: AttributeOperator | null;
  value: string | null;
  caseInsensitive: boolean;
};

type PseudoSelector = {
  name: string;
  argument: string | null;
};

type SimpleSelector =
  | { kind: "universal" }
  | { kind: "tag"; value: string }
  | { kind: "id"; value: string }
  | { kind: "class"; value: string }
  | { kind: "attribute"; value: AttributeSelector }
  | { kind: "pseudo"; value: PseudoSelector };

type CompoundSelector = {
  simples: SimpleSelector[];
};

type ComplexSelector = {
  compounds: CompoundSelector[];
  combinators: Combinator[];
};

export function canUseNativeSelector(selector: string): boolean {
  void selector;
  return false;
}

export function querySelectorAllInDocument(document: Document, selector: string): Element[] {
  const roots = [document.documentElement as unknown as Node];
  return queryFromRoots(roots, selector, null, false);
}

export function querySelectorAllInElement(root: Element, selector: string): Element[] {
  return queryFromRoots([root], selector, root, false);
}

export function querySelectorAllInSubtree(root: Node, selector: string): Element[] {
  return queryFromRoots([root], selector, null, false);
}

export function elementMatchesSelector(element: Element, selector: string): boolean {
  const simpleId = parseSimpleIdSelector(selector);
  if (simpleId != null) {
    return element.id === simpleId;
  }

  const selectors = parseSelectorList(selector);
  if (selectors.length === 0) {
    return false;
  }

  for (const complex of selectors) {
    if (matchesComplex(element, complex, null)) {
      return true;
    }
  }

  return false;
}

function queryFromRoots(roots: Node[], selector: string, scopeRoot: Element | null, includeRoot: boolean): Element[] {
  const simpleId = parseSimpleIdSelector(selector);
  if (simpleId != null) {
    return querySimpleIdFromRoots(roots, simpleId, includeRoot);
  }

  const selectors = parseSelectorList(selector);
  if (selectors.length === 0) {
    return [];
  }

  const matches: Element[] = [];
  const seen = new Set<number>();

  for (const root of roots) {
    const stack: Node[] = [];
    if (includeRoot) {
      stack.push(root);
    } else {
      for (const child of root.childNodes.toArray()) {
        stack.push(child);
      }
    }

    while (stack.length > 0) {
      const current = stack.pop();
      if (!current) {
        continue;
      }

      if (current.nodeType === Node.ELEMENT_NODE) {
        const element = current as unknown as Element;
        if (selectors.some((complex) => matchesComplex(element, complex, scopeRoot))) {
          if (!seen.has(element._handle)) {
            seen.add(element._handle);
            matches.push(element);
          }
        }
      }

      const children = current.childNodes.toArray();
      for (let index = children.length - 1; index >= 0; index -= 1) {
        const child = children[index];
        if (child) {
          stack.push(child);
        }
      }
    }
  }

  return matches;
}

function querySimpleIdFromRoots(roots: Node[], id: string, includeRoot: boolean): Element[] {
  const matches: Element[] = [];
  const seen = new Set<number>();

  for (const root of roots) {
    const stack: Node[] = [];
    if (includeRoot) {
      stack.push(root);
    } else {
      for (const child of root.childNodes.toArray()) {
        stack.push(child);
      }
    }

    while (stack.length > 0) {
      const current = stack.pop();
      if (!current) {
        continue;
      }

      if (current.nodeType === Node.ELEMENT_NODE) {
        const element = current as unknown as Element;
        if (element.id === id && !seen.has(element._handle)) {
          seen.add(element._handle);
          matches.push(element);
        }
      }

      const children = current.childNodes.toArray();
      for (let index = children.length - 1; index >= 0; index -= 1) {
        const child = children[index];
        if (child) {
          stack.push(child);
        }
      }
    }
  }

  return matches;
}

function parseSelectorList(selector: string): ComplexSelector[] {
  const groups: string[] = [];
  let depthBracket = 0;
  let depthParen = 0;
  let start = 0;

  for (let index = 0; index < selector.length; index += 1) {
    const ch = selector[index];
    if (ch === "[") depthBracket += 1;
    if (ch === "]") depthBracket = Math.max(0, depthBracket - 1);
    if (ch === "(") depthParen += 1;
    if (ch === ")") depthParen = Math.max(0, depthParen - 1);

    if (ch === "," && depthBracket === 0 && depthParen === 0) {
      groups.push(selector.slice(start, index));
      start = index + 1;
    }
  }
  groups.push(selector.slice(start));

  return groups
    .map((value) => parseComplexSelector(trimAsciiWhitespace(value)))
    .filter((value): value is ComplexSelector => value !== null);
}

function parseComplexSelector(input: string): ComplexSelector | null {
  if (input.length === 0) {
    return null;
  }

  const compounds: CompoundSelector[] = [];
  const combinators: Combinator[] = [];

  let index = 0;
  let pendingDescendant = false;

  while (index < input.length) {
    let consumedWhitespace = false;
    while (index < input.length && isAsciiWhitespace(input[index] ?? "")) {
      index += 1;
      consumedWhitespace = true;
    }
    if (consumedWhitespace && compounds.length > 0) {
      pendingDescendant = true;
    }

    if (index >= input.length) {
      break;
    }

    const ch = input[index];
    if (ch === ">" || ch === "+" || ch === "~") {
      if (compounds.length === 0) {
        return null;
      }
      combinators.push(ch === ">" ? "child" : ch === "+" ? "adjacent" : "sibling");
      pendingDescendant = false;
      index += 1;
      continue;
    }

    const parsed = parseCompoundSelector(input, index);
    if (!parsed) {
      return null;
    }

    if (pendingDescendant && compounds.length > combinators.length) {
      combinators.push("descendant");
    }

    compounds.push(parsed.compound);
    index = parsed.nextIndex;
    pendingDescendant = false;
  }

  if (compounds.length === 0) {
    return null;
  }

  while (combinators.length < compounds.length - 1) {
    combinators.push("descendant");
  }

  return { compounds, combinators };
}

function parseCompoundSelector(input: string, start: number): { compound: CompoundSelector; nextIndex: number } | null {
  let index = start;
  const simples: SimpleSelector[] = [];

  if (input[index] === "*" && input[index + 1] === "|") {
    const tag = readIdentifier(input, index + 2);
    if (!tag.value) return null;
    simples.push({ kind: "tag", value: tag.value.toLowerCase() });
    index = tag.next;
  } else if (input[index] === "*") {
    simples.push({ kind: "universal" });
    index += 1;
  } else {
    const tag = readIdentifier(input, index);
    if (tag.value) {
      simples.push({ kind: "tag", value: tag.value.toLowerCase() });
      index = tag.next;
    }
  }

  while (index < input.length) {
    const ch = input[index];
    if (!ch || ch === "," || ch === ">" || ch === "+" || ch === "~" || isAsciiWhitespace(ch)) {
      break;
    }

    if (ch === "#") {
      const ident = readIdentifier(input, index + 1);
      if (!ident.value) return null;
      simples.push({ kind: "id", value: ident.value });
      index = ident.next;
      continue;
    }

    if (ch === ".") {
      const ident = readIdentifier(input, index + 1);
      if (!ident.value) return null;
      simples.push({ kind: "class", value: ident.value });
      index = ident.next;
      continue;
    }

    if (ch === "[") {
      const attr = parseAttributeSelector(input, index);
      if (!attr) return null;
      simples.push({ kind: "attribute", value: attr.selector });
      index = attr.next;
      continue;
    }

    if (ch === ":") {
      const pseudo = parsePseudoSelector(input, index);
      if (!pseudo) return null;
      simples.push({ kind: "pseudo", value: pseudo.selector });
      index = pseudo.next;
      continue;
    }

    return null;
  }

  if (simples.length === 0) {
    return null;
  }

  return {
    compound: { simples },
    nextIndex: index
  };
}

function parseAttributeSelector(input: string, start: number): { selector: AttributeSelector; next: number } | null {
  let index = start + 1;
  while (index < input.length && isAsciiWhitespace(input[index] ?? "")) {
    index += 1;
  }

  let namespaceAny = false;
  if (input[index] === "*" && input[index + 1] === "|") {
    namespaceAny = true;
    index += 2;
  }

  let nameToken = readIdentifier(input, index);
  if (!nameToken.value) {
    return null;
  }
  let name = nameToken.value;
  index = nameToken.next;

  if (!namespaceAny && input[index] === "|" && input[index + 1] !== "=") {
    const namespace = name;
    index += 1;
    nameToken = readIdentifier(input, index);
    if (!nameToken.value) {
      return null;
    }
    name = nameToken.value;
    index = nameToken.next;

    if (namespace !== "*") {
      return null;
    }
    namespaceAny = true;
  }

  while (index < input.length && isAsciiWhitespace(input[index] ?? "")) {
    index += 1;
  }

  let operator: AttributeOperator | null = null;
  let value: string | null = null;

  const opCandidate = (input[index] ?? "") + (input[index + 1] ?? "");
  if (["~=", "|=", "^=", "$=", "*="].includes(opCandidate)) {
    operator = opCandidate as AttributeOperator;
    index += 2;
  } else if (input[index] === "=") {
    operator = "=";
    index += 1;
  }

  if (operator) {
    while (index < input.length && isAsciiWhitespace(input[index] ?? "")) {
      index += 1;
    }

    if (input[index] === '"' || input[index] === "'") {
      const quote = input[index];
      index += 1;
      const valueStart = index;
      while (index < input.length && input[index] !== quote) {
        index += 1;
      }
      value = input.slice(valueStart, index);
      if (input[index] === quote) {
        index += 1;
      }
    } else {
      const valueToken = readIdentifier(input, index);
      value = valueToken.value;
      index = valueToken.next;
    }
  }

  while (index < input.length && isAsciiWhitespace(input[index] ?? "")) {
    index += 1;
  }

  let caseInsensitive = false;
  const modifier = (input[index] ?? "").toLowerCase();
  if (modifier === "i" || modifier === "s") {
    caseInsensitive = modifier === "i";
    index += 1;
    while (index < input.length && isAsciiWhitespace(input[index] ?? "")) {
      index += 1;
    }
  }

  if (input[index] !== "]") {
    return null;
  }

  index += 1;
  return {
    selector: { namespaceAny, name, operator, value, caseInsensitive },
    next: index
  };
}

function parsePseudoSelector(input: string, start: number): { selector: PseudoSelector; next: number } | null {
  let index = start + 1;
  const ident = readIdentifier(input, index);
  if (!ident.value) {
    return null;
  }

  const name = ident.value.toLowerCase();
  index = ident.next;

  let argument: string | null = null;
  if (input[index] === "(") {
    index += 1;
    const argumentStart = index;
    let depth = 1;
    while (index < input.length && depth > 0) {
      const ch = input[index];
      if (ch === "(") depth += 1;
      if (ch === ")") depth -= 1;
      index += 1;
    }

    if (depth !== 0) {
      return null;
    }

    argument = input.slice(argumentStart, index - 1).trim();
  }

  return {
    selector: { name, argument },
    next: index
  };
}

function readIdentifier(input: string, start: number): { value: string; next: number } {
  let index = start;
  let value = "";

  while (index < input.length) {
    const ch = input[index] ?? "";
    if (!ch || isAsciiWhitespace(ch) || ",>+~#.:[]()=\"'*|^$".includes(ch)) {
      break;
    }

    if (ch === "\u0000") {
      value += "\uFFFD";
      index += 1;
      continue;
    }

    if (ch !== "\\") {
      value += ch;
      index += 1;
      continue;
    }

    const parsedEscape = parseCssEscape(input, index);
    value += parsedEscape.value;
    index = parsedEscape.next;
  }

  return {
    value,
    next: index
  };
}

function parseCssEscape(input: string, start: number): { value: string; next: number } {
  let index = start + 1;
  if (index >= input.length) {
    return { value: "\uFFFD", next: index };
  }

  const first = input[index] ?? "";
  if (/\r|\n|\f/.test(first)) {
    // A backslash-newline pair is a line continuation and contributes no code point.
    return { value: "", next: index + 1 };
  }

  let hex = "";
  while (index < input.length && hex.length < 6) {
    const ch = input[index] ?? "";
    if (!/[0-9a-fA-F]/.test(ch)) {
      break;
    }
    hex += ch;
    index += 1;
  }

  if (hex.length > 0) {
    if (index < input.length && isAsciiWhitespace(input[index] ?? "")) {
      const ch = input[index] ?? "";
      if (ch === "\r" && input[index + 1] === "\n") {
        index += 2;
      } else {
        index += 1;
      }
    }

    const codePoint = Number.parseInt(hex, 16);
    if (codePoint === 0 || codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
      return { value: "\uFFFD", next: index };
    }

    return { value: String.fromCodePoint(codePoint), next: index };
  }

  const escaped = input[index] ?? "";
  return { value: escaped, next: index + 1 };
}

function parseSimpleIdSelector(selector: string): string | null {
  const input = trimAsciiWhitespace(selector);
  if (!input.startsWith("#") || input.length <= 1) {
    return null;
  }

  let index = 1;
  let value = "";

  while (index < input.length) {
    const ch = input[index] ?? "";
    if (!ch || isAsciiWhitespace(ch) || ",>+~[.:".includes(ch)) {
      return null;
    }

    if (ch === "\\") {
      const escaped = parseCssEscape(input, index);
      value += escaped.value;
      index = escaped.next;
      continue;
    }

    if (ch === "\u0000") {
      value += "\uFFFD";
      index += 1;
      continue;
    }

    value += ch;
    index += 1;
  }

  return value;
}

function matchesComplex(element: Element, selector: ComplexSelector, scopeRoot: Element | null): boolean {
  const { compounds, combinators } = selector;

  const matchAt = (candidate: Element, index: number): boolean => {
    if (!matchesCompound(candidate, compounds[index], scopeRoot)) {
      return false;
    }

    if (index === 0) {
      return true;
    }

    const combinator = combinators[index - 1] ?? "descendant";
    if (combinator === "child") {
      const parent = parentElement(candidate);
      return parent ? matchAt(parent, index - 1) : false;
    }

    if (combinator === "adjacent") {
      const prev = previousElementSibling(candidate);
      return prev ? matchAt(prev, index - 1) : false;
    }

    if (combinator === "sibling") {
      let prev = previousElementSibling(candidate);
      while (prev) {
        if (matchAt(prev, index - 1)) {
          return true;
        }
        prev = previousElementSibling(prev);
      }
      return false;
    }

    let ancestor = parentElement(candidate);
    while (ancestor) {
      if (matchAt(ancestor, index - 1)) {
        return true;
      }
      ancestor = parentElement(ancestor);
    }
    return false;
  };

  return matchAt(element, compounds.length - 1);
}

function matchesCompound(element: Element, compound: CompoundSelector, scopeRoot: Element | null): boolean {
  for (const simple of compound.simples) {
    if (simple.kind === "universal") {
      continue;
    }

    if (simple.kind === "tag") {
      if (element.tagName.toLowerCase() !== simple.value && element.localName.toLowerCase() !== simple.value) {
        return false;
      }
      continue;
    }

    if (simple.kind === "id") {
      if (element.id !== simple.value) {
        return false;
      }
      continue;
    }

    if (simple.kind === "class") {
      if (!element.classList.contains(simple.value)) {
        return false;
      }
      continue;
    }

    if (simple.kind === "attribute") {
      if (!matchesAttributeSelector(element, simple.value)) {
        return false;
      }
      continue;
    }

    if (simple.kind === "pseudo") {
      if (!matchesPseudoSelector(element, simple.value, scopeRoot)) {
        return false;
      }
    }
  }

  return true;
}

function matchesAttributeSelector(element: Element, selector: AttributeSelector): boolean {
  let actual: string | null = null;
  if (selector.namespaceAny) {
    const attributes = (element as unknown as {
      attributes?: Array<{ name: string; localName?: string; value: string }>;
    }).attributes ?? [];
    const match = attributes.find((attribute) => (attribute.localName ?? attribute.name.split(":").pop() ?? attribute.name) === selector.name);
    actual = match?.value ?? null;
  } else {
    const isHtmlElement = (element as unknown as { namespaceURI?: string | null }).namespaceURI === "http://www.w3.org/1999/xhtml";
    const attributeName = isHtmlElement ? selector.name.toLowerCase() : selector.name;
    actual = element.getAttribute(attributeName);
  }

  if (actual == null) {
    return false;
  }

  if (!selector.operator) {
    return true;
  }

  const expected = selector.value ?? "";
  const compare = (left: string, right: string): boolean => {
    if (selector.caseInsensitive) {
      return left.toLowerCase() === right.toLowerCase();
    }
    return left === right;
  };
  const normalize = (value: string): string => selector.caseInsensitive ? value.toLowerCase() : value;

  switch (selector.operator) {
    case "=":
      return compare(actual, expected);
    case "~=":
      return actual.split(/\s+/).filter(Boolean).some((token) => compare(token, expected));
    case "|=":
      return compare(actual, expected) || normalize(actual).startsWith(`${normalize(expected)}-`);
    case "^=":
      return normalize(actual).startsWith(normalize(expected));
    case "$=":
      return normalize(actual).endsWith(normalize(expected));
    case "*=":
      return normalize(actual).includes(normalize(expected));
    default:
      return false;
  }
}

function isAsciiWhitespace(value: string): boolean {
  return value === " " || value === "\t" || value === "\n" || value === "\r" || value === "\f";
}

function trimAsciiWhitespace(value: string): string {
  let start = 0;
  let end = value.length;
  while (start < end && isAsciiWhitespace(value[start] ?? "")) {
    start += 1;
  }
  while (end > start && isAsciiWhitespace(value[end - 1] ?? "")) {
    end -= 1;
  }
  return value.slice(start, end);
}

function matchesPseudoSelector(element: Element, pseudo: PseudoSelector, scopeRoot: Element | null): boolean {
  switch (pseudo.name) {
    case "first-child":
      return previousElementSibling(element) === null;
    case "last-child":
      return nextElementSibling(element) === null;
    case "nth-child":
      return matchesNthChild(element, pseudo.argument ?? "");
    case "not": {
      const selectors = parseSelectorList(pseudo.argument ?? "");
      if (selectors.length === 0) {
        return false;
      }
      return !selectors.some((selector) => matchesComplex(element, selector, scopeRoot));
    }
    case "is":
    case "where": {
      const selectors = parseSelectorList(pseudo.argument ?? "");
      if (selectors.length === 0) {
        return false;
      }
      return selectors.some((selector) => matchesComplex(element, selector, scopeRoot));
    }
    case "scope":
      return scopeRoot ? scopeRoot === element : false;
    default:
      return false;
  }
}

function matchesNthChild(element: Element, argument: string): boolean {
  const normalized = argument.trim().toLowerCase();
  const parent = parentElement(element);
  if (!parent) {
    return false;
  }

  const siblings = parent.children.toArray();
  const index = siblings.indexOf(element) + 1;
  if (index <= 0) {
    return false;
  }

  if (normalized === "odd") {
    return index % 2 === 1;
  }
  if (normalized === "even") {
    return index % 2 === 0;
  }

  const parsed = Number.parseInt(normalized, 10);
  if (Number.isNaN(parsed)) {
    return false;
  }
  return index === parsed;
}

function parentElement(node: Node): Element | null {
  const parent = node.parentNode;
  if (!parent || parent.nodeType !== Node.ELEMENT_NODE) {
    return null;
  }
  return parent as unknown as Element;
}

function previousElementSibling(node: Node): Element | null {
  let cursor = node.previousSibling;
  while (cursor) {
    if (cursor.nodeType === Node.ELEMENT_NODE) {
      return cursor as unknown as Element;
    }
    cursor = cursor.previousSibling;
  }
  return null;
}

function nextElementSibling(node: Node): Element | null {
  let cursor = node.nextSibling;
  while (cursor) {
    if (cursor.nodeType === Node.ELEMENT_NODE) {
      return cursor as unknown as Element;
    }
    cursor = cursor.nextSibling;
  }
  return null;
}

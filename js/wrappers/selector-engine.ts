import type { Document } from "./Document.ts";
import { ZigDOMException } from "./DOMException.ts";
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
  | { kind: "namespace-none"; value: string | null }
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

function asciiLowercase(value: string): string {
  if (!/[A-Z]/.test(value)) {
    return value;
  }
  return value.replace(/[A-Z]/g, (letter) => letter.toLowerCase());
}

export function canUseNativeSelector(selector: string): boolean {
  return selector === "*"
    || /^[A-Za-z][A-Za-z0-9_-]*$/.test(selector)
    || /^\.[A-Za-z_][A-Za-z0-9_-]*$/.test(selector)
    || /^\[[A-Za-z_][A-Za-z0-9_:-]*\]$/.test(selector);
}

export function querySelectorAllInDocument(document: Document, selector: string): Element[] {
  const roots = [document.documentElement as unknown as Node];
  return queryFromRoots(roots, selector, null, true);
}

export function querySelectorAllInElement(root: Element, selector: string): Element[] {
  return queryFromRoots([root], selector, root, false);
}

export function querySelectorAllInSubtree(root: Node, selector: string): Element[] {
  return queryFromRoots([root], selector, null, false);
}

export function elementMatchesSelector(element: Element, selector: string, scopeRoot: Element = element): boolean {
  const simpleId = parseSimpleIdSelector(selector);
  if (simpleId != null) {
    return element.id === simpleId;
  }

  const selectors = parseSelectorList(selector);
  if (selectors.length === 0) {
    return false;
  }

  for (const complex of selectors) {
    if (matchesComplex(element, complex, scopeRoot)) {
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

  const simpleSelector = parseFastSimpleSelector(selector);
  if (simpleSelector) {
    return queryFastSimpleSelectorFromRoots(roots, simpleSelector, includeRoot);
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
      const children = root.childNodes.toArray();
      for (let index = children.length - 1; index >= 0; index -= 1) {
        const child = children[index];
        if (child) {
          stack.push(child);
        }
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

type FastSimpleSelector =
  | { kind: "tag"; value: string }
  | { kind: "class"; value: string }
  | { kind: "attribute"; value: string };

function parseFastSimpleSelector(selector: string): FastSimpleSelector | null {
  if (/^[A-Za-z][A-Za-z0-9_-]*$/.test(selector)) {
    return { kind: "tag", value: selector };
  }
  if (/^\.[A-Za-z_][A-Za-z0-9_-]*$/.test(selector)) {
    return { kind: "class", value: selector.slice(1) };
  }
  const attributeMatch = selector.match(/^\[([A-Za-z_][A-Za-z0-9_:-]*)\]$/);
  if (attributeMatch?.[1]) {
    return { kind: "attribute", value: attributeMatch[1] };
  }
  return null;
}

function queryFastSimpleSelectorFromRoots(roots: Node[], selector: FastSimpleSelector, includeRoot: boolean): Element[] {
  const matches: Element[] = [];
  const seen = new Set<number>();

  for (const root of roots) {
    const stack: Node[] = [];
    if (includeRoot) {
      stack.push(root);
    } else {
      const children = root.childNodes.toArray();
      for (let index = children.length - 1; index >= 0; index -= 1) {
        const child = children[index];
        if (child) {
          stack.push(child);
        }
      }
    }

    while (stack.length > 0) {
      const current = stack.pop();
      if (!current) {
        continue;
      }

      if (current.nodeType === Node.ELEMENT_NODE) {
        const element = current as unknown as Element;
        let matched = false;
        if (selector.kind === "tag") {
          const selectorTagName = isHtmlElement(element)
            ? asciiLowercase(selector.value)
            : selector.value;
          matched = element.localName === selectorTagName;
        } else if (selector.kind === "class") {
          const className = element.getAttribute("class");
          matched = className != null && className.split(/[\t\n\f\r ]+/).includes(selector.value);
        } else {
          const attributeName = isHtmlElement(element)
            ? asciiLowercase(selector.value)
            : selector.value;
          matched = element.getAttribute(attributeName) != null;
        }
        if (matched && !seen.has(element._handle)) {
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

function querySimpleIdFromRoots(roots: Node[], id: string, includeRoot: boolean): Element[] {
  const matches: Element[] = [];
  const seen = new Set<number>();

  for (const root of roots) {
    const stack: Node[] = [];
    if (includeRoot) {
      stack.push(root);
    } else {
      const children = root.childNodes.toArray();
      for (let index = children.length - 1; index >= 0; index -= 1) {
        const child = children[index];
        if (child) {
          stack.push(child);
        }
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

  const selectors = groups.map((value) => {
    const parsed = parseComplexSelector(trimAsciiWhitespace(value));
    if (!parsed) {
      throwSelectorSyntaxError(selector);
    }
    return parsed;
  });

  return selectors;
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
      if (compounds.length === 0 || combinators.length >= compounds.length) {
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

  if (input[index] === "|" && input[index + 1] === "*") {
    simples.push({ kind: "namespace-none", value: null });
    index += 2;
  } else if (input[index] === "|") {
    const tag = readIdentifier(input, index + 1);
    if (!tag.value) return null;
    simples.push({ kind: "namespace-none", value: tag.value.toLowerCase() });
    index = tag.next;
  } else if (input[index] === "*" && input[index + 1] === "*" ) {
    return null;
  } else if (input[index] === "*" && input[index + 1] === "|" && input[index + 2] === "*") {
    simples.push({ kind: "universal" });
    index += 3;
  } else if (input[index] === "*" && input[index + 1] === "|") {
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
      if (!ident.value || /^[0-9]/.test(ident.value)) return null;
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
      value = readCssStringValue(input.slice(valueStart, index));
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

  if (input[index] !== "]" && (index < input.length || !operator)) {
    return null;
  }

  if (input[index] === "]") {
    index += 1;
  }
  return {
    selector: { namespaceAny, name, operator, value, caseInsensitive },
    next: index
  };
}

function parsePseudoSelector(input: string, start: number): { selector: PseudoSelector; next: number } | null {
  let index = start + 1;
  const isPseudoElement = input[index] === ":";
  if (isPseudoElement) {
    index += 1;
  }
  const ident = readIdentifier(input, index);
  if (!ident.value) {
    return null;
  }

  const name = ident.value.toLowerCase();
  index = ident.next;
  const legacyPseudoElementNames = ["after", "before", "first-letter", "first-line"];

  if (isPseudoElement) {
    if (["slotted", ...legacyPseudoElementNames, "selection"].includes(name)) {
      let argument: string | null = null;
      if (input[index] === "(") {
        const parsedArgument = readPseudoArgument(input, index);
        if (!parsedArgument) {
          if (name !== "slotted") {
            return null;
          }
          argument = input.slice(index + 1).trim();
          index = input.length;
        } else {
          argument = parsedArgument.argument;
          index = parsedArgument.next;
        }
      }
      return {
        selector: { name: `::${name}`, argument },
        next: index
      };
    }
    return null;
  }

  if (legacyPseudoElementNames.includes(name)) {
    return {
      selector: { name: `::${name}`, argument: null },
      next: index
    };
  }

  const knownPseudoClassNames = [
    "checked", "disabled", "empty", "enabled", "first-child", "first-of-type", "has", "invalid", "is", "lang",
    "last-child", "last-of-type", "link", "not", "nth-child", "nth-last-child", "nth-last-of-type",
    "nth-of-type", "only-child", "only-of-type", "root", "scope", "target", "visited", "where"
    , "focus", "focus-visible", "focus-within"
  ];
  if (!knownPseudoClassNames.includes(name)) {
    return null;
  }

  let argument: string | null = null;
  if (input[index] === "(") {
    const parsedArgument = readPseudoArgument(input, index);
    if (!parsedArgument) {
      return null;
    }
    argument = parsedArgument.argument;
    index = parsedArgument.next;
  }

  if (["not", "is", "where", "has"].includes(name)) {
    parseSelectorList(argument ?? "");
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
    if (!ch || isAsciiWhitespace(ch) || ",>+~#.:[]()=\"'*|^${}$%<>".includes(ch)) {
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

function readCssStringValue(input: string): string {
  let index = 0;
  let value = "";
  while (index < input.length) {
    if (input[index] === "\\") {
      const parsedEscape = parseCssEscape(input, index);
      value += parsedEscape.value;
      index = parsedEscape.next;
      continue;
    }
    value += input[index] ?? "";
    index += 1;
  }
  return value;
}

function readPseudoArgument(input: string, start: number): { argument: string; next: number } | null {
  let index = start + 1;
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

  return {
    argument: input.slice(argumentStart, index - 1).trim(),
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

    if (simple.kind === "namespace-none") {
      if (element.namespaceURI !== "" && element.namespaceURI != null) {
        return false;
      }
      if (simple.value != null && element.localName.toLowerCase() !== simple.value) {
        return false;
      }
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
    const attributes = Array.from(((element as unknown as {
      attributes?: Array<{ name: string; localName?: string; value: string }>;
    }).attributes ?? []) as Array<{ name: string; localName?: string; value: string }>);
    const selectorName = isHtmlElement(element) ? selector.name.toLowerCase() : selector.name;
    const match = attributes.find((attribute) => {
      const attributeName = attribute.localName ?? attribute.name.split(":").pop() ?? attribute.name;
      return (isHtmlElement(element) ? attributeName.toLowerCase() : attributeName) === selectorName;
    });
    actual = match?.value ?? null;
  } else {
    const attributeName = isHtmlElement(element) ? selector.name.toLowerCase() : selector.name;
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
      if (expected === "") {
        return false;
      }
      return actual.split(/\s+/).filter(Boolean).some((token) => compare(token, expected));
    case "|=":
      if (expected === "") {
        return false;
      }
      return compare(actual, expected) || normalize(actual).startsWith(`${normalize(expected)}-`);
    case "^=":
      if (expected === "") {
        return false;
      }
      return normalize(actual).startsWith(normalize(expected));
    case "$=":
      if (expected === "") {
        return false;
      }
      return normalize(actual).endsWith(normalize(expected));
    case "*=":
      if (expected === "") {
        return false;
      }
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
    case "focus": {
      return element.ownerDocument?.activeElement === element;
    }
    case "focus-visible": {
      // Mirror focus state until keyboard modality tracking exists.
      return element.ownerDocument?.activeElement === element;
    }
    case "focus-within": {
      const activeElement = element.ownerDocument?.activeElement;
      if (!activeElement || activeElement.nodeType !== Node.ELEMENT_NODE) {
        return false;
      }
      return activeElement === element || element.contains(activeElement);
    }
    case "root":
      return element.ownerDocument?.documentElement === element;
    case "first-child":
      return previousElementSibling(element) === null;
    case "last-child":
      return nextElementSibling(element) === null;
    case "only-child":
      return previousElementSibling(element) === null && nextElementSibling(element) === null;
    case "nth-child":
      return matchesNth(element, pseudo.argument ?? "", false, false);
    case "nth-last-child":
      return matchesNth(element, pseudo.argument ?? "", true, false);
    case "nth-of-type":
      return matchesNth(element, pseudo.argument ?? "", false, true);
    case "nth-last-of-type":
      return matchesNth(element, pseudo.argument ?? "", true, true);
    case "first-of-type":
      return typeIndex(element, false).index === 1;
    case "last-of-type": {
      const position = typeIndex(element, true);
      return position.index === 1;
    }
    case "only-of-type":
      return typeIndex(element, false).total === 1;
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
    case "target": {
      if (!element.isConnected) {
        return false;
      }
      const hash = element.ownerDocument?.defaultView?.location.hash ?? "";
      return hash.length > 1 && element.id === decodeURIComponent(hash.slice(1));
    }
    case "link":
      return isLinkElement(element) && element.hasAttribute("href");
    case "visited":
      return false;
    case "lang":
      return matchesLang(element, pseudo.argument ?? "");
    case "enabled":
      return isFormControl(element) && !isDisabledFormControl(element);
    case "disabled":
      return isFormControl(element) && isDisabledFormControl(element);
    case "checked":
      return isCheckable(element) && element.hasAttribute("checked");
    case "empty":
      return element.childNodes.toArray().every((child) => {
        if (child.nodeType === Node.ELEMENT_NODE) {
          return false;
        }
        return child.nodeType !== Node.TEXT_NODE || child.textContent === "";
      });
    case "invalid":
      return isInvalidFormControl(element) || element.children.toArray().some((child) => matchesPseudoSelector(child, pseudo, scopeRoot));
    case "has": {
      const argument = pseudo.argument ?? "";
      if (/^>\s*:scope$/.test(argument)) {
        return scopeRoot != null && element.children.toArray().includes(scopeRoot);
      }
      const selectors = parseSelectorList(argument);
      if (selectors.length === 0) {
        return false;
      }
      const descendants = collectDescendantElements(element);
      return descendants.some((descendant) => selectors.some((selector) => matchesComplex(descendant, selector, scopeRoot)));
    }
    case "::after":
    case "::before":
    case "::first-letter":
    case "::first-line":
    case "::slotted":
    case "::selection":
      return false;
    default:
      throwSelectorSyntaxError(`:${pseudo.name}`);
  }
}

function collectDescendantElements(root: Element): Element[] {
  const out: Element[] = [];
  const visit = (node: Node): void => {
    for (const child of node.childNodes.toArray()) {
      if (child.nodeType === Node.ELEMENT_NODE) {
        out.push(child as unknown as Element);
        visit(child);
      }
    }
  };
  visit(root);
  return out;
}

function isInvalidFormControl(element: Element): boolean {
  const localName = element.localName.toLowerCase();
  if ((localName === "input" || localName === "select" || localName === "textarea") && element.hasAttribute("required")) {
    return (element as unknown as { value?: string }).value === "";
  }
  return false;
}

function matchesNth(element: Element, argument: string, fromEnd: boolean, ofType: boolean): boolean {
  const parent = parentElement(element);
  if (!parent) {
    return false;
  }

  const siblings = ofType
    ? parent.children.toArray().filter((sibling) => sameElementType(sibling, element))
    : parent.children.toArray();
  const index = siblings.indexOf(element) + 1;
  if (index <= 0) {
    return false;
  }

  const parsed = parseNth(argument);
  if (!parsed) {
    throwSelectorSyntaxError(`:nth-child(${argument})`);
  }

  const candidateIndex = fromEnd ? siblings.length - index + 1 : index;
  const { a, b } = parsed;
  if (a === 0) {
    return candidateIndex === b;
  }
  const n = (candidateIndex - b) / a;
  return Number.isInteger(n) && n >= 0;
}

function parseNth(argument: string): { a: number; b: number } | null {
  const normalized = argument.replace(/\s+/g, "").toLowerCase();
  if (normalized === "odd") {
    return { a: 2, b: 1 };
  }
  if (normalized === "even") {
    return { a: 2, b: 0 };
  }

  const integer = normalized.match(/^[+-]?\d+$/);
  if (integer) {
    return { a: 0, b: Number.parseInt(normalized, 10) };
  }

  const linear = normalized.match(/^([+-]?\d*)n([+-]?\d+)?$/);
  if (!linear) {
    return null;
  }

  const rawA = linear[1] ?? "";
  const a = rawA === "" || rawA === "+" ? 1 : rawA === "-" ? -1 : Number.parseInt(rawA, 10);
  const b = linear[2] ? Number.parseInt(linear[2], 10) : 0;
  if (!Number.isFinite(a) || !Number.isFinite(b)) {
    return null;
  }
  return { a, b };
}

function typeIndex(element: Element, fromEnd: boolean): { index: number; total: number } {
  const parent = parentElement(element);
  if (!parent) {
    return { index: 0, total: 0 };
  }

  const siblings = parent.children.toArray().filter((sibling) => sameElementType(sibling, element));
  const index = siblings.indexOf(element);
  return {
    index: fromEnd ? siblings.length - index : index + 1,
    total: siblings.length
  };
}

function sameElementType(left: Element, right: Element): boolean {
  return left.localName.toLowerCase() === right.localName.toLowerCase() && left.namespaceURI === right.namespaceURI;
}

function isLinkElement(element: Element): boolean {
  const localName = element.localName.toLowerCase();
  return localName === "a" || localName === "area";
}

function isFormControl(element: Element): boolean {
  return ["button", "input", "select", "textarea", "option", "optgroup", "fieldset"].includes(element.localName.toLowerCase());
}

function isDisabledFormControl(element: Element): boolean {
  return element.hasAttribute("disabled");
}

function isCheckable(element: Element): boolean {
  const localName = element.localName.toLowerCase();
  if (localName === "option") {
    return true;
  }
  if (localName !== "input") {
    return false;
  }
  const type = (element.getAttribute("type") ?? "text").toLowerCase();
  return type === "checkbox" || type === "radio";
}

function matchesLang(element: Element, argument: string): boolean {
  const expected = argument.trim().replace(/^["']|["']$/g, "").toLowerCase();
  if (expected.length === 0) {
    return false;
  }

  let cursor: Element | null = element;
  while (cursor) {
    const lang = cursor.getAttribute("lang") ?? cursor.getAttribute("xml:lang");
    if (lang) {
      const normalized = lang.toLowerCase();
      return normalized === expected || normalized.startsWith(`${expected}-`);
    }
    cursor = parentElement(cursor);
  }
  return false;
}

function isHtmlElement(element: Element): boolean {
  return (element as unknown as { namespaceURI?: string | null }).namespaceURI === "http://www.w3.org/1999/xhtml";
}

function throwSelectorSyntaxError(selector: string): never {
  throw new ZigDOMException(`'${selector}' is not a valid selector.`, "SyntaxError", 12);
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

import type { Document } from "./Document.ts";
import type { DocumentFragment } from "./DocumentFragment.ts";
import type { Element } from "./Element.ts";
import { Node } from "./Node.ts";

const VOID_ELEMENTS = new Set([
  "area",
  "base",
  "br",
  "col",
  "embed",
  "hr",
  "img",
  "input",
  "link",
  "meta",
  "param",
  "source",
  "track",
  "wbr"
]);

function appendNode(stack: Array<Element | DocumentFragment>, node: Node): void {
  stack[stack.length - 1].appendChild(node);
}

function parseAttributes(element: Element, source: string): void {
  const attrRegex = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
  let match: RegExpExecArray | null = null;
  while ((match = attrRegex.exec(source)) !== null) {
    const name = match[1];
    const value = decodeHtmlEntities(match[2] ?? match[3] ?? match[4] ?? "");
    if (name !== "/") {
      element.setAttribute(name, value);
    }
  }
}

function decodeHtmlEntities(input: string): string {
  if (!input.includes("&")) {
    return input;
  }

  return input.replace(/&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, (_match, entity: string) => {
    if (entity.startsWith("#x") || entity.startsWith("#X")) {
      const codePoint = Number.parseInt(entity.slice(2), 16);
      return Number.isFinite(codePoint) ? String.fromCodePoint(codePoint) : _match;
    }

    if (entity.startsWith("#")) {
      const codePoint = Number.parseInt(entity.slice(1), 10);
      return Number.isFinite(codePoint) ? String.fromCodePoint(codePoint) : _match;
    }

    switch (entity) {
      case "amp":
        return "&";
      case "lt":
        return "<";
      case "gt":
        return ">";
      case "quot":
        return '"';
      case "apos":
        return "'";
      case "nbsp":
        return "\u00A0";
      default:
        return _match;
    }
  });
}

export function parseHtmlInto(parent: Element | DocumentFragment, html: string): void {
  const document = parent.ownerDocument as Document;
  const fragment = document.createDocumentFragment();
  const stack: Array<Element | DocumentFragment> = [fragment];

  const tokenRegex = /<!--[\s\S]*?-->|<[^>]+>|[^<]+/g;
  let tokenMatch: RegExpExecArray | null = null;

  while ((tokenMatch = tokenRegex.exec(html)) !== null) {
    const token = tokenMatch[0];
    if (!token) continue;

    if (token.startsWith("<!--") && token.endsWith("-->")) {
      appendNode(stack, document.createComment(token.slice(4, -3)));
      continue;
    }

    if (token.startsWith("</")) {
      const tagName = token.slice(2, -1).trim().toLowerCase();
      while (stack.length > 1) {
        const current = stack.pop();
        if (current instanceof Node && current.nodeName.toLowerCase() === tagName) {
          break;
        }
      }
      continue;
    }

    if (token.startsWith("<")) {
      const selfClosing = token.endsWith("/>");
      const inner = token.slice(1, selfClosing ? -2 : -1).trim();
      if (!inner) continue;
      const firstSpace = inner.search(/\s/);
      const tagName = (firstSpace === -1 ? inner : inner.slice(0, firstSpace)).toLowerCase();
      const attrSource = firstSpace === -1 ? "" : inner.slice(firstSpace + 1);

      if (tagName === "body" && stack.length === 1 && (parent as Element).localName === "body") {
        if (attrSource) {
          parseAttributes(parent as Element, attrSource);
        }
        stack.push(parent as Element);
        continue;
      }

      const element = document.createElement(tagName);
      if (attrSource) {
        parseAttributes(element, attrSource);
      }
      appendNode(stack, element);

      if (!selfClosing && !VOID_ELEMENTS.has(tagName)) {
        stack.push(element);
      }
      continue;
    }

    const text = decodeHtmlEntities(token);
    if (text.length > 0) {
      appendNode(stack, document.createTextNode(text));
    }
  }

  while (fragment.firstChild) {
    parent.appendChild(fragment.firstChild);
  }
}

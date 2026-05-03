export const PropertySymbol = {
  ownerWindow: Symbol.for("zig-dom.ownerWindow"),
  ownerDocument: Symbol.for("zig-dom.ownerDocument"),
  nodeArray: Symbol.for("zig-dom.nodeArray"),
  classList: Symbol.for("zig-dom.classList")
} as const;

type DomExceptionMapping = {
  name: string;
  code: number;
  defaultMessage: string;
};

const DOM_EXCEPTION_BY_STATUS = new Map<number, DomExceptionMapping>([
  [1, { name: "InvalidStateError", code: 11, defaultMessage: "The object is in an invalid state." }],
  [2, { name: "HierarchyRequestError", code: 3, defaultMessage: "The operation would yield an incorrect node tree." }],
  [3, { name: "NotFoundError", code: 8, defaultMessage: "The object can not be found here." }],
  [4, { name: "QuotaExceededError", code: 22, defaultMessage: "The operation ran out of memory." }],
  [5, { name: "SyntaxError", code: 12, defaultMessage: "The provided input is invalid." }],
  [6, { name: "InvalidStateError", code: 11, defaultMessage: "A native internal error occurred." }]
]);

export class ZigDOMException extends Error {
  readonly code: number;

  constructor(message: string, name: string, code = 0) {
    super(message);
    this.name = name;
    this.code = code;
  }
}

export function domExceptionForStatus(status: number, operation: string, details?: string): ZigDOMException {
  const mapping = DOM_EXCEPTION_BY_STATUS.get(status);
  if (!mapping) {
    return new ZigDOMException(`${operation} failed${details ? `: ${details}` : ""}`, "InvalidStateError", 11);
  }

  const message = details ? `${mapping.defaultMessage} ${details}` : `${mapping.defaultMessage} (${operation})`;
  return new ZigDOMException(message, mapping.name, mapping.code);
}

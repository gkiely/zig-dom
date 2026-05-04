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
  static readonly INDEX_SIZE_ERR = 1;
  static readonly DOMSTRING_SIZE_ERR = 2;
  static readonly HIERARCHY_REQUEST_ERR = 3;
  static readonly WRONG_DOCUMENT_ERR = 4;
  static readonly INVALID_CHARACTER_ERR = 5;
  static readonly NO_DATA_ALLOWED_ERR = 6;
  static readonly NO_MODIFICATION_ALLOWED_ERR = 7;
  static readonly NOT_FOUND_ERR = 8;
  static readonly NOT_SUPPORTED_ERR = 9;
  static readonly INUSE_ATTRIBUTE_ERR = 10;
  static readonly INVALID_STATE_ERR = 11;
  static readonly SYNTAX_ERR = 12;
  static readonly INVALID_MODIFICATION_ERR = 13;
  static readonly NAMESPACE_ERR = 14;
  static readonly INVALID_ACCESS_ERR = 15;
  static readonly VALIDATION_ERR = 16;
  static readonly TYPE_MISMATCH_ERR = 17;
  static readonly SECURITY_ERR = 18;
  static readonly NETWORK_ERR = 19;
  static readonly ABORT_ERR = 20;
  static readonly URL_MISMATCH_ERR = 21;
  static readonly QUOTA_EXCEEDED_ERR = 22;
  static readonly TIMEOUT_ERR = 23;
  static readonly INVALID_NODE_TYPE_ERR = 24;
  static readonly DATA_CLONE_ERR = 25;

  readonly code: number;

  constructor(message: string, name: string, code = 0) {
    super(message);
    this.name = name;
    this.code = code;
  }
}

for (const [name, value] of Object.entries({
  INDEX_SIZE_ERR: 1,
  DOMSTRING_SIZE_ERR: 2,
  HIERARCHY_REQUEST_ERR: 3,
  WRONG_DOCUMENT_ERR: 4,
  INVALID_CHARACTER_ERR: 5,
  NO_DATA_ALLOWED_ERR: 6,
  NO_MODIFICATION_ALLOWED_ERR: 7,
  NOT_FOUND_ERR: 8,
  NOT_SUPPORTED_ERR: 9,
  INUSE_ATTRIBUTE_ERR: 10,
  INVALID_STATE_ERR: 11,
  SYNTAX_ERR: 12,
  INVALID_MODIFICATION_ERR: 13,
  NAMESPACE_ERR: 14,
  INVALID_ACCESS_ERR: 15,
  VALIDATION_ERR: 16,
  TYPE_MISMATCH_ERR: 17,
  SECURITY_ERR: 18,
  NETWORK_ERR: 19,
  ABORT_ERR: 20,
  URL_MISMATCH_ERR: 21,
  QUOTA_EXCEEDED_ERR: 22,
  TIMEOUT_ERR: 23,
  INVALID_NODE_TYPE_ERR: 24,
  DATA_CLONE_ERR: 25
})) {
  Object.defineProperty(ZigDOMException.prototype, name, {
    value,
    configurable: true
  });
}

export function domExceptionForStatus(status: number, operation: string, details?: string): ZigDOMException {
  const mapping = DOM_EXCEPTION_BY_STATUS.get(status);
  if (!mapping) {
    return new ZigDOMException(`${operation} failed${details ? `: ${details}` : ""}`, "InvalidStateError", 11);
  }

  const message = details ? `${mapping.defaultMessage} ${details}` : `${mapping.defaultMessage} (${operation})`;
  return new ZigDOMException(message, mapping.name, mapping.code);
}

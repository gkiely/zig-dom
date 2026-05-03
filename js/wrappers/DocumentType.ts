import { Node } from "./Node.ts";

export class DocumentType extends Node {
  #name: string;
  #publicId: string;
  #systemId: string;

  constructor(window: Node["_window"], handle: number, name = "html", publicId = "", systemId = "") {
    super(window, handle, Node.DOCUMENT_TYPE_NODE);
    this.#name = name;
    this.#publicId = publicId;
    this.#systemId = systemId;
  }

  setDefinition(name: string, publicId = "", systemId = ""): void {
    this.#name = name;
    this.#publicId = publicId;
    this.#systemId = systemId;
  }

  override get nodeName(): string {
    return this.#name;
  }

  get name(): string {
    return this.#name;
  }

  get publicId(): string {
    return this.#publicId;
  }

  get systemId(): string {
    return this.#systemId;
  }

  override cloneNode(): DocumentType {
    const ownerDocument = this.ownerDocument;
    if (!ownerDocument) {
      return new DocumentType(this._window, 0, this.#name, this.#publicId, this.#systemId);
    }

    const implementation = ownerDocument.implementation as {
      createDocumentType: (qualifiedName: string, publicId?: string, systemId?: string) => DocumentType;
    };

    return implementation.createDocumentType(this.#name, this.#publicId, this.#systemId);
  }
}

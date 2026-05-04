import { dlopen, ptr, suffix, toArrayBuffer, type Pointer } from "bun:ffi";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { domExceptionForStatus } from "./wrappers/DOMException.ts";

export const enum NativeStatus {
  Ok = 0,
  InvalidHandle = 1,
  HierarchyRequest = 2,
  NotFound = 3,
  OutOfMemory = 4,
  InvalidArgument = 5,
  InternalError = 6
}

function statusName(status: number): string {
  switch (status) {
    case NativeStatus.Ok:
      return "ok";
    case NativeStatus.InvalidHandle:
      return "invalid_handle";
    case NativeStatus.HierarchyRequest:
      return "hierarchy_request";
    case NativeStatus.NotFound:
      return "not_found";
    case NativeStatus.OutOfMemory:
      return "out_of_memory";
    case NativeStatus.InvalidArgument:
      return "invalid_argument";
    case NativeStatus.InternalError:
      return "internal_error";
    default:
      return `unknown_${status}`;
  }
}

function assertStatus(status: number, operation: string): void {
  if (status !== NativeStatus.Ok) {
    throw domExceptionForStatus(status, operation, `${statusName(status)} (${status})`);
  }
}

function resolveLibraryPath(): string {
  const platform = `${process.platform}-${process.arch}`;
  const libraryNames = process.platform === "win32" ? ["zig_dom.dll", "libzig_dom.dll"] : [`libzig_dom.${suffix}`];
  const packageName = `zig-dom-${platform}`;
  const candidates = [
    ...libraryNames.map((name) => join(import.meta.dir, "native", platform, name)),
    ...libraryNames.map((name) => join(import.meta.dir, "native", name)),
    ...libraryNames.map((name) => join(import.meta.dir, "..", "dist", "native", platform, name)),
    ...libraryNames.map((name) => join(import.meta.dir, "..", "dist", "native", name)),
    ...libraryNames.map((name) => join(import.meta.dir, "..", "zig-out", "lib", name)),
    ...libraryNames.map((name) => join(process.cwd(), "dist", "native", platform, name)),
    ...libraryNames.map((name) => join(process.cwd(), "dist", "native", name)),
    ...libraryNames.map((name) => join(process.cwd(), "zig-out", "lib", name)),
    ...libraryNames.map((name) => join(process.cwd(), "node_modules", packageName, "native", platform, name)),
    ...libraryNames.map((name) => join(import.meta.dir, "..", "node_modules", packageName, "native", platform, name))
  ];

  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  throw new Error(`Unable to locate native library for ${platform}. Install ${packageName}, or rebuild zig-dom for this platform.`);
}

const libraryPath = resolveLibraryPath();

const nativeLibrary = dlopen(libraryPath, {
  zig_dom_version: { returns: "cstring", args: [] },
  zig_dom_can_return_structs: { returns: "u32", args: [] },
  zig_dom_echo_utf8: { returns: "u32", args: ["ptr", "usize", "ptr", "ptr"] },
  zig_dom_create_window: { returns: "u32", args: ["ptr"] },
  zig_dom_destroy_window: { returns: "void", args: ["u64"] },
  zig_dom_window_document: { returns: "u32", args: ["u64", "ptr"] },
  zig_dom_window_document_element: { returns: "u32", args: ["u64", "ptr"] },
  zig_dom_window_head: { returns: "u32", args: ["u64", "ptr"] },
  zig_dom_window_body: { returns: "u32", args: ["u64", "ptr"] },
  zig_dom_node_kind: { returns: "u32", args: ["u64"] },
  zig_dom_node_type: { returns: "u32", args: ["u64"] },
  zig_dom_node_owner_document: { returns: "u32", args: ["u64", "ptr"] },
  zig_dom_node_parent: { returns: "u64", args: ["u64"] },
  zig_dom_node_first_child: { returns: "u64", args: ["u64"] },
  zig_dom_node_last_child: { returns: "u64", args: ["u64"] },
  zig_dom_node_next_sibling: { returns: "u64", args: ["u64"] },
  zig_dom_node_previous_sibling: { returns: "u64", args: ["u64"] },
  zig_dom_node_child_handles: { returns: "u32", args: ["u64", "ptr", "ptr"] },
  zig_dom_node_contains: { returns: "u32", args: ["u64", "u64"] },
  zig_dom_node_compare_document_position: { returns: "u32", args: ["u64", "u64"] },
  zig_dom_node_name: { returns: "u32", args: ["u64", "ptr", "ptr"] },
  zig_dom_node_append_child: { returns: "u32", args: ["u64", "u64"] },
  zig_dom_node_append_fragment: { returns: "u32", args: ["u64", "u64"] },
  zig_dom_node_replace_children: { returns: "u32", args: ["u64", "ptr", "usize"] },
  zig_dom_node_set_inner_html: { returns: "u32", args: ["u64", "ptr", "usize"] },
  zig_dom_window_append_child: { returns: "u32", args: ["u64", "u64", "u64"] },
  zig_dom_node_insert_before: { returns: "u32", args: ["u64", "u64", "u64"] },
  zig_dom_node_remove_child: { returns: "u32", args: ["u64", "u64"] },
  zig_dom_node_replace_child: { returns: "u32", args: ["u64", "u64", "u64"] },
  zig_dom_document_create_element: { returns: "u32", args: ["u64", "ptr", "usize", "ptr"] },
  zig_dom_document_create_div_element: { returns: "u64", args: ["u64"] },
  zig_dom_document_create_text_node: { returns: "u32", args: ["u64", "ptr", "usize", "ptr"] },
  zig_dom_document_create_text_node_direct: { returns: "u64", args: ["u64", "ptr", "usize"] },
  zig_dom_document_create_comment: { returns: "u32", args: ["u64", "ptr", "usize", "ptr"] },
  zig_dom_document_create_document_fragment: { returns: "u32", args: ["u64", "ptr"] },
  zig_dom_element_get_attribute: { returns: "u32", args: ["u64", "ptr", "usize", "ptr", "ptr", "ptr"] },
  zig_dom_element_get_attribute_ref: { returns: "u32", args: ["u64", "ptr", "usize", "ptr", "ptr", "ptr"] },
  zig_dom_element_set_attribute: { returns: "u32", args: ["u64", "ptr", "usize", "ptr", "usize"] },
  zig_dom_element_remove_attribute: { returns: "u32", args: ["u64", "ptr", "usize"] },
  zig_dom_element_has_attribute: { returns: "u32", args: ["u64", "ptr", "usize"] },
  zig_dom_element_attributes_json: { returns: "u32", args: ["u64", "ptr", "ptr"] },
  zig_dom_node_text_content: { returns: "u32", args: ["u64", "ptr", "ptr"] },
  zig_dom_node_set_text_content: { returns: "u32", args: ["u64", "ptr", "usize"] },
  zig_dom_character_data_set_data_direct: { returns: "void", args: ["u64", "ptr", "usize"] },
  zig_dom_node_outer_html: { returns: "u32", args: ["u64", "ptr", "ptr"] },
  zig_dom_document_get_element_by_id: { returns: "u32", args: ["u64", "ptr", "usize", "ptr"] },
  zig_dom_document_query_selector: { returns: "u32", args: ["u64", "ptr", "usize", "ptr"] },
  zig_dom_document_query_selector_all: { returns: "u32", args: ["u64", "ptr", "usize", "ptr", "ptr"] },
  zig_dom_node_query_selector: { returns: "u32", args: ["u64", "ptr", "usize", "ptr"] },
  zig_dom_node_query_selector_all: { returns: "u32", args: ["u64", "ptr", "usize", "ptr", "ptr"] },
  zig_dom_document_reset: { returns: "u32", args: ["u64"] },
  zig_dom_free_string: { returns: "void", args: ["ptr", "usize"] },
  zig_dom_free_handle_array: { returns: "void", args: ["ptr", "usize"] },
  zig_dom_retain_handle: { returns: "void", args: ["u64"] },
  zig_dom_release_handle: { returns: "void", args: ["u64"] },
  zig_dom_debug_reset_counters: { returns: "void", args: [] },
  zig_dom_debug_get_counters: { returns: "u32", args: ["ptr", "ptr", "ptr", "ptr"] }
});

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { ignoreBOM: true });
const EMPTY_BYTES = new Uint8Array(1);
const ENCODE_CACHE_LIMIT = 256;
const ENCODE_CACHE_MAX_INPUT_LENGTH = 64;
const encodeCache = new Map<string, Uint8Array>();
const HANDLE_OUT_SCRATCH = new BigUint64Array(1);
let HANDLE_ARRAY_SCRATCH = new BigUint64Array(0);
const GET_ATTR_OUT_PTR = new BigUint64Array(1);
const GET_ATTR_OUT_LEN = new BigUint64Array(1);
const GET_ATTR_OUT_EXISTS = new Uint8Array(1);

function encode(input: string, shouldCache = true): Uint8Array {
  if (input.length === 0) {
    return EMPTY_BYTES;
  }

  if (!shouldCache) {
    return encoder.encode(input);
  }

  const cached = encodeCache.get(input);
  if (cached) {
    return cached;
  }

  const bytes = encoder.encode(input);
  if (input.length <= ENCODE_CACHE_MAX_INPUT_LENGTH) {
    if (encodeCache.size >= ENCODE_CACHE_LIMIT) {
      encodeCache.clear();
    }
    encodeCache.set(input, bytes);
  }

  return bytes;
}

function encodedLength(input: string, bytes: Uint8Array): number {
  return input.length === 0 ? 0 : bytes.length;
}

function readStringFromOutParams(addressRef: BigUint64Array, lengthRef: BigUint64Array): string {
  const address = Number(addressRef[0]);
  const length = Number(lengthRef[0]);
  if (address === 0 || length === 0) {
    return "";
  }

  const view = new Uint8Array(toArrayBuffer(address as unknown as Pointer, 0, length));
  const copy = Uint8Array.from(view);
  nativeLibrary.symbols.zig_dom_free_string(address as unknown as Pointer, length);
  return decoder.decode(copy);
}

function createHandleOut(): BigUint64Array {
  HANDLE_OUT_SCRATCH[0] = 0n;
  return HANDLE_OUT_SCRATCH;
}

function readHandle(out: BigUint64Array): number {
  return Number(out[0]);
}

function writeHandleArray(handles: number[]): BigUint64Array {
  if (HANDLE_ARRAY_SCRATCH.length < handles.length) {
    HANDLE_ARRAY_SCRATCH = new BigUint64Array(handles.length);
  }
  for (let index = 0; index < handles.length; index += 1) {
    HANDLE_ARRAY_SCRATCH[index] = BigInt(handles[index] ?? 0);
  }
  return HANDLE_ARRAY_SCRATCH.subarray(0, handles.length);
}

function writeNodeHandleArray(nodes: ArrayLike<{ _handle: number }>): BigUint64Array {
  if (HANDLE_ARRAY_SCRATCH.length < nodes.length) {
    HANDLE_ARRAY_SCRATCH = new BigUint64Array(nodes.length);
  }
  for (let index = 0; index < nodes.length; index += 1) {
    HANDLE_ARRAY_SCRATCH[index] = BigInt(nodes[index]?._handle ?? 0);
  }
  return HANDLE_ARRAY_SCRATCH;
}

function readHandleArrayFromOutParams(addressRef: BigUint64Array, lengthRef: BigUint64Array): number[] {
  const address = Number(addressRef[0]);
  const length = Number(lengthRef[0]);
  if (address === 0 || length === 0) {
    return [];
  }

  const bytes = new Uint8Array(toArrayBuffer(address as unknown as Pointer, 0, length * 8));
  const copy = bytes.slice().buffer;
  nativeLibrary.symbols.zig_dom_free_handle_array(address as unknown as Pointer, length);
  const values = new BigUint64Array(copy);
  return Array.from(values, (value) => Number(value));
}

export const native = {
  libraryPath,
  version(): string {
    return String(nativeLibrary.symbols.zig_dom_version());
  },
  canReturnStructs(): boolean {
    return nativeLibrary.symbols.zig_dom_can_return_structs() === 1;
  },
  echoUtf8(input: string): string {
    const bytes = encode(input);
    const outPtr = new BigUint64Array(1);
    const outLen = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_echo_utf8(ptr(bytes), encodedLength(input, bytes), ptr(outPtr), ptr(outLen));
    assertStatus(status, "zig_dom_echo_utf8");
    return readStringFromOutParams(outPtr, outLen);
  },
  createWindow(): number {
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_create_window(ptr(out));
    assertStatus(status, "zig_dom_create_window");
    return readHandle(out);
  },
  destroyWindow(window: number): void {
    nativeLibrary.symbols.zig_dom_destroy_window(window);
  },
  windowDocument(window: number): number {
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_window_document(window, ptr(out));
    assertStatus(status, "zig_dom_window_document");
    return readHandle(out);
  },
  windowDocumentElement(window: number): number {
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_window_document_element(window, ptr(out));
    assertStatus(status, "zig_dom_window_document_element");
    return readHandle(out);
  },
  windowHead(window: number): number {
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_window_head(window, ptr(out));
    assertStatus(status, "zig_dom_window_head");
    return readHandle(out);
  },
  windowBody(window: number): number {
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_window_body(window, ptr(out));
    assertStatus(status, "zig_dom_window_body");
    return readHandle(out);
  },
  nodeKind(handle: number): number {
    return nativeLibrary.symbols.zig_dom_node_kind(handle);
  },
  nodeType(handle: number): number {
    return nativeLibrary.symbols.zig_dom_node_type(handle);
  },
  nodeOwnerDocument(handle: number): number {
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_node_owner_document(handle, ptr(out));
    assertStatus(status, "zig_dom_node_owner_document");
    return readHandle(out);
  },
  nodeParent(handle: number): number {
    return Number(nativeLibrary.symbols.zig_dom_node_parent(handle));
  },
  nodeFirstChild(handle: number): number {
    return Number(nativeLibrary.symbols.zig_dom_node_first_child(handle));
  },
  nodeLastChild(handle: number): number {
    return Number(nativeLibrary.symbols.zig_dom_node_last_child(handle));
  },
  nodeNextSibling(handle: number): number {
    return Number(nativeLibrary.symbols.zig_dom_node_next_sibling(handle));
  },
  nodePreviousSibling(handle: number): number {
    return Number(nativeLibrary.symbols.zig_dom_node_previous_sibling(handle));
  },
  nodeChildHandles(handle: number): number[] {
    const outPtr = new BigUint64Array(1);
    const outLen = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_node_child_handles(handle, ptr(outPtr), ptr(outLen));
    assertStatus(status, "zig_dom_node_child_handles");
    return readHandleArrayFromOutParams(outPtr, outLen);
  },
  nodeContains(ancestorHandle: number, nodeHandle: number): boolean {
    return nativeLibrary.symbols.zig_dom_node_contains(ancestorHandle, nodeHandle) === 1;
  },
  nodeCompareDocumentPosition(leftHandle: number, rightHandle: number): number {
    return nativeLibrary.symbols.zig_dom_node_compare_document_position(leftHandle, rightHandle);
  },
  nodeName(handle: number): string {
    const outPtr = new BigUint64Array(1);
    const outLen = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_node_name(handle, ptr(outPtr), ptr(outLen));
    assertStatus(status, "zig_dom_node_name");
    return readStringFromOutParams(outPtr, outLen);
  },
  appendChild(parent: number, child: number): void {
    const status = nativeLibrary.symbols.zig_dom_node_append_child(parent, child);
    assertStatus(status, "zig_dom_node_append_child");
  },
  appendFragment(parent: number, fragment: number): void {
    const status = nativeLibrary.symbols.zig_dom_node_append_fragment(parent, fragment);
    assertStatus(status, "zig_dom_node_append_fragment");
  },
  replaceChildren(parent: number, children: number[]): void {
    const handles = writeHandleArray(children);
    const status = nativeLibrary.symbols.zig_dom_node_replace_children(
      parent,
      ptr(handles.length === 0 ? HANDLE_OUT_SCRATCH : handles),
      handles.length
    );
    assertStatus(status, "zig_dom_node_replace_children");
  },
  replaceChildrenFromNodes(parent: number, children: ArrayLike<{ _handle: number }>): void {
    const handles = writeNodeHandleArray(children);
    const status = nativeLibrary.symbols.zig_dom_node_replace_children(
      parent,
      ptr(children.length === 0 ? HANDLE_OUT_SCRATCH : handles),
      children.length
    );
    assertStatus(status, "zig_dom_node_replace_children");
  },
  setInnerHTML(parent: number, html: string): void {
    const bytes = encode(html, false);
    const status = nativeLibrary.symbols.zig_dom_node_set_inner_html(parent, ptr(bytes), encodedLength(html, bytes));
    assertStatus(status, "zig_dom_node_set_inner_html");
  },
  appendChildInWindow(window: number, parent: number, child: number): void {
    const status = nativeLibrary.symbols.zig_dom_window_append_child(window, parent, child);
    if (status !== NativeStatus.Ok) {
      throw domExceptionForStatus(status, "zig_dom_window_append_child", `${statusName(status)} (${status})`);
    }
  },
  insertBefore(parent: number, child: number, referenceChild: number): void {
    const status = nativeLibrary.symbols.zig_dom_node_insert_before(parent, child, referenceChild);
    assertStatus(status, "zig_dom_node_insert_before");
  },
  removeChild(parent: number, child: number): void {
    const status = nativeLibrary.symbols.zig_dom_node_remove_child(parent, child);
    assertStatus(status, "zig_dom_node_remove_child");
  },
  replaceChild(parent: number, newChild: number, oldChild: number): void {
    const status = nativeLibrary.symbols.zig_dom_node_replace_child(parent, newChild, oldChild);
    assertStatus(status, "zig_dom_node_replace_child");
  },
  createElement(documentHandle: number, tagName: string): number {
    const tag = encode(tagName);
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_document_create_element(documentHandle, ptr(tag), encodedLength(tagName, tag), ptr(out));
    assertStatus(status, "zig_dom_document_create_element");
    return readHandle(out);
  },
  createDivElement(documentHandle: number): number {
    const handle = Number(nativeLibrary.symbols.zig_dom_document_create_div_element(documentHandle));
    if (handle === 0) {
      throw domExceptionForStatus(NativeStatus.OutOfMemory, "zig_dom_document_create_div_element", `${statusName(NativeStatus.OutOfMemory)} (${NativeStatus.OutOfMemory})`);
    }
    return handle;
  },
  createTextNode(documentHandle: number, text: string): number {
    const data = encode(text);
    const handle = Number(nativeLibrary.symbols.zig_dom_document_create_text_node_direct(documentHandle, ptr(data), encodedLength(text, data)));
    if (handle === 0) {
      throw domExceptionForStatus(NativeStatus.OutOfMemory, "zig_dom_document_create_text_node_direct", `${statusName(NativeStatus.OutOfMemory)} (${NativeStatus.OutOfMemory})`);
    }
    return handle;
  },
  createComment(documentHandle: number, text: string): number {
    const data = encode(text);
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_document_create_comment(documentHandle, ptr(data), encodedLength(text, data), ptr(out));
    assertStatus(status, "zig_dom_document_create_comment");
    return readHandle(out);
  },
  createDocumentFragment(documentHandle: number): number {
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_document_create_document_fragment(documentHandle, ptr(out));
    assertStatus(status, "zig_dom_document_create_document_fragment");
    return readHandle(out);
  },
  getAttribute(elementHandle: number, name: string): string | null {
    const key = encode(name);
    GET_ATTR_OUT_PTR[0] = 0n;
    GET_ATTR_OUT_LEN[0] = 0n;
    GET_ATTR_OUT_EXISTS[0] = 0;
    const status = nativeLibrary.symbols.zig_dom_element_get_attribute_ref(
      elementHandle,
      ptr(key),
      encodedLength(name, key),
      ptr(GET_ATTR_OUT_PTR),
      ptr(GET_ATTR_OUT_LEN),
      ptr(GET_ATTR_OUT_EXISTS)
    );
    assertStatus(status, "zig_dom_element_get_attribute_ref");
    if (GET_ATTR_OUT_EXISTS[0] === 0) return null;

    const address = Number(GET_ATTR_OUT_PTR[0]);
    const length = Number(GET_ATTR_OUT_LEN[0]);
    if (address === 0 || length === 0) {
      return "";
    }

    const view = new Uint8Array(toArrayBuffer(address as unknown as Pointer, 0, length));
    return decoder.decode(view);
  },
  setAttribute(elementHandle: number, name: string, value: string): void {
    const key = encode(name);
    const val = encode(value, false);
    const status = nativeLibrary.symbols.zig_dom_element_set_attribute(elementHandle, ptr(key), encodedLength(name, key), ptr(val), encodedLength(value, val));
    assertStatus(status, "zig_dom_element_set_attribute");
  },
  removeAttribute(elementHandle: number, name: string): void {
    const key = encode(name);
    const status = nativeLibrary.symbols.zig_dom_element_remove_attribute(elementHandle, ptr(key), encodedLength(name, key));
    assertStatus(status, "zig_dom_element_remove_attribute");
  },
  hasAttribute(elementHandle: number, name: string): boolean {
    const key = encode(name);
    return nativeLibrary.symbols.zig_dom_element_has_attribute(elementHandle, ptr(key), encodedLength(name, key)) === 1;
  },
  elementAttributes(elementHandle: number): Array<{ name: string; value: string }> {
    const outPtr = new BigUint64Array(1);
    const outLen = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_element_attributes_json(elementHandle, ptr(outPtr), ptr(outLen));
    assertStatus(status, "zig_dom_element_attributes_json");
    const json = readStringFromOutParams(outPtr, outLen);
    if (json.length === 0) {
      return [];
    }
    const parsed = JSON.parse(json) as Array<{ name?: unknown; value?: unknown }>;
    return parsed
      .filter((entry) => typeof entry?.name === "string" && typeof entry?.value === "string")
      .map((entry) => ({ name: String(entry.name), value: String(entry.value) }));
  },
  nodeTextContent(handle: number): string {
    const outPtr = new BigUint64Array(1);
    const outLen = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_node_text_content(handle, ptr(outPtr), ptr(outLen));
    assertStatus(status, "zig_dom_node_text_content");
    return readStringFromOutParams(outPtr, outLen);
  },
  setNodeTextContent(handle: number, value: string): void {
    const data = encode(value);
    const status = nativeLibrary.symbols.zig_dom_node_set_text_content(handle, ptr(data), encodedLength(value, data));
    assertStatus(status, "zig_dom_node_set_text_content");
  },
  setCharacterDataDirect(handle: number, value: string): void {
    const data = encode(value);
    nativeLibrary.symbols.zig_dom_character_data_set_data_direct(handle, ptr(data), encodedLength(value, data));
  },
  nodeOuterHtml(handle: number): string {
    const outPtr = new BigUint64Array(1);
    const outLen = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_node_outer_html(handle, ptr(outPtr), ptr(outLen));
    assertStatus(status, "zig_dom_node_outer_html");
    return readStringFromOutParams(outPtr, outLen);
  },
  documentGetElementById(documentHandle: number, id: string): number {
    const data = encode(id);
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_document_get_element_by_id(documentHandle, ptr(data), encodedLength(id, data), ptr(out));
    assertStatus(status, "zig_dom_document_get_element_by_id");
    return readHandle(out);
  },
  documentQuerySelector(documentHandle: number, selector: string): number {
    const data = encode(selector);
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_document_query_selector(documentHandle, ptr(data), encodedLength(selector, data), ptr(out));
    assertStatus(status, "zig_dom_document_query_selector");
    return readHandle(out);
  },
  documentQuerySelectorAll(documentHandle: number, selector: string): number[] {
    const data = encode(selector);
    const outPtr = new BigUint64Array(1);
    const outLen = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_document_query_selector_all(documentHandle, ptr(data), encodedLength(selector, data), ptr(outPtr), ptr(outLen));
    assertStatus(status, "zig_dom_document_query_selector_all");
    return readHandleArrayFromOutParams(outPtr, outLen);
  },
  nodeQuerySelectorAll(rootHandle: number, selector: string): number[] {
    const data = encode(selector);
    const outPtr = new BigUint64Array(1);
    const outLen = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_node_query_selector_all(rootHandle, ptr(data), encodedLength(selector, data), ptr(outPtr), ptr(outLen));
    assertStatus(status, "zig_dom_node_query_selector_all");
    return readHandleArrayFromOutParams(outPtr, outLen);
  },
  nodeQuerySelector(rootHandle: number, selector: string): number {
    const data = encode(selector);
    const out = createHandleOut();
    const status = nativeLibrary.symbols.zig_dom_node_query_selector(rootHandle, ptr(data), encodedLength(selector, data), ptr(out));
    assertStatus(status, "zig_dom_node_query_selector");
    return readHandle(out);
  },
  documentReset(documentHandle: number): void {
    const status = nativeLibrary.symbols.zig_dom_document_reset(documentHandle);
    assertStatus(status, "zig_dom_document_reset");
  },
  retainHandle(handle: number): void {
    nativeLibrary.symbols.zig_dom_retain_handle(handle);
  },
  releaseHandle(handle: number): void {
    nativeLibrary.symbols.zig_dom_release_handle(handle);
  },
  debugResetCounters(): void {
    nativeLibrary.symbols.zig_dom_debug_reset_counters();
  },
  debugGetCounters(): { windowsCreated: number; windowsDestroyed: number; nodesCreated: number; nodesDestroyed: number } {
    const windowsCreated = new BigUint64Array(1);
    const windowsDestroyed = new BigUint64Array(1);
    const nodesCreated = new BigUint64Array(1);
    const nodesDestroyed = new BigUint64Array(1);
    const status = nativeLibrary.symbols.zig_dom_debug_get_counters(
      ptr(windowsCreated),
      ptr(windowsDestroyed),
      ptr(nodesCreated),
      ptr(nodesDestroyed)
    );
    assertStatus(status, "zig_dom_debug_get_counters");

    return {
      windowsCreated: Number(windowsCreated[0]),
      windowsDestroyed: Number(windowsDestroyed[0]),
      nodesCreated: Number(nodesCreated[0]),
      nodesDestroyed: Number(nodesDestroyed[0])
    };
  }
};

export type NativeBindings = typeof native;

const std = @import("std");
const runtime_pkg = @import("../runtime/runtime.zig");
const transform = @import("transform.zig");
const yuku_transform = @import("yuku_transform.zig");
const quickjs = @import("quickjs");

const Allocator = std.mem.Allocator;
const Runtime = runtime_pkg.Runtime;
const Exception = runtime_pkg.Exception;
const ModuleContext = runtime_pkg.ModuleContext;
const ModuleDef = runtime_pkg.ModuleDef;

const run_bootstrap_source =
    \\globalThis.__zigDone = false;
    \\globalThis.__zigRunError = "";
    \\Promise.resolve()
    \\  .then(() => globalThis.__zigRunner.run())
    \\  .then(() => {
    \\    globalThis.__zigDone = true;
    \\  })
    \\  .catch((error) => {
    \\    const details = error && error.stack ? String(error.stack) : String(error);
    \\    globalThis.__zigRunError = details;
    \\    globalThis.__zigDone = true;
    \\  });
;

const collection_flush_source =
    \\globalThis.__zigCollectionFlushDone = false;
    \\Promise.resolve().then(() => {
    \\  globalThis.__zigCollectionFlushDone = true;
    \\});
;

const setup_dom_probe_begin_source =
    \\globalThis.__zigSetupDocumentNodeNameHidden = false;
    \\try {
    \\  if (globalThis.document && globalThis.document.nodeName) {
    \\    Object.defineProperty(globalThis.document, "nodeName", {
    \\      value: undefined,
    \\      configurable: true
    \\    });
    \\    globalThis.__zigSetupDocumentNodeNameHidden = true;
    \\  }
    \\} catch {}
;

const setup_dom_probe_end_source =
    \\try {
    \\  if (globalThis.__zigSetupDocumentNodeNameHidden && globalThis.document) {
    \\    delete globalThis.document.nodeName;
    \\  }
    \\} catch {}
    \\globalThis.__zigSetupDocumentNodeNameHidden = false;
;

const bun_specifier = "bun";
const bun_test_specifier = "bun:test";
const node_url_specifier = "url";
const node_url_colon_specifier = "node:url";
const node_fs_specifier = "fs";
const node_fs_colon_specifier = "node:fs";
const node_path_specifier = "path";
const node_path_colon_specifier = "node:path";
const node_util_specifier = "util";
const node_util_colon_specifier = "node:util";
const node_buffer_specifier = "buffer";
const node_buffer_colon_specifier = "node:buffer";
const node_crypto_specifier = "crypto";
const node_crypto_colon_specifier = "node:crypto";
const node_http_specifier = "http";
const node_http_colon_specifier = "node:http";
const node_https_specifier = "https";
const node_https_colon_specifier = "node:https";
const node_net_specifier = "net";
const node_net_colon_specifier = "node:net";
const node_zlib_specifier = "zlib";
const node_zlib_colon_specifier = "node:zlib";
const node_child_process_specifier = "child_process";
const node_child_process_colon_specifier = "node:child_process";
const node_stream_specifier = "stream";
const node_stream_colon_specifier = "node:stream";
const node_stream_web_specifier = "stream/web";
const node_stream_web_colon_specifier = "node:stream/web";
const node_vm_specifier = "vm";
const node_vm_colon_specifier = "node:vm";
const node_perf_hooks_colon_specifier = "node:perf_hooks";
const zig_dom_specifier = "zig-dom";
const zig_dom_index_specifier = "zig-dom/index";
const zig_dom_global_registrator_specifier = "zig-dom/global-registrator";
const zig_dom_global_registrar_specifier = "zig-dom/global-registrar";

const bun_shim_source =
    \\const api = globalThis.__zigBunApi;
    \\export const plugin = api.plugin;
    \\export const $ = api.$;
    \\export const file = api.file;
    \\const bunApi = { plugin, $, file };
    \\export default bunApi;
;

const bun_test_shim_source =
    \\const api = globalThis.__zigBunTestApi;
    \\export const test = api.test;
    \\export const it = api.it;
    \\export const describe = api.describe;
    \\export const expect = api.expect;
    \\export const mock = api.mock;
    \\export const spyOn = api.spyOn;
    \\export const beforeAll = api.beforeAll;
    \\export const beforeEach = api.beforeEach;
    \\export const afterEach = api.afterEach;
    \\export const afterAll = api.afterAll;
    \\const bunTest = { test, it, describe, expect, mock, spyOn, beforeAll, beforeEach, afterEach, afterAll };
    \\export default bunTest;
;

const zig_dom_global_registrator_shim_source = @embedFile("builtins/zig-dom/global-registrator.js");
const zig_dom_index_shim_source = @embedFile("builtins/zig-dom/index.js");

const node_url_shim_source =
    \\const URLCtor = globalThis.URL;
    \\const URLSearchParamsCtor = globalThis.URLSearchParams;
    \\export const URL = URLCtor;
    \\export const URLSearchParams = URLSearchParamsCtor;
    \\export function pathToFileURL(pathLike) {
    \\  const raw = String(pathLike ?? "");
    \\  if (raw.startsWith("file:")) {
    \\    return new URLCtor(raw);
    \\  }
    \\  const normalized = raw.replace(/\\\\/g, "/");
    \\  const prefixed = normalized.startsWith("/") ? normalized : `/${normalized}`;
    \\  return new URLCtor(`file://${prefixed}`);
    \\}
    \\export function fileURLToPath(input) {
    \\  const parsed = input instanceof URLCtor ? input : new URLCtor(String(input ?? ""));
    \\  if (parsed.protocol !== "file:") {
    \\    throw new TypeError("fileURLToPath expects a file URL");
    \\  }
    \\  return decodeURIComponent(parsed.pathname || "");
    \\}
    \\export default { URL, URLSearchParams, pathToFileURL, fileURLToPath };
;

const node_fs_shim_source =
    \\function unsupported(name) {
    \\  throw new Error(`node:fs.${name} is not implemented in this runner`);
    \\}
    \\function resolvePath(path) {
    \\  const raw = String(path);
    \\  if (raw.startsWith("/")) return raw;
    \\  const cwd = globalThis.process && typeof globalThis.process.cwd === "function" ? globalThis.process.cwd() : "";
    \\  return cwd ? `${cwd.replace(/\/+$/, "")}/${raw}` : raw;
    \\}
    \\export function readFileSync(path, encoding = "utf8") {
    \\  if (encoding !== "utf8" && encoding !== "utf-8") {
    \\    unsupported("readFileSync encoding " + encoding);
    \\  }
    \\  return globalThis.__zigReadFileSync(resolvePath(path), encoding);
    \\}
    \\export function writeFileSync() { unsupported("writeFileSync"); }
    \\export function mkdirSync() { unsupported("mkdirSync"); }
    \\export function readdirSync() { unsupported("readdirSync"); }
    \\export function existsSync() { return false; }
    \\export default { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync };
;

const node_http_shim_source =
    \\function unsupported(name) {
    \\  throw new Error(`node:http.${name} is not implemented in this runner`);
    \\}
    \\export function request() { unsupported("request"); }
    \\export function get() { unsupported("get"); }
    \\export function createServer() { unsupported("createServer"); }
    \\export default { request, get, createServer };
;

const node_https_shim_source =
    \\import * as http from "http";
    \\export const request = http.request;
    \\export const get = http.get;
    \\export default { request, get };
;

const node_net_shim_source =
    \\function unsupported(name) {
    \\  throw new Error(`node:net.${name} is not implemented in this runner`);
    \\}
    \\export function createConnection() { unsupported("createConnection"); }
    \\export function createServer() { unsupported("createServer"); }
    \\export function isIP() { return 0; }
    \\export default { createConnection, createServer, isIP };
;

const node_zlib_shim_source =
    \\function unsupported(name) {
    \\  throw new Error(`node:zlib.${name} is not implemented in this runner`);
    \\}
    \\export function gzipSync() { unsupported("gzipSync"); }
    \\export function gunzipSync() { unsupported("gunzipSync"); }
    \\export default { gzipSync, gunzipSync };
;

const node_child_process_shim_source =
    \\function unsupported(name) {
    \\  throw new Error(`node:child_process.${name} is not implemented in this runner`);
    \\}
    \\export function spawn() { unsupported("spawn"); }
    \\export function exec() { unsupported("exec"); }
    \\export default { spawn, exec };
;

const node_path_shim_source =
    \\function normalize(value) {
    \\  return String(value ?? "").replace(/\\\\/g, "/");
    \\}
    \\export function join(...parts) {
    \\  return parts.map((part) => normalize(part)).filter(Boolean).join("/").replace(/\/+/g, "/");
    \\}
    \\export function resolve(...parts) {
    \\  return join(...parts);
    \\}
    \\export function dirname(input) {
    \\  const normalized = normalize(input);
    \\  const index = normalized.lastIndexOf("/");
    \\  return index <= 0 ? "." : normalized.slice(0, index);
    \\}
    \\export function basename(input) {
    \\  const normalized = normalize(input);
    \\  const index = normalized.lastIndexOf("/");
    \\  return index < 0 ? normalized : normalized.slice(index + 1);
    \\}
    \\export function extname(input) {
    \\  const base = basename(input);
    \\  const index = base.lastIndexOf(".");
    \\  return index <= 0 ? "" : base.slice(index);
    \\}
    \\export default { join, resolve, dirname, basename, extname };
;

const node_util_shim_source =
    \\export function inspect(value) {
    \\  try {
    \\    return JSON.stringify(value);
    \\  } catch {
    \\    return String(value);
    \\  }
    \\}
    \\export function format(...values) {
    \\  return values.map((value) => String(value)).join(" ");
    \\}
    \\export function promisify(fn) {
    \\  return (...args) =>
    \\    new Promise((resolve, reject) => {
    \\      fn(...args, (error, value) => {
    \\        if (error) reject(error);
    \\        else resolve(value);
    \\      });
    \\    });
    \\}
    \\export const TextEncoder = globalThis.TextEncoder;
    \\export const TextDecoder = globalThis.TextDecoder;
    \\export default { inspect, format, promisify, TextEncoder, TextDecoder };
;

const node_buffer_shim_source =
    \\class BufferImpl extends Uint8Array {
    \\  static from(input) {
    \\    if (typeof input === "string") {
    \\      return new TextEncoder().encode(input);
    \\    }
    \\    if (Array.isArray(input) || ArrayBuffer.isView(input)) {
    \\      return new Uint8Array(input);
    \\    }
    \\    if (input instanceof ArrayBuffer) {
    \\      return new Uint8Array(input);
    \\    }
    \\    return new Uint8Array(0);
    \\  }
    \\  static isBuffer(value) {
    \\    return value instanceof Uint8Array;
    \\  }
    \\}
    \\export const Buffer = BufferImpl;
    \\export const Blob = globalThis.Blob;
    \\export default { Buffer, Blob };
;

const node_crypto_shim_source =
    \\const cryptoApi = globalThis.crypto || {};
    \\export function randomUUID() {
    \\  if (typeof cryptoApi.randomUUID === "function") {
    \\    return cryptoApi.randomUUID();
    \\  }
    \\  return "00000000-0000-4000-8000-000000000000";
    \\}
    \\export const webcrypto = cryptoApi;
    \\export default { randomUUID, webcrypto };
;

const node_stream_shim_source =
    \\class Readable {}
    \\class Writable {}
    \\class Transform {}
    \\class Duplex {}
    \\export { Readable, Writable, Transform, Duplex };
    \\export default { Readable, Writable, Transform, Duplex };
;

const node_stream_web_shim_source =
    \\export const ReadableStream = globalThis.ReadableStream;
    \\export const WritableStream = globalThis.WritableStream;
    \\export const TransformStream = globalThis.TransformStream;
    \\export default { ReadableStream, WritableStream, TransformStream };
;

const node_vm_shim_source =
    \\function unsupported(name) {
    \\  throw new Error(`node:vm.${name} is not implemented in this runner`);
    \\}
    \\export function runInNewContext() { unsupported("runInNewContext"); }
    \\export function runInContext() { unsupported("runInContext"); }
    \\export function runInThisContext() { unsupported("runInThisContext"); }
    \\export class Script {
    \\  constructor() {}
    \\  runInThisContext() { unsupported("Script.runInThisContext"); }
    \\}
    \\export default { runInNewContext, runInContext, runInThisContext, Script };
;

const node_perf_hooks_shim_source =
    \\export const performance = globalThis.performance;
    \\export class PerformanceObserver {
    \\  observe() {}
    \\  disconnect() {}
    \\  takeRecords() { return []; }
    \\}
    \\export class PerformanceEntry {}
    \\export default { performance, PerformanceObserver, PerformanceEntry };
;

const max_module_source_bytes = 4 * 1024 * 1024;
const max_tsconfig_bytes = 2 * 1024 * 1024;
const max_package_json_bytes = 512 * 1024;

const TransformBatchEntry = struct {
    input_path: []const u8,
    loader: []const u8,
    contents: ?[]u8 = null,
};

const CommonJsImport = struct {
    specifier: []u8,
    resolved: []u8,
    local: []u8,
    json_source: ?[]u8 = null,

    fn deinit(self: *CommonJsImport, allocator: Allocator) void {
        allocator.free(self.specifier);
        allocator.free(self.resolved);
        allocator.free(self.local);
        if (self.json_source) |json| allocator.free(json);
    }
};

pub const FileResult = struct {
    path: []u8,
    passed: usize,
    failed: usize,
    skipped: usize,
    timed_out: usize,
    collection_errors: usize,
    failure_report: ?[]u8,
    collection_report: ?[]u8,

    pub fn deinit(self: *FileResult, allocator: Allocator) void {
        allocator.free(self.path);
        if (self.failure_report) |report| {
            allocator.free(report);
        }
        if (self.collection_report) |report| {
            allocator.free(report);
        }
    }
};

pub const Summary = struct {
    files: []FileResult,
    total_passed: usize,
    total_failed: usize,
    total_skipped: usize,
    total_timed_out: usize,
    total_collection_errors: usize,

    pub fn deinit(self: *Summary, allocator: Allocator) void {
        for (self.files) |*file| {
            file.deinit(allocator);
        }
        allocator.free(self.files);
    }

    pub fn hasFailures(self: Summary) bool {
        return self.total_failed > 0 or self.total_timed_out > 0 or self.total_collection_errors > 0;
    }
};

const ModuleLoaderState = struct {
    const PathAlias = struct {
        pattern: []u8,
        target: []u8,
    };

    allocator: Allocator,
    io: std.Io,
    runtime: ?*Runtime,
    loaded_modules: std.StringHashMap(*ModuleDef),
    transformed_sources: std.StringHashMap([]u8),
    pending_onload_transforms: std.ArrayList(TransformBatchEntry),
    mock_module_sources: std.StringHashMap([]u8),
    path_alias_root: ?[]u8,
    path_aliases: std.ArrayList(PathAlias),

    fn init(allocator: Allocator, io: std.Io) ModuleLoaderState {
        return .{
            .allocator = allocator,
            .io = io,
            .runtime = null,
            .loaded_modules = std.StringHashMap(*ModuleDef).init(allocator),
            .transformed_sources = std.StringHashMap([]u8).init(allocator),
            .pending_onload_transforms = .empty,
            .mock_module_sources = std.StringHashMap([]u8).init(allocator),
            .path_alias_root = null,
            .path_aliases = .empty,
        };
    }

    fn deinit(self: *ModuleLoaderState) void {
        self.clearPathAliases();

        var output_iterator = self.transformed_sources.iterator();
        while (output_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.transformed_sources.deinit();

        self.clearPendingOnLoadTransforms();
        self.pending_onload_transforms.deinit(self.allocator);

        var mock_iterator = self.mock_module_sources.iterator();
        while (mock_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.mock_module_sources.deinit();

        var loaded_iterator = self.loaded_modules.iterator();
        while (loaded_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.loaded_modules.deinit();
    }

    fn normalizeSpecifier(self: *ModuleLoaderState, module_base_name: []const u8, module_name: []const u8) ![]u8 {
        if (self.runtime) |runtime| {
            try self.syncMockModulesFromRuntime(runtime);
        }

        if (builtInModuleSource(module_name) != null) {
            return self.allocator.dupe(u8, module_name);
        }

        if (self.mock_module_sources.contains(module_name)) {
            return std.fmt.allocPrint(self.allocator, "__zig_mock__/{s}", .{module_name});
        }

        if (try self.resolvePathAlias(module_base_name, module_name)) |resolved| {
            return resolved;
        }

        if (std.fs.path.isAbsolute(module_name)) {
            return self.resolveAbsolutePath(module_name);
        }

        if (isRelativeSpecifier(module_name)) {
            return self.resolveRelativePath(module_base_name, module_name);
        }

        if (try self.resolveNodeModule(module_base_name, module_name)) |resolved| {
            return resolved;
        }

        return error.UnsupportedExternalModule;
    }

    fn preloadEntryGraph(self: *ModuleLoaderState, entry_module_id: []const u8) !void {
        const graph = try self.discoverModuleGraph(entry_module_id);
        defer {
            for (graph) |module_id| {
                self.allocator.free(module_id);
            }
            self.allocator.free(graph);
        }

        var transform_targets: std.ArrayList([]const u8) = .empty;
        defer transform_targets.deinit(self.allocator);
        for (graph) |module_id| {
            if (transform.needsTransform(module_id)) {
                try transform_targets.append(self.allocator, module_id);
            }
        }

        try self.prepareTransformTargets(transform_targets.items, true);
    }

    fn prepareTransformTargets(self: *ModuleLoaderState, module_paths: []const []const u8, include_pending_onload: bool) !void {
        var pending: std.ArrayList(TransformBatchEntry) = .empty;
        defer pending.deinit(self.allocator);

        for (module_paths) |module_id| {
            if (self.transformed_sources.contains(module_id)) {
                continue;
            }
            if (include_pending_onload and self.hasPendingOnLoadTransform(module_id)) {
                continue;
            }
            const loader = transform.loaderForPath(module_id) orelse return error.TransformCommandFailed;
            try pending.append(self.allocator, .{
                .input_path = module_id,
                .loader = loader,
            });
        }

        if (include_pending_onload) {
            for (self.pending_onload_transforms.items) |entry| {
                try pending.append(self.allocator, entry);
            }
            self.pending_onload_transforms.clearRetainingCapacity();
        }

        defer {
            for (pending.items) |entry| {
                if (entry.contents != null) {
                    self.allocator.free(entry.input_path);
                    self.allocator.free(entry.loader);
                    self.allocator.free(entry.contents.?);
                }
            }
        }

        if (pending.items.len > 0) {
            const exit_code = try self.runTransformBatch(pending.items);
            if (exit_code != 0) {
                return error.TransformCommandFailed;
            }
        }
    }

    fn discoverModuleGraph(self: *ModuleLoaderState, entry_module_id: []const u8) ![]const []u8 {
        var queue: std.ArrayList([]u8) = .empty;
        errdefer {
            for (queue.items) |item| {
                self.allocator.free(item);
            }
            queue.deinit(self.allocator);
        }

        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();
        var scanned_cjs = std.StringHashMap(void).init(self.allocator);
        defer {
            var scanned_iterator = scanned_cjs.iterator();
            while (scanned_iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            scanned_cjs.deinit();
        }

        const entry = try self.allocator.dupe(u8, entry_module_id);
        queue.append(self.allocator, entry) catch |err| {
            self.allocator.free(entry);
            return err;
        };
        seen.put(entry, {}) catch |err| {
            _ = queue.pop();
            self.allocator.free(entry);
            return err;
        };

        var index: usize = 0;
        while (index < queue.items.len) : (index += 1) {
            const module_id = queue.items[index];

            const source = try self.loadModuleSourceForGraph(module_id);
            defer self.allocator.free(source);

            const specifiers = try collectEsmSpecifiers(self.allocator, source);
            defer {
                for (specifiers) |specifier| {
                    self.allocator.free(specifier);
                }
                self.allocator.free(specifiers);
            }

            for (specifiers) |specifier| {
                const resolved = self.normalizeSpecifier(module_id, specifier) catch |err| switch (err) {
                    // External package specifiers may be type-only imports erased by transform.
                    error.UnsupportedExternalModule => continue,
                    error.ModuleNotFound => {
                        if (isBarePackageSpecifier(specifier)) {
                            continue;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) {
                    self.allocator.free(resolved);
                    continue;
                }

                if (seen.contains(resolved)) {
                    self.allocator.free(resolved);
                    continue;
                }

                try seen.put(resolved, {});
                try queue.append(self.allocator, resolved);
            }

            if (isCommonJsSource(module_id, source)) {
                try self.enqueueCommonJsBareDependencies(module_id, source, &seen, &queue, &scanned_cjs);
            }
        }

        return queue.toOwnedSlice(self.allocator);
    }

    fn enqueueCommonJsBareDependencies(
        self: *ModuleLoaderState,
        module_id: []const u8,
        source: []const u8,
        seen: *std.StringHashMap(void),
        queue: *std.ArrayList([]u8),
        scanned_cjs: *std.StringHashMap(void),
    ) !void {
        if (scanned_cjs.contains(module_id)) {
            return;
        }
        const scanned_key = try self.allocator.dupe(u8, module_id);
        errdefer self.allocator.free(scanned_key);
        try scanned_cjs.put(scanned_key, {});

        const cjs_specifiers = try collectCommonJsSpecifiers(self.allocator, source);
        defer {
            for (cjs_specifiers) |specifier| {
                self.allocator.free(specifier);
            }
            self.allocator.free(cjs_specifiers);
        }

        for (cjs_specifiers) |specifier| {
            if (isRelativeSpecifier(specifier)) {
                const resolved_relative = self.normalizeSpecifier(module_id, specifier) catch continue;

                if (builtInModuleSource(resolved_relative) != null or isMockModuleId(resolved_relative)) {
                    self.allocator.free(resolved_relative);
                    continue;
                }

                const scan_module_id = if (scanned_cjs.contains(resolved_relative))
                    null
                else
                    try self.allocator.dupe(u8, resolved_relative);
                defer if (scan_module_id) |owned| self.allocator.free(owned);

                if (!seen.contains(resolved_relative)) {
                    try seen.put(resolved_relative, {});
                    try queue.append(self.allocator, resolved_relative);
                } else {
                    self.allocator.free(resolved_relative);
                }

                const scan_id = scan_module_id orelse {
                    continue;
                };
                const relative_source = self.loadModuleSourceForGraph(scan_id) catch continue;
                defer self.allocator.free(relative_source);

                if (isCommonJsSource(scan_id, relative_source)) {
                    try self.enqueueCommonJsBareDependencies(scan_id, relative_source, seen, queue, scanned_cjs);
                }
                continue;
            }

            const resolved = self.normalizeSpecifier(module_id, specifier) catch |err| switch (err) {
                error.UnsupportedExternalModule => continue,
                error.ModuleNotFound => continue,
                else => return err,
            };
            if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) {
                self.allocator.free(resolved);
                continue;
            }

            if (seen.contains(resolved)) {
                self.allocator.free(resolved);
                continue;
            }

            try seen.put(resolved, {});
            try queue.append(self.allocator, resolved);
        }
    }

    fn loadModuleSourceForGraph(self: *ModuleLoaderState, module_id: []const u8) ![]u8 {
        const default_loader = transform.loaderForPath(module_id) orelse return error.UnsupportedModuleExtension;

        if (std.fs.path.isAbsolute(module_id)) {
            if (self.runtime) |runtime| {
                var hook_result = (try self.invokeOnLoad(runtime, module_id)) orelse {
                    return std.Io.Dir.cwd().readFileAlloc(
                        self.io,
                        module_id,
                        self.allocator,
                        .limited(max_module_source_bytes),
                    );
                };
                defer hook_result.deinit(self.allocator);
                const effective_loader = hook_result.loader orelse default_loader;
                if (std.mem.eql(u8, effective_loader, "ts") or
                    std.mem.eql(u8, effective_loader, "tsx") or
                    std.mem.eql(u8, effective_loader, "jsx") or
                    (std.mem.eql(u8, effective_loader, "js") and looksLikeJsxSource(hook_result.contents)))
                {
                    const transform_loader = if (std.mem.eql(u8, effective_loader, "js")) "jsx" else effective_loader;
                    try self.queueOnLoadTransform(module_id, transform_loader, hook_result.contents);
                }
                return try self.allocator.dupe(u8, hook_result.contents);
            }
        }

        return std.Io.Dir.cwd().readFileAlloc(
            self.io,
            module_id,
            self.allocator,
            .limited(max_module_source_bytes),
        );
    }

    fn loadModuleSource(self: *ModuleLoaderState, module_id: []const u8) ![]u8 {
        if (builtInModuleSource(module_id)) |shim_source| {
            return self.allocator.dupe(u8, shim_source);
        }

        if (isMockModuleId(module_id)) {
            const specifier = module_id["__zig_mock__/".len..];
            const source = self.mock_module_sources.get(specifier) orelse return error.ModuleNotFound;
            return self.allocator.dupe(u8, source);
        }

        const default_loader = transform.loaderForPath(module_id) orelse return error.UnsupportedModuleExtension;

        if (try self.loadModuleSourceFromOnLoad(module_id, default_loader)) |hook_source| {
            return hook_source;
        }

        if (std.mem.eql(u8, default_loader, "js")) {
            const source = try std.Io.Dir.cwd().readFileAlloc(
                self.io,
                module_id,
                self.allocator,
                .limited(max_module_source_bytes),
            );

            if (isCommonJsSource(module_id, source)) {
                self.allocator.free(source);
                return try self.loadCommonJsModuleSource(module_id);
            }

            return source;
        }

        if (std.mem.eql(u8, default_loader, "json")) {
            const json = try std.Io.Dir.cwd().readFileAlloc(
                self.io,
                module_id,
                self.allocator,
                .limited(max_module_source_bytes),
            );
            defer self.allocator.free(json);

            var source: std.ArrayList(u8) = .empty;
            errdefer source.deinit(self.allocator);
            try source.appendSlice(self.allocator, "export default ");
            try source.appendSlice(self.allocator, json);
            try source.appendSlice(self.allocator, ";\n");
            return try source.toOwnedSlice(self.allocator);
        }

        if (self.transformed_sources.get(module_id)) |transformed| {
            return self.allocator.dupe(u8, transformed);
        }

        if (std.c.getenv("ZIG_DOM_TRANSFORM_DEBUG") != null) {
            std.debug.print("[zig-dom transform] {s} {s}\n", .{ default_loader, module_id });
        }
        const transformed = try yuku_transform.transformFile(self.allocator, self.io, module_id, default_loader);
        errdefer self.allocator.free(transformed);
        const key = try self.allocator.dupe(u8, module_id);
        errdefer self.allocator.free(key);
        try self.transformed_sources.put(key, transformed);
        return self.allocator.dupe(u8, transformed);
    }

    fn loadCommonJsModuleSource(self: *ModuleLoaderState, module_id: []const u8) ![]u8 {
        const source = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            module_id,
            self.allocator,
            .limited(max_module_source_bytes),
        );
        defer self.allocator.free(source);

        return self.buildNativeCommonJsModuleSource(module_id, source);
    }

    fn buildNativeCommonJsModuleSource(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) ![]u8 {
        const specifiers = try collectCommonJsSpecifiers(self.allocator, source);
        defer {
            for (specifiers) |specifier| self.allocator.free(specifier);
            self.allocator.free(specifiers);
        }

        var imports: std.ArrayList(CommonJsImport) = .empty;
        defer {
            for (imports.items) |*item| item.deinit(self.allocator);
            imports.deinit(self.allocator);
        }

        for (specifiers, 0..) |specifier, index| {
            const resolved = self.normalizeSpecifier(module_id, specifier) catch continue;
            errdefer self.allocator.free(resolved);

            const local = if (std.mem.endsWith(u8, resolved, ".json"))
                try self.allocator.dupe(u8, "")
            else
                try std.fmt.allocPrint(self.allocator, "__zig_cjs_dep_{d}", .{index});
            errdefer self.allocator.free(local);

            const json_source = if (std.mem.endsWith(u8, resolved, ".json"))
                try std.Io.Dir.cwd().readFileAlloc(self.io, resolved, self.allocator, .limited(max_module_source_bytes))
            else
                null;
            errdefer if (json_source) |json| self.allocator.free(json);

            try imports.append(self.allocator, .{
                .specifier = try self.allocator.dupe(u8, specifier),
                .resolved = resolved,
                .local = local,
                .json_source = json_source,
            });
        }

        const export_names = try self.collectCommonJsExportNamesDeep(module_id, source);
        defer {
            for (export_names) |name| self.allocator.free(name);
            self.allocator.free(export_names);
        }

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);

        for (imports.items) |item| {
            if (item.json_source != null) continue;
            const resolved_literal = try escapeJsSingleQuotedString(self.allocator, item.resolved);
            defer self.allocator.free(resolved_literal);
            try appendFmt(self.allocator, &out, "import * as {s} from '{s}';\n", .{ item.local, resolved_literal });
        }

        const module_literal = try escapeJsSingleQuotedString(self.allocator, module_id);
        defer self.allocator.free(module_literal);
        const dirname = std.fs.path.dirname(module_id) orelse ".";
        const dirname_literal = try escapeJsSingleQuotedString(self.allocator, dirname);
        defer self.allocator.free(dirname_literal);

        try out.appendSlice(self.allocator,
            \\const __zigCjsRegistry = globalThis.__zigCjsRegistry || (globalThis.__zigCjsRegistry = new Map());
            \\function __zigCjsNamespaceToRequireValue(ns) {
            \\  try {
            \\    if (Object.prototype.hasOwnProperty.call(ns, "__zigCommonJSExports")) return ns.__zigCommonJSExports;
            \\    if (Object.prototype.hasOwnProperty.call(ns, "default")) return ns.default;
            \\    return ns;
            \\  } catch {
            \\    return {};
            \\  }
            \\}
            \\const __zigCjsDeps = {
            \\
        );

        for (imports.items) |item| {
            const specifier_literal = try escapeJsSingleQuotedString(self.allocator, item.specifier);
            defer self.allocator.free(specifier_literal);
            if (item.json_source) |json| {
                try appendFmt(self.allocator, &out, "  '{s}': () => (", .{specifier_literal});
                try out.appendSlice(self.allocator, json);
                try out.appendSlice(self.allocator, "),\n");
            } else {
                try appendFmt(self.allocator, &out, "  '{s}': () => __zigCjsNamespaceToRequireValue({s}),\n", .{ specifier_literal, item.local });
            }
        }

        try out.appendSlice(self.allocator,
            \\};
            \\function __zigLoadCommonJS(id, dirname, deps, factory) {
            \\  if (__zigCjsRegistry.has(id)) return __zigCjsRegistry.get(id).exports;
            \\  const module = { exports: {} };
            \\  __zigCjsRegistry.set(id, module);
            \\  const require = (specifier) => {
            \\    const load = deps[String(specifier)];
            \\    if (!load) throw new Error(`Cannot find module '${specifier}' from ${id}`);
            \\    return load();
            \\  };
            \\  require.resolve = (specifier) => String(specifier);
            \\  factory.call(module.exports, module, module.exports, require, id, dirname, globalThis);
            \\  return module.exports;
            \\}
            \\
        );
        try appendFmt(self.allocator, &out, "const __zigCommonJSExports = __zigLoadCommonJS('{s}', '{s}', __zigCjsDeps, function(module, exports, require, __filename, __dirname, global) {{\n", .{ module_literal, dirname_literal });
        try out.appendSlice(self.allocator, source);
        try out.appendSlice(self.allocator,
            \\
            \\});
            \\export { __zigCommonJSExports };
            \\export default __zigCommonJSExports;
            \\
        );

        for (export_names) |name| {
            try appendFmt(self.allocator, &out, "export const {s} = __zigCommonJSExports == null ? undefined : __zigCommonJSExports.{s};\n", .{ name, name });
        }

        return out.toOwnedSlice(self.allocator);
    }

    fn collectCommonJsExportNamesDeep(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) ![]const []u8 {
        var names: std.ArrayList([]u8) = .empty;
        errdefer {
            for (names.items) |name| self.allocator.free(name);
            names.deinit(self.allocator);
        }

        var dedup = std.StringHashMap(void).init(self.allocator);
        defer dedup.deinit();
        var scanned = std.StringHashMap(void).init(self.allocator);
        defer {
            var iterator = scanned.iterator();
            while (iterator.next()) |entry| self.allocator.free(entry.key_ptr.*);
            scanned.deinit();
        }

        try self.collectCommonJsExportNamesInto(module_id, source, &names, &dedup, &scanned);
        return names.toOwnedSlice(self.allocator);
    }

    fn collectCommonJsExportNamesInto(
        self: *ModuleLoaderState,
        module_id: []const u8,
        source: []const u8,
        names: *std.ArrayList([]u8),
        dedup: *std.StringHashMap(void),
        scanned: *std.StringHashMap(void),
    ) !void {
        if (scanned.contains(module_id)) return;

        const scanned_key = try self.allocator.dupe(u8, module_id);
        errdefer self.allocator.free(scanned_key);
        try scanned.put(scanned_key, {});

        try collectCommonJsExportNamesFromSource(self.allocator, source, names, dedup);

        const specifiers = try collectCommonJsSpecifiers(self.allocator, source);
        defer {
            for (specifiers) |specifier| self.allocator.free(specifier);
            self.allocator.free(specifiers);
        }

        for (specifiers) |specifier| {
            if (!isRelativeSpecifier(specifier)) continue;

            const resolved = self.normalizeSpecifier(module_id, specifier) catch continue;
            defer self.allocator.free(resolved);
            if (scanned.contains(resolved)) continue;

            const child_source = std.Io.Dir.cwd().readFileAlloc(
                self.io,
                resolved,
                self.allocator,
                .limited(max_module_source_bytes),
            ) catch continue;
            defer self.allocator.free(child_source);

            if (isCommonJsSource(resolved, child_source)) {
                try self.collectCommonJsExportNamesInto(resolved, child_source, names, dedup, scanned);
            }
        }
    }

    fn syncMockModulesFromRuntime(self: *ModuleLoaderState, runtime: *Runtime) !void {
        self.clearMockModules();

        const manifest_json = runtime.getGlobalStringDup("__zigMockModuleManifestJson") catch {
            return;
        };
        defer self.allocator.free(manifest_json);

        if (manifest_json.len == 0) {
            return;
        }

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, manifest_json, .{});
        defer parsed.deinit();

        if (parsed.value != .array) {
            return;
        }

        for (parsed.value.array.items) |entry| {
            if (entry != .object) {
                continue;
            }

            const specifier_value = entry.object.get("specifier") orelse continue;
            const source_value = entry.object.get("source") orelse continue;
            if (specifier_value != .string or source_value != .string) {
                continue;
            }

            const key = try self.allocator.dupe(u8, specifier_value.string);
            errdefer self.allocator.free(key);

            const value = try self.allocator.dupe(u8, source_value.string);
            errdefer self.allocator.free(value);

            if (try self.mock_module_sources.fetchPut(key, value)) |previous| {
                self.allocator.free(previous.key);
                self.allocator.free(previous.value);
            }
        }
    }

    fn loadModuleSourceFromOnLoad(
        self: *ModuleLoaderState,
        module_id: []const u8,
        default_loader: []const u8,
    ) !?[]u8 {
        if (!std.fs.path.isAbsolute(module_id)) {
            return null;
        }

        const runtime = self.runtime orelse return null;
        var hook_result = (try self.invokeOnLoad(runtime, module_id)) orelse return null;
        defer hook_result.deinit(self.allocator);

        const effective_loader = hook_result.loader orelse default_loader;
        if (std.mem.eql(u8, effective_loader, "js")) {
            if (looksLikeJsxSource(hook_result.contents)) {
                return try self.transformOnLoadContents(module_id, "jsx", hook_result.contents);
            }
            return try self.allocator.dupe(u8, hook_result.contents);
        }

        if (
            std.mem.eql(u8, effective_loader, "ts") or
            std.mem.eql(u8, effective_loader, "tsx") or
            std.mem.eql(u8, effective_loader, "jsx")
        ) {
            const transformed = try self.transformOnLoadContents(module_id, effective_loader, hook_result.contents);
            return transformed;
        }

        return error.UnsupportedTransformLoader;
    }

    const OnLoadResult = struct {
        contents: []u8,
        loader: ?[]u8,

        fn deinit(self: *OnLoadResult, allocator: Allocator) void {
            allocator.free(self.contents);
            if (self.loader) |loader| {
                allocator.free(loader);
            }
        }
    };

    fn invokeOnLoad(self: *ModuleLoaderState, runtime: *Runtime, module_id: []const u8) !?OnLoadResult {
        const module_id_literal = try escapeJsSingleQuotedString(self.allocator, module_id);
        defer self.allocator.free(module_id_literal);

        const request_prefix =
            \\globalThis.__zigOnLoadDone = false;
            \\globalThis.__zigOnLoadError = "";
            \\globalThis.__zigOnLoadResult = "";
            \\Promise.resolve()
            \\  .then(() => {
            \\    const apply = globalThis.__zigRunnerApplyOnLoad;
            \\    if (typeof apply !== "function") {
            \\      return null;
            \\    }
            \\    return apply('
        ;
        const request_suffix =
            \\');
            \\  })
            \\  .then((value) => {
            \\    if (!value || typeof value !== "object" || !Object.prototype.hasOwnProperty.call(value, "contents")) {
            \\      globalThis.__zigOnLoadResult = "";
            \\    } else {
            \\      const loader = value.loader == null ? null : String(value.loader);
            \\      const contents = String(value.contents);
            \\      globalThis.__zigOnLoadResult = JSON.stringify({ loader, contents });
            \\    }
            \\    globalThis.__zigOnLoadDone = true;
            \\  })
            \\  .catch((error) => {
            \\    const details = error && error.stack ? String(error.stack) : String(error);
            \\    globalThis.__zigOnLoadError = details;
            \\    globalThis.__zigOnLoadDone = true;
            \\  });
        ;

        const request_source = try std.mem.concat(self.allocator, u8, &.{ request_prefix, module_id_literal, request_suffix });
        defer self.allocator.free(request_source);

        try runtime.evalScript("<zig-onload-hook>", request_source);

        const timeout_ms: i64 = 10_000;
        const started = std.Io.Clock.Timestamp.now(self.io, .awake);
        while (!(runtime.getGlobalBool("__zigOnLoadDone") catch false)) {
            const elapsed = started.untilNow(self.io).raw.toMilliseconds();
            if (elapsed > timeout_ms) {
                return error.ModuleLoaderHookTimedOut;
            }

            if (runtime.isJobPending()) {
                _ = try runtime.executePendingJob();
                continue;
            }

            return error.ModuleLoaderHookFailed;
        }

        const onload_error = runtime.getGlobalStringDup("__zigOnLoadError") catch try self.allocator.dupe(u8, "");
        defer self.allocator.free(onload_error);
        if (onload_error.len > 0) {
            return error.ModuleLoaderHookFailed;
        }

        const onload_result_json = runtime.getGlobalStringDup("__zigOnLoadResult") catch try self.allocator.dupe(u8, "");
        defer self.allocator.free(onload_result_json);
        if (onload_result_json.len == 0) {
            return null;
        }

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, onload_result_json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) {
            return null;
        }

        const contents_value = parsed.value.object.get("contents") orelse return null;
        if (contents_value != .string) {
            return null;
        }

        const contents = try self.allocator.dupe(u8, contents_value.string);
        errdefer self.allocator.free(contents);

        const loader = blk: {
            const loader_value = parsed.value.object.get("loader") orelse break :blk null;
            if (loader_value != .string) {
                break :blk null;
            }

            if (loader_value.string.len == 0) {
                break :blk null;
            }

            break :blk try self.allocator.dupe(u8, loader_value.string);
        };
        errdefer if (loader) |owned| self.allocator.free(owned);

        return .{
            .contents = contents,
            .loader = loader,
        };
    }

    fn transformOnLoadContents(
        self: *ModuleLoaderState,
        module_id: []const u8,
        loader: []const u8,
        contents: []const u8,
    ) ![]u8 {
        const extension = if (std.mem.eql(u8, loader, "ts"))
            ".ts"
        else if (std.mem.eql(u8, loader, "tsx"))
            ".tsx"
        else if (std.mem.eql(u8, loader, "jsx"))
            ".jsx"
        else
            return error.UnsupportedTransformLoader;
        _ = extension;
        return yuku_transform.transformSource(self.allocator, module_id, contents, loader);
    }

    fn queueOnLoadTransform(
        self: *ModuleLoaderState,
        module_id: []const u8,
        loader: []const u8,
        contents: []const u8,
    ) !void {
        _ = onLoadTransformExtension(loader) orelse return error.UnsupportedTransformLoader;
        if (self.transformed_sources.contains(module_id) or self.hasPendingOnLoadTransform(module_id)) {
            return;
        }

        const input_path = try self.allocator.dupe(u8, module_id);
        errdefer self.allocator.free(input_path);

        const loader_owned = try self.allocator.dupe(u8, loader);
        errdefer self.allocator.free(loader_owned);
        const contents_owned = try self.allocator.dupe(u8, contents);
        errdefer self.allocator.free(contents_owned);

        try self.pending_onload_transforms.append(self.allocator, .{
            .input_path = input_path,
            .loader = loader_owned,
            .contents = contents_owned,
        });
    }

    fn hasPendingOnLoadTransform(self: *ModuleLoaderState, module_id: []const u8) bool {
        for (self.pending_onload_transforms.items) |entry| {
            if (std.mem.eql(u8, entry.input_path, module_id)) return true;
        }
        return false;
    }

    fn preparePendingOnLoadTransforms(self: *ModuleLoaderState) !void {
        defer self.clearPendingOnLoadTransforms();

        if (self.pending_onload_transforms.items.len == 0) {
            return;
        }

        const exit_code = try self.runTransformBatch(self.pending_onload_transforms.items);
        if (exit_code != 0) {
            return error.TransformCommandFailed;
        }
    }

    fn clearPendingOnLoadTransforms(self: *ModuleLoaderState) void {
        for (self.pending_onload_transforms.items) |entry| {
            self.allocator.free(entry.input_path);
            self.allocator.free(entry.loader);
            if (entry.contents) |contents| self.allocator.free(contents);
        }
        self.pending_onload_transforms.clearRetainingCapacity();
    }

    fn runTransformBatch(self: *ModuleLoaderState, entries: []const TransformBatchEntry) !u8 {
        const debug_transform = std.c.getenv("ZIG_DOM_TRANSFORM_DEBUG") != null;
        for (entries) |entry| {
            if (debug_transform) {
                std.debug.print("[zig-dom transform] {s} {s}\n", .{ entry.loader, entry.input_path });
            }
            const transformed = if (entry.contents) |contents|
                yuku_transform.transformSource(self.allocator, entry.input_path, contents, entry.loader) catch return 1
            else
                yuku_transform.transformFile(self.allocator, self.io, entry.input_path, entry.loader) catch return 1;
            errdefer self.allocator.free(transformed);

            const key = self.allocator.dupe(u8, entry.input_path) catch {
                self.allocator.free(transformed);
                return 1;
            };
            errdefer self.allocator.free(key);

            if (self.transformed_sources.fetchPut(key, transformed) catch {
                self.allocator.free(key);
                self.allocator.free(transformed);
                return 1;
            }) |previous| {
                self.allocator.free(key);
                self.allocator.free(previous.value);
            }
        }

        if (debug_transform) {
            std.debug.print("Transformed {d} file(s).\n", .{entries.len});
        }
        return 0;
    }

    fn clearMockModules(self: *ModuleLoaderState) void {
        var iterator = self.mock_module_sources.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        self.mock_module_sources.clearRetainingCapacity();
    }


fn escapeJsSingleQuotedString(allocator: Allocator, text: []const u8) ![]u8 {
    var builder: std.ArrayList(u8) = .empty;
    errdefer builder.deinit(allocator);

    for (text) |ch| {
        switch (ch) {
            '\\' => try builder.appendSlice(allocator, "\\\\"),
            '\'' => try builder.appendSlice(allocator, "\\'"),
            '\n' => try builder.appendSlice(allocator, "\\n"),
            '\r' => try builder.appendSlice(allocator, "\\r"),
            '\t' => try builder.appendSlice(allocator, "\\t"),
            else => {
                if (ch < 0x20) {
                    const hex = "0123456789ABCDEF";
                    try builder.appendSlice(allocator, "\\x");
                    try builder.append(allocator, hex[(ch >> 4) & 0x0F]);
                    try builder.append(allocator, hex[ch & 0x0F]);
                } else {
                    try builder.append(allocator, ch);
                }
            },
        }
    }

    return builder.toOwnedSlice(allocator);
}
    fn resolveRelativePath(self: *ModuleLoaderState, module_base_name: []const u8, specifier: []const u8) ![]u8 {
        if (!std.fs.path.isAbsolute(module_base_name)) {
            return error.ModuleNotFound;
        }

        const base_dir = std.fs.path.dirname(module_base_name) orelse return error.ModuleNotFound;
        const candidate = try std.fs.path.resolve(self.allocator, &.{ base_dir, specifier });
        errdefer self.allocator.free(candidate);

        return self.resolvePathWithProbing(candidate);
    }

    fn resolveAbsolutePath(self: *ModuleLoaderState, specifier: []const u8) ![]u8 {
        const candidate = try std.fs.path.resolve(self.allocator, &.{specifier});
        errdefer self.allocator.free(candidate);

        return self.resolvePathWithProbing(candidate);
    }

    fn resolvePathWithProbing(self: *ModuleLoaderState, candidate: []u8) ![]u8 {
        if (self.pathIsSupportedFile(candidate)) {
            return candidate;
        }

        if (std.mem.eql(u8, std.fs.path.extension(candidate), ".css")) {
            const css_ts_candidate = try std.fmt.allocPrint(self.allocator, "{s}.ts", .{candidate});
            if (self.pathIsSupportedFile(css_ts_candidate)) {
                self.allocator.free(candidate);
                return css_ts_candidate;
            }
            self.allocator.free(css_ts_candidate);
        }

        if (std.fs.path.extension(candidate).len > 0) {
            return error.ModuleNotFound;
        }

        if (try self.resolvePathWithoutExtension(candidate)) |resolved| {
            self.allocator.free(candidate);
            return resolved;
        }

        return error.ModuleNotFound;
    }

    fn resolvePathWithoutExtension(self: *ModuleLoaderState, base_path: []const u8) !?[]u8 {
        const extensions = [_][]const u8{ ".ts", ".tsx", ".jsx", ".mjs", ".js", ".cjs" };

        for (extensions) |extension| {
            const candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_path, extension });
            if (self.pathIsSupportedFile(candidate)) {
                return candidate;
            }
            self.allocator.free(candidate);
        }

        for (extensions) |extension| {
            const candidate = try std.fmt.allocPrint(self.allocator, "{s}/index{s}", .{ base_path, extension });
            if (self.pathIsSupportedFile(candidate)) {
                return candidate;
            }
            self.allocator.free(candidate);
        }

        return null;
    }

    fn resolveNodeModule(self: *ModuleLoaderState, module_base_name: []const u8, module_name: []const u8) !?[]u8 {
        const parsed = parseBarePackageSpecifier(module_name) orelse return null;
        if (!std.fs.path.isAbsolute(module_base_name)) {
            return null;
        }

        var current_dir = try self.allocator.dupe(u8, std.fs.path.dirname(module_base_name) orelse return null);
        defer self.allocator.free(current_dir);

        while (true) {
            const package_dir = try std.fs.path.resolve(self.allocator, &.{ current_dir, "node_modules", parsed.package_name });
            defer self.allocator.free(package_dir);

            if (self.pathIsDirectory(package_dir)) {
                const resolved = try self.resolveNodeModuleFromDirectory(package_dir, parsed.subpath);
                return resolved;
            }

            const parent = std.fs.path.dirname(current_dir) orelse break;
            if (parent.len == current_dir.len) {
                break;
            }

            const next_dir = try self.allocator.dupe(u8, parent);
            self.allocator.free(current_dir);
            current_dir = next_dir;
        }

        return null;
    }

    fn resolveNodeModuleFromDirectory(self: *ModuleLoaderState, package_dir: []const u8, subpath: []const u8) ![]u8 {
        if (subpath.len > 0) {
            if (try self.resolveNodeModuleSubpathFromExports(package_dir, subpath)) |resolved_from_exports| {
                return resolved_from_exports;
            }

            const subpath_candidate = try std.fs.path.resolve(self.allocator, &.{ package_dir, subpath });
            errdefer self.allocator.free(subpath_candidate);

            if (self.pathIsDirectory(subpath_candidate)) {
                if (try self.resolveNodeModulePackageRoot(subpath_candidate)) |resolved_dir_entry| {
                    self.allocator.free(subpath_candidate);
                    return resolved_dir_entry;
                }
            }

            return self.resolvePathWithProbing(subpath_candidate);
        }

        if (try self.resolveNodeModulePackageRoot(package_dir)) |resolved| {
            return resolved;
        }

        const index_candidate = try std.fs.path.resolve(self.allocator, &.{ package_dir, "index" });
        errdefer self.allocator.free(index_candidate);
        return self.resolvePathWithProbing(index_candidate);
    }

    fn resolveNodeModuleSubpathFromExports(self: *ModuleLoaderState, package_dir: []const u8, subpath: []const u8) !?[]u8 {
        const package_json_path = try std.fs.path.resolve(self.allocator, &.{ package_dir, "package.json" });
        defer self.allocator.free(package_json_path);

        const package_json_stat = std.Io.Dir.cwd().statFile(self.io, package_json_path, .{}) catch return null;
        if (package_json_stat.kind != .file) {
            return null;
        }

        const package_json_source = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            package_json_path,
            self.allocator,
            .limited(max_package_json_bytes),
        );
        defer self.allocator.free(package_json_source);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, package_json_source, .{});
        defer parsed.deinit();

        const root = parsed.value;
        const target = jsonResolvePackageSubpathImport(self.allocator, root, subpath) orelse return null;
        defer self.allocator.free(target);

        return self.resolveNodeModulePackageEntryPath(package_dir, target);
    }

    fn resolveNodeModulePackageRoot(self: *ModuleLoaderState, package_dir: []const u8) !?[]u8 {
        const package_json_path = try std.fs.path.resolve(self.allocator, &.{ package_dir, "package.json" });
        defer self.allocator.free(package_json_path);

        const package_json_stat = std.Io.Dir.cwd().statFile(self.io, package_json_path, .{}) catch return null;
        if (package_json_stat.kind != .file) {
            return null;
        }

        const package_json_source = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            package_json_path,
            self.allocator,
            .limited(max_package_json_bytes),
        );
        defer self.allocator.free(package_json_source);

        if (try self.resolveNodeModulePackageEntry(package_dir, package_json_source, true)) |resolved| {
            return resolved;
        }

        return null;
    }

    fn resolveNodeModulePackageEntry(
        self: *ModuleLoaderState,
        package_dir: []const u8,
        package_json_source: []const u8,
        allow_exports: bool,
    ) !?[]u8 {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, package_json_source, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) {
            return null;
        }

        if (allow_exports) {
            if (jsonResolvePackageRootImport(root)) |entry| {
                if (try self.resolveNodeModulePackageEntryPath(package_dir, entry)) |resolved| {
                    return resolved;
                }
            }
        }

        if (jsonObjectString(root.object, "main")) |entry| {
            if (try self.resolveNodeModulePackageEntryPath(package_dir, entry)) |resolved| {
                return resolved;
            }
        }

        if (jsonObjectString(root.object, "module")) |entry| {
            if (try self.resolveNodeModulePackageEntryPath(package_dir, entry)) |resolved| {
                return resolved;
            }
        }

        return null;
    }

    fn resolveNodeModulePackageEntryPath(self: *ModuleLoaderState, package_dir: []const u8, entry: []const u8) !?[]u8 {
        if (entry.len == 0) {
            return null;
        }

        const entry_path = if (std.fs.path.isAbsolute(entry))
            try std.fs.path.resolve(self.allocator, &.{entry})
        else
            try std.fs.path.resolve(self.allocator, &.{ package_dir, entry });
        errdefer self.allocator.free(entry_path);

        return self.resolvePathWithProbing(entry_path) catch |err| switch (err) {
            error.ModuleNotFound => {
                self.allocator.free(entry_path);
                return null;
            },
            else => return err,
        };
    }

    fn resolvePathAlias(self: *ModuleLoaderState, module_base_name: []const u8, module_name: []const u8) !?[]u8 {
        const loaded = try self.loadPathAliasesForModule(module_base_name);
        if (!loaded) {
            return null;
        }

        var matched_alias = false;
        for (self.path_aliases.items) |alias| {
            const resolved = self.tryResolveSingleAlias(module_name, alias.pattern, alias.target) catch |err| switch (err) {
                error.ModuleNotFound => {
                    matched_alias = true;
                    continue;
                },
                else => return err,
            };

            if (resolved) |path| {
                return path;
            }
        }

        if (matched_alias) {
            return error.ModuleNotFound;
        }

        return null;
    }

    fn tryResolveSingleAlias(self: *ModuleLoaderState, module_name: []const u8, pattern: []const u8, target: []const u8) !?[]u8 {
        const wildcard = std.mem.indexOfScalar(u8, pattern, '*');
        var wildcard_value: []const u8 = "";

        if (wildcard) |wildcard_index| {
            const pattern_prefix = pattern[0..wildcard_index];
            const pattern_suffix = pattern[wildcard_index + 1 ..];
            if (!std.mem.startsWith(u8, module_name, pattern_prefix)) {
                return null;
            }
            if (pattern_suffix.len > 0 and !std.mem.endsWith(u8, module_name, pattern_suffix)) {
                return null;
            }
            if (module_name.len < pattern_prefix.len + pattern_suffix.len) {
                return null;
            }

            wildcard_value = module_name[pattern_prefix.len .. module_name.len - pattern_suffix.len];
        } else if (!std.mem.eql(u8, module_name, pattern)) {
            return null;
        }

        const root = self.path_alias_root orelse return null;

        var mapped_target_builder: std.ArrayList(u8) = .empty;
        defer mapped_target_builder.deinit(self.allocator);

        if (std.mem.indexOfScalar(u8, target, '*')) |target_wildcard| {
            try mapped_target_builder.appendSlice(self.allocator, target[0..target_wildcard]);
            try mapped_target_builder.appendSlice(self.allocator, wildcard_value);
            try mapped_target_builder.appendSlice(self.allocator, target[target_wildcard + 1 ..]);
        } else {
            try mapped_target_builder.appendSlice(self.allocator, target);
        }

        const mapped_target = try mapped_target_builder.toOwnedSlice(self.allocator);
        defer self.allocator.free(mapped_target);

        const candidate = try std.fs.path.resolve(self.allocator, &.{ root, mapped_target });
        errdefer self.allocator.free(candidate);

        const resolved = try self.resolvePathWithProbing(candidate);
        return resolved;
    }

    fn loadPathAliasesForModule(self: *ModuleLoaderState, module_base_name: []const u8) !bool {
        const root = (try self.findTsconfigRoot(module_base_name)) orelse return false;

        if (self.path_alias_root) |existing_root| {
            if (std.mem.eql(u8, existing_root, root)) {
                self.allocator.free(root);
                return true;
            }
        }

        self.clearPathAliases();
        self.path_alias_root = root;

        const tsconfig_path = try std.fs.path.resolve(self.allocator, &.{ root, "tsconfig.json" });
        defer self.allocator.free(tsconfig_path);

        const source = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            tsconfig_path,
            self.allocator,
            .limited(max_tsconfig_bytes),
        );
        defer self.allocator.free(source);

        try self.parseTsconfigPathAliases(source);
        return true;
    }

    fn findTsconfigRoot(self: *ModuleLoaderState, module_base_name: []const u8) !?[]u8 {
        if (!std.fs.path.isAbsolute(module_base_name)) {
            return null;
        }

        var current_dir = try self.allocator.dupe(u8, std.fs.path.dirname(module_base_name) orelse return null);

        while (true) {
            if (self.directoryContainsFile(current_dir, "tsconfig.json")) {
                return current_dir;
            }

            const parent = std.fs.path.dirname(current_dir) orelse break;
            if (parent.len == current_dir.len) {
                break;
            }

            const next_dir = try self.allocator.dupe(u8, parent);
            self.allocator.free(current_dir);
            current_dir = next_dir;
        }

        self.allocator.free(current_dir);
        return null;
    }

    fn parseTsconfigPathAliases(self: *ModuleLoaderState, source: []const u8) !void {
        const paths_key_index = std.mem.indexOf(u8, source, "\"paths\"") orelse return;

        var index = paths_key_index + "\"paths\"".len;
        skipJsonTrivia(source, &index);
        if (index >= source.len or source[index] != ':') {
            return;
        }
        index += 1;

        skipJsonTrivia(source, &index);
        if (index >= source.len or source[index] != '{') {
            return;
        }

        const object_end = findMatchingJsonBrace(source, index) orelse return;

        index += 1;
        while (index < object_end) {
            skipJsonTrivia(source, &index);
            if (index >= object_end) {
                break;
            }

            if (source[index] == ',') {
                index += 1;
                continue;
            }

            if (source[index] != '"') {
                index += 1;
                continue;
            }

            const key_result = try parseJsonStringAlloc(self.allocator, source, index);
            defer self.allocator.free(key_result.value);
            index = key_result.next_index;

            skipJsonTrivia(source, &index);
            if (index >= object_end or source[index] != ':') {
                continue;
            }
            index += 1;

            skipJsonTrivia(source, &index);
            if (index >= object_end or source[index] != '[') {
                continue;
            }
            index += 1;

            while (index < object_end) {
                skipJsonTrivia(source, &index);
                if (index >= object_end) {
                    break;
                }

                if (source[index] == ']') {
                    index += 1;
                    break;
                }

                if (source[index] == ',') {
                    index += 1;
                    continue;
                }

                if (source[index] != '"') {
                    index += 1;
                    continue;
                }

                const target_result = try parseJsonStringAlloc(self.allocator, source, index);
                index = target_result.next_index;

                const pattern = try self.allocator.dupe(u8, key_result.value);
                errdefer self.allocator.free(pattern);

                try self.path_aliases.append(self.allocator, .{
                    .pattern = pattern,
                    .target = target_result.value,
                });
            }
        }
    }

    fn clearPathAliases(self: *ModuleLoaderState) void {
        if (self.path_alias_root) |root| {
            self.allocator.free(root);
            self.path_alias_root = null;
        }

        for (self.path_aliases.items) |alias| {
            self.allocator.free(alias.pattern);
            self.allocator.free(alias.target);
        }
        self.path_aliases.clearRetainingCapacity();
        self.path_aliases.deinit(self.allocator);
        self.path_aliases = .empty;
    }

    fn directoryContainsFile(self: *ModuleLoaderState, dir_path: []const u8, basename: []const u8) bool {
        const candidate = std.fs.path.resolve(self.allocator, &.{ dir_path, basename }) catch return false;
        defer self.allocator.free(candidate);

        const stat = std.Io.Dir.cwd().statFile(self.io, candidate, .{}) catch return false;
        return stat.kind == .file;
    }

    fn pathIsSupportedFile(self: *ModuleLoaderState, path: []const u8) bool {
        if (transform.loaderForPath(path) == null) {
            return false;
        }

        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return false;
        return stat.kind == .file;
    }

    fn pathIsDirectory(self: *ModuleLoaderState, path: []const u8) bool {
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return false;
        return stat.kind == .directory;
    }

    fn pathLooksCommonJs(self: *ModuleLoaderState, path: []const u8) !bool {
        if (std.mem.endsWith(u8, path, ".cjs")) {
            return true;
        }

        if (!std.mem.endsWith(u8, path, ".js")) {
            return false;
        }

        const sample = std.Io.Dir.cwd().readFileAlloc(
            self.io,
            path,
            self.allocator,
            .limited(16 * 1024),
        ) catch return false;
        defer self.allocator.free(sample);

        return isCommonJsSource(path, sample);
    }
};

const BarePackageSpecifier = struct {
    package_name: []const u8,
    subpath: []const u8,
};

fn parseBarePackageSpecifier(specifier: []const u8) ?BarePackageSpecifier {
    if (specifier.len == 0) {
        return null;
    }

    if (specifier[0] == '.' or specifier[0] == '/' or std.mem.indexOfScalar(u8, specifier, ':') != null) {
        return null;
    }

    const first_slash = std.mem.indexOfScalar(u8, specifier, '/') orelse return .{
        .package_name = specifier,
        .subpath = "",
    };

    if (specifier[0] == '@') {
        const second_slash = std.mem.indexOfScalarPos(u8, specifier, first_slash + 1, '/') orelse return .{
            .package_name = specifier,
            .subpath = "",
        };
        return .{
            .package_name = specifier[0..second_slash],
            .subpath = specifier[second_slash + 1 ..],
        };
    }

    return .{
        .package_name = specifier[0..first_slash],
        .subpath = specifier[first_slash + 1 ..],
    };
}

fn isBarePackageSpecifier(specifier: []const u8) bool {
    if (specifier.len == 0) {
        return false;
    }

    if (isRelativeSpecifier(specifier) or std.fs.path.isAbsolute(specifier)) {
        return false;
    }

    if (std.mem.startsWith(u8, specifier, "~/") or std.mem.startsWith(u8, specifier, "@/")) {
        return false;
    }

    return true;
}

fn jsonObjectString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .string => |text| text,
        else => null,
    };
}

fn jsonResolvePackageRootImport(root: std.json.Value) ?[]const u8 {
    if (root != .object) {
        return null;
    }

    const exports_value = root.object.get("exports") orelse return null;
    return jsonExtractImportTarget(exports_value);
}

fn jsonResolvePackageSubpathImport(allocator: Allocator, root: std.json.Value, subpath: []const u8) ?[]u8 {
    if (root != .object) {
        return null;
    }

    const exports_value = root.object.get("exports") orelse return null;
    if (exports_value != .object) {
        return null;
    }

    const exports_object = exports_value.object;
    const exact_key = std.fmt.allocPrint(allocator, "./{s}", .{subpath}) catch return null;
    defer allocator.free(exact_key);

    if (exports_object.get(exact_key)) |exact_export| {
        if (jsonExtractImportTarget(exact_export)) |target| {
            return allocator.dupe(u8, target) catch return null;
        }
    }

    var iterator = exports_object.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        if (!std.mem.startsWith(u8, key, "./")) {
            continue;
        }

        const key_pattern = key[2..];
        const wildcard_index = std.mem.indexOfScalar(u8, key_pattern, '*') orelse continue;
        const key_pattern_prefix = key_pattern[0..wildcard_index];
        const key_pattern_suffix = key_pattern[wildcard_index + 1 ..];

        if (!std.mem.startsWith(u8, subpath, key_pattern_prefix)) {
            continue;
        }

        if (key_pattern_suffix.len > 0 and !std.mem.endsWith(u8, subpath, key_pattern_suffix)) {
            continue;
        }

        if (subpath.len < key_pattern_prefix.len + key_pattern_suffix.len) {
            continue;
        }

        const wildcard_value = subpath[key_pattern_prefix.len .. subpath.len - key_pattern_suffix.len];
        const target = jsonExtractImportTarget(entry.value_ptr.*) orelse continue;
        if (std.mem.indexOfScalar(u8, target, '*')) |target_wildcard_index| {
            var builder: std.ArrayList(u8) = .empty;
            defer builder.deinit(allocator);

            builder.appendSlice(allocator, target[0..target_wildcard_index]) catch return null;
            builder.appendSlice(allocator, wildcard_value) catch return null;
            builder.appendSlice(allocator, target[target_wildcard_index + 1 ..]) catch return null;
            return builder.toOwnedSlice(allocator) catch return null;
        }

        return allocator.dupe(u8, target) catch return null;
    }

    return null;
}

fn jsonExtractImportTarget(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        .object => |object| blk: {
            if (object.get(".")) |root_export| {
                if (jsonExtractImportTarget(root_export)) |target| {
                    break :blk target;
                }
            }

            if (object.get("import")) |import_export| {
                if (jsonExtractImportTarget(import_export)) |target| {
                    break :blk target;
                }
            }

            if (object.get("default")) |default_export| {
                if (jsonExtractImportTarget(default_export)) |target| {
                    break :blk target;
                }
            }

            if (object.get("require")) |require_export| {
                if (jsonExtractImportTarget(require_export)) |target| {
                    break :blk target;
                }
            }

            break :blk null;
        },
        .array => |array| blk: {
            for (array.items) |item| {
                if (jsonExtractImportTarget(item)) |target| {
                    break :blk target;
                }
            }
            break :blk null;
        },
        else => null,
    };
}

const JsonStringResult = struct {
    value: []u8,
    next_index: usize,
};

fn parseJsonStringAlloc(allocator: Allocator, source: []const u8, start_index: usize) !JsonStringResult {
    if (start_index >= source.len or source[start_index] != '"') {
        return error.InvalidJsonString;
    }

    var index = start_index + 1;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    while (index < source.len) {
        const ch = source[index];
        if (ch == '"') {
            return .{
                .value = try output.toOwnedSlice(allocator),
                .next_index = index + 1,
            };
        }

        if (ch == '\\') {
            if (index + 1 >= source.len) {
                return error.InvalidJsonString;
            }

            const escaped = source[index + 1];
            const decoded = switch (escaped) {
                '"' => '"',
                '\\' => '\\',
                '/' => '/',
                'b' => 0x08,
                'f' => 0x0c,
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => escaped,
            };

            try output.append(allocator, decoded);
            index += 2;
            continue;
        }

        try output.append(allocator, ch);
        index += 1;
    }

    return error.InvalidJsonString;
}

fn skipJsonTrivia(source: []const u8, index: *usize) void {
    while (index.* < source.len) {
        const ch = source[index.*];
        if (std.ascii.isWhitespace(ch)) {
            index.* += 1;
            continue;
        }

        if (ch == '/' and index.* + 1 < source.len and source[index.* + 1] == '/') {
            index.* += 2;
            while (index.* < source.len and source[index.*] != '\n') {
                index.* += 1;
            }
            continue;
        }

        if (ch == '/' and index.* + 1 < source.len and source[index.* + 1] == '*') {
            index.* += 2;
            while (index.* + 1 < source.len) {
                if (source[index.*] == '*' and source[index.* + 1] == '/') {
                    index.* += 2;
                    break;
                }
                index.* += 1;
            }
            continue;
        }

        break;
    }
}

fn findMatchingJsonBrace(source: []const u8, open_brace_index: usize) ?usize {
    if (open_brace_index >= source.len or source[open_brace_index] != '{') {
        return null;
    }

    var index = open_brace_index;
    var depth: usize = 0;
    var in_string = false;
    var escaped = false;

    while (index < source.len) : (index += 1) {
        const ch = source[index];

        if (in_string) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if (ch == '"') {
                in_string = false;
            }
            continue;
        }

        if (ch == '"') {
            in_string = true;
            continue;
        }

        if (ch == '/' and index + 1 < source.len and source[index + 1] == '/') {
            index += 2;
            while (index < source.len and source[index] != '\n') : (index += 1) {}
            continue;
        }

        if (ch == '/' and index + 1 < source.len and source[index + 1] == '*') {
            index += 2;
            while (index + 1 < source.len) : (index += 1) {
                if (source[index] == '*' and source[index + 1] == '/') {
                    index += 1;
                    break;
                }
            }
            continue;
        }

        if (ch == '{') {
            depth += 1;
            continue;
        }

        if (ch == '}') {
            if (depth == 0) {
                return null;
            }

            depth -= 1;
            if (depth == 0) {
                return index;
            }
        }
    }

    return null;
}

const ParsedLiteral = struct {
    specifier: []const u8,
    next_index: usize,
};

fn collectEsmSpecifiers(allocator: Allocator, source: []const u8) ![]const []u8 {
    var specifiers: std.ArrayList([]u8) = .empty;
    errdefer {
        for (specifiers.items) |specifier| {
            allocator.free(specifier);
        }
        specifiers.deinit(allocator);
    }

    var dedup = std.StringHashMap(void).init(allocator);
    defer dedup.deinit();

    var cursor: usize = 0;
    while (cursor < source.len) {
        const current = source[cursor];

        if (current == '/') {
            if (cursor + 1 < source.len and source[cursor + 1] == '/') {
                cursor = skipLineComment(source, cursor);
                continue;
            }
            if (cursor + 1 < source.len and source[cursor + 1] == '*') {
                cursor = skipBlockComment(source, cursor);
                continue;
            }
        }

        if (current == '\'' or current == '"' or current == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        if (hasWordAt(source, cursor, "import")) {
            cursor = try parseImportSpecifier(allocator, source, cursor, &specifiers, &dedup);
            continue;
        }

        if (hasWordAt(source, cursor, "export")) {
            cursor = try parseExportSpecifier(allocator, source, cursor, &specifiers, &dedup);
            continue;
        }

        cursor += 1;
    }

    return specifiers.toOwnedSlice(allocator);
}

fn collectCommonJsSpecifiers(allocator: Allocator, source: []const u8) ![]const []u8 {
    var specifiers: std.ArrayList([]u8) = .empty;
    errdefer {
        for (specifiers.items) |specifier| {
            allocator.free(specifier);
        }
        specifiers.deinit(allocator);
    }

    var dedup = std.StringHashMap(void).init(allocator);
    defer dedup.deinit();

    var cursor: usize = 0;
    while (cursor < source.len) {
        const current = source[cursor];

        if (current == '/') {
            if (cursor + 1 < source.len and source[cursor + 1] == '/') {
                cursor = skipLineComment(source, cursor);
                continue;
            }
            if (cursor + 1 < source.len and source[cursor + 1] == '*') {
                cursor = skipBlockComment(source, cursor);
                continue;
            }
        }

        if (current == '\'' or current == '"' or current == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        if (hasWordAt(source, cursor, "require")) {
            var value_index = cursor + "require".len;
            skipTrivia(source, &value_index);
            if (value_index < source.len and source[value_index] == '(') {
                value_index += 1;
                skipTrivia(source, &value_index);
                if (parseQuotedSpecifier(source, value_index)) |literal| {
                    try appendSpecifier(allocator, &specifiers, &dedup, literal.specifier);
                    cursor = literal.next_index;
                    continue;
                }
            }
        }

        cursor += 1;
    }

    return specifiers.toOwnedSlice(allocator);
}

fn collectCommonJsExportNamesFromSource(
    allocator: Allocator,
    source: []const u8,
    names: *std.ArrayList([]u8),
    dedup: *std.StringHashMap(void),
) !void {
    var cursor: usize = 0;
    while (cursor < source.len) {
        if (source[cursor] == '/' and cursor + 1 < source.len and source[cursor + 1] == '/') {
            cursor = skipLineComment(source, cursor);
            continue;
        }
        if (source[cursor] == '/' and cursor + 1 < source.len and source[cursor + 1] == '*') {
            cursor = skipBlockComment(source, cursor);
            continue;
        }
        if (source[cursor] == '\'' or source[cursor] == '"' or source[cursor] == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        if (std.mem.startsWith(u8, source[cursor..], "exports.")) {
            const start = cursor + "exports.".len;
            var end = start;
            while (end < source.len and isIdentifierChar(source[end])) : (end += 1) {}
            if (end > start) {
                const name = source[start..end];
                if (!std.mem.eql(u8, name, "default") and !std.mem.eql(u8, name, "__esModule")) {
                    try appendSpecifier(allocator, names, dedup, name);
                }
                cursor = end;
                continue;
            }
        }

        if (std.mem.startsWith(u8, source[cursor..], "module.exports.")) {
            const start = cursor + "module.exports.".len;
            var end = start;
            while (end < source.len and isIdentifierChar(source[end])) : (end += 1) {}
            if (end > start) {
                const name = source[start..end];
                if (!std.mem.eql(u8, name, "default") and !std.mem.eql(u8, name, "__esModule")) {
                    try appendSpecifier(allocator, names, dedup, name);
                }
                cursor = end;
                continue;
            }
        }

        cursor += 1;
    }
}

fn parseImportSpecifier(
    allocator: Allocator,
    source: []const u8,
    start_index: usize,
    specifiers: *std.ArrayList([]u8),
    dedup: *std.StringHashMap(void),
) !usize {
    var cursor = start_index + "import".len;
    skipTrivia(source, &cursor);
    if (cursor >= source.len) {
        return cursor;
    }

    if (source[cursor] == '.') {
        return cursor + 1;
    }

    if (hasWordAt(source, cursor, "type")) {
        return skipStatement(source, cursor + "type".len);
    }

    if (parseQuotedSpecifier(source, cursor)) |literal| {
        try appendSpecifier(allocator, specifiers, dedup, literal.specifier);
        return literal.next_index;
    }

    if (source[cursor] == '(') {
        cursor += 1;
        skipTrivia(source, &cursor);
        if (parseQuotedSpecifier(source, cursor)) |literal| {
            try appendSpecifier(allocator, specifiers, dedup, literal.specifier);
            return literal.next_index;
        }
        return cursor;
    }

    while (cursor < source.len) {
        const current = source[cursor];

        if (current == ';') {
            return cursor + 1;
        }

        if (current == '/') {
            if (cursor + 1 < source.len and source[cursor + 1] == '/') {
                cursor = skipLineComment(source, cursor);
                continue;
            }
            if (cursor + 1 < source.len and source[cursor + 1] == '*') {
                cursor = skipBlockComment(source, cursor);
                continue;
            }
        }

        if (current == '\'' or current == '"' or current == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        if (hasWordAt(source, cursor, "from")) {
            var value_index = cursor + "from".len;
            skipTrivia(source, &value_index);
            if (parseQuotedSpecifier(source, value_index)) |literal| {
                try appendSpecifier(allocator, specifiers, dedup, literal.specifier);
                return literal.next_index;
            }
        }

        cursor += 1;
    }

    return cursor;
}

fn parseExportSpecifier(
    allocator: Allocator,
    source: []const u8,
    start_index: usize,
    specifiers: *std.ArrayList([]u8),
    dedup: *std.StringHashMap(void),
) !usize {
    var cursor = start_index + "export".len;
    skipTrivia(source, &cursor);
    if (hasWordAt(source, cursor, "type")) {
        return skipStatement(source, cursor + "type".len);
    }

    while (cursor < source.len) {
        const current = source[cursor];

        if (current == ';') {
            return cursor + 1;
        }

        if (current == '/') {
            if (cursor + 1 < source.len and source[cursor + 1] == '/') {
                cursor = skipLineComment(source, cursor);
                continue;
            }
            if (cursor + 1 < source.len and source[cursor + 1] == '*') {
                cursor = skipBlockComment(source, cursor);
                continue;
            }
        }

        if (current == '\'' or current == '"' or current == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        if (hasWordAt(source, cursor, "from")) {
            var value_index = cursor + "from".len;
            skipTrivia(source, &value_index);
            if (parseQuotedSpecifier(source, value_index)) |literal| {
                try appendSpecifier(allocator, specifiers, dedup, literal.specifier);
                return literal.next_index;
            }
        }

        cursor += 1;
    }

    return cursor;
}

fn skipStatement(source: []const u8, start_index: usize) usize {
    var cursor = start_index;
    while (cursor < source.len) {
        const current = source[cursor];

        if (current == ';') {
            return cursor + 1;
        }

        if (current == '/') {
            if (cursor + 1 < source.len and source[cursor + 1] == '/') {
                cursor = skipLineComment(source, cursor);
                continue;
            }
            if (cursor + 1 < source.len and source[cursor + 1] == '*') {
                cursor = skipBlockComment(source, cursor);
                continue;
            }
        }

        if (current == '\'' or current == '"' or current == '`') {
            cursor = skipQuotedLiteral(source, cursor);
            continue;
        }

        cursor += 1;
    }

    return cursor;
}

fn appendSpecifier(
    allocator: Allocator,
    specifiers: *std.ArrayList([]u8),
    dedup: *std.StringHashMap(void),
    specifier: []const u8,
) !void {
    if (specifier.len == 0 or dedup.contains(specifier)) {
        return;
    }

    const owned = try allocator.dupe(u8, specifier);
    errdefer allocator.free(owned);

    try dedup.put(owned, {});
    try specifiers.append(allocator, owned);
}

fn parseQuotedSpecifier(source: []const u8, start_index: usize) ?ParsedLiteral {
    if (start_index >= source.len) {
        return null;
    }

    const quote = source[start_index];
    if (quote != '\'' and quote != '"') {
        return null;
    }

    var index = start_index + 1;
    while (index < source.len) {
        const current = source[index];
        if (current == '\\') {
            if (index + 1 >= source.len) {
                return null;
            }
            index += 2;
            continue;
        }

        if (current == quote) {
            return .{
                .specifier = source[start_index + 1 .. index],
                .next_index = index + 1,
            };
        }

        index += 1;
    }

    return null;
}

fn skipTrivia(source: []const u8, index: *usize) void {
    while (index.* < source.len) {
        const current = source[index.*];
        if (std.ascii.isWhitespace(current)) {
            index.* += 1;
            continue;
        }

        if (current == '/' and index.* + 1 < source.len and source[index.* + 1] == '/') {
            index.* = skipLineComment(source, index.*);
            continue;
        }

        if (current == '/' and index.* + 1 < source.len and source[index.* + 1] == '*') {
            index.* = skipBlockComment(source, index.*);
            continue;
        }

        break;
    }
}

fn skipLineComment(source: []const u8, start_index: usize) usize {
    var index = start_index + 2;
    while (index < source.len and source[index] != '\n') {
        index += 1;
    }
    return index;
}

fn skipBlockComment(source: []const u8, start_index: usize) usize {
    var index = start_index + 2;
    while (index + 1 < source.len) {
        if (source[index] == '*' and source[index + 1] == '/') {
            return index + 2;
        }
        index += 1;
    }
    return source.len;
}

fn skipQuotedLiteral(source: []const u8, start_index: usize) usize {
    const quote = source[start_index];
    var index = start_index + 1;
    while (index < source.len) {
        const current = source[index];
        if (current == '\\') {
            if (index + 1 >= source.len) {
                return source.len;
            }
            index += 2;
            continue;
        }

        if (current == quote) {
            return index + 1;
        }

        index += 1;
    }
    return source.len;
}

fn hasWordAt(source: []const u8, index: usize, word: []const u8) bool {
    if (index + word.len > source.len) {
        return false;
    }

    if (!std.mem.eql(u8, source[index .. index + word.len], word)) {
        return false;
    }

    if (index > 0 and isIdentifierChar(source[index - 1])) {
        return false;
    }

    const end_index = index + word.len;
    if (end_index < source.len and isIdentifierChar(source[end_index])) {
        return false;
    }

    return true;
}

fn isIdentifierChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$';
}

fn appendFmt(allocator: Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

pub fn runFiles(allocator: Allocator, io: std.Io, paths: []const []u8, setup_paths: []const []const u8) !Summary {
    var results: std.ArrayList(FileResult) = .empty;
    errdefer {
        for (results.items) |*item| {
            item.deinit(allocator);
        }
        results.deinit(allocator);
    }

    var totals = Summary{
        .files = &.{},
        .total_passed = 0,
        .total_failed = 0,
        .total_skipped = 0,
        .total_timed_out = 0,
        .total_collection_errors = 0,
    };

    for (paths) |path| {
        var file_result = try runSingleFile(allocator, io, path, setup_paths);
        errdefer file_result.deinit(allocator);

        totals.total_passed += file_result.passed;
        totals.total_failed += file_result.failed;
        totals.total_skipped += file_result.skipped;
        totals.total_timed_out += file_result.timed_out;
        totals.total_collection_errors += file_result.collection_errors;

        try results.append(allocator, file_result);
    }

    totals.files = try results.toOwnedSlice(allocator);
    return totals;
}

fn runSingleFile(allocator: Allocator, io: std.Io, path: []const u8, setup_paths: []const []const u8) !FileResult {
    const entry_module_id = canonicalizePath(allocator, io, path) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };
    defer allocator.free(entry_module_id);

    var setup_module_ids: std.ArrayList([]u8) = .empty;
    defer {
        for (setup_module_ids.items) |setup_module_id| {
            allocator.free(setup_module_id);
        }
        setup_module_ids.deinit(allocator);
    }

    for (setup_paths) |setup_path| {
        const setup_module_id = canonicalizePath(allocator, io, setup_path) catch |err| {
            return collectionFailureFromError(allocator, path, "collection failed", err);
        };
        setup_module_ids.append(allocator, setup_module_id) catch |err| {
            allocator.free(setup_module_id);
            return err;
        };
    }

    var vm = try Runtime.init(allocator, io);
    defer vm.deinit();

    vm.evalScript(
        "<zig-runner-test-api>",
        "globalThis.mock = globalThis.__zigMock; globalThis.spyOn = globalThis.__zigSpyOn; globalThis.__zigInstallBunTestApi();",
    ) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to initialize runner test API", err, &vm);
    };

    var module_loader_state = ModuleLoaderState.init(allocator, io);
    defer module_loader_state.deinit();
    module_loader_state.runtime = &vm;

    vm.setModuleLoaderFunc(ModuleLoaderState, &module_loader_state, moduleNormalize, moduleLoad);

    const process_root = if (setup_module_ids.items.len > 0)
        (std.fs.path.dirname(setup_module_ids.items[0]) orelse std.fs.path.dirname(entry_module_id) orelse ".")
    else
        (std.fs.path.dirname(entry_module_id) orelse ".");
    evalRunnerProcessGlobals(allocator, &vm, process_root, entry_module_id) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to initialize process globals", err, &vm);
    };

    for (setup_module_ids.items) |setup_module_id| {
        const setup_source = module_loader_state.loadModuleSource(setup_module_id) catch |err| {
            return collectionFailureFromError(allocator, path, "collection failed", err);
        };
        defer allocator.free(setup_source);

        vm.evalScript("<zig-setup-dom-probe-begin>", setup_dom_probe_begin_source) catch |err| {
            return failureFromRuntimeException(allocator, path, "failed to prepare setup environment", err, &vm);
        };

        vm.evalModule(setup_module_id, setup_source) catch |err| {
            vm.evalScript("<zig-setup-dom-probe-end>", setup_dom_probe_end_source) catch {};
            return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
        };
        vm.evalScript("<zig-setup-dom-probe-end>", setup_dom_probe_end_source) catch |err| {
            return failureFromRuntimeException(allocator, path, "failed to restore setup environment", err, &vm);
        };

        while (vm.isJobPending()) {
            _ = vm.executePendingJob() catch |err| {
                return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
            };
        }
    }

    module_loader_state.syncMockModulesFromRuntime(&vm) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };

    const entry_source = module_loader_state.loadModuleSource(entry_module_id) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };
    defer allocator.free(entry_source);

    vm.evalModule(entry_module_id, entry_source) catch |err| {
        return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
    };

    while (vm.isJobPending()) {
        _ = vm.executePendingJob() catch |err| {
            return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
        };
    }

    vm.evalScript("<zig-collection-flush>", collection_flush_source) catch |err| {
        return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
    };

    const flush_timeout_ms: i64 = 1_000;
    const flush_start_ts = std.Io.Clock.Timestamp.now(io, .awake);
    while (!(vm.getGlobalBool("__zigCollectionFlushDone") catch false)) {
        const flush_elapsed_ms = flush_start_ts.untilNow(io).raw.toMilliseconds();
        if (flush_elapsed_ms > flush_timeout_ms) {
            return .{
                .path = try allocator.dupe(u8, path),
                .passed = 0,
                .failed = 0,
                .skipped = 0,
                .timed_out = 0,
                .collection_errors = 1,
                .failure_report = null,
                .collection_report = try allocator.dupe(u8, "collection failed: microtask flush timed out"),
            };
        }

        if (vm.isJobPending()) {
            _ = vm.executePendingJob() catch |err| {
                return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
            };
        }
    }

    while (vm.isJobPending()) {
        _ = vm.executePendingJob() catch |err| {
            return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
        };
    }

    vm.evalScript("<zig-runner-bootstrap>", run_bootstrap_source) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to start file execution", err, &vm);
    };

    const run_timeout_ms: i64 = 30_000;
    const start_ts = std.Io.Clock.Timestamp.now(io, .awake);
    while (!(vm.getGlobalBool("__zigDone") catch false)) {
        const elapsed_ms = start_ts.untilNow(io).raw.toMilliseconds();
        if (elapsed_ms > run_timeout_ms) {
            return .{
                .path = try allocator.dupe(u8, path),
                .passed = 0,
                .failed = 0,
                .skipped = 0,
                .timed_out = 1,
                .collection_errors = 0,
                .failure_report = try allocator.dupe(u8, "Runner timed out while waiting for async jobs."),
                .collection_report = null,
            };
        }

        if (vm.isJobPending()) {
            _ = vm.executePendingJob() catch |err| {
                return failureFromRuntimeException(allocator, path, "job execution failed", err, &vm);
            };
            continue;
        }

        return .{
            .path = try allocator.dupe(u8, path),
            .passed = 0,
            .failed = 1,
            .skipped = 0,
            .timed_out = 0,
            .collection_errors = 0,
            .failure_report = try allocator.dupe(u8, "Runner stalled with unresolved async work."),
            .collection_report = null,
        };
    }

    const run_error = vm.getGlobalStringDup("__zigRunError") catch try allocator.dupe(u8, "");
    if (run_error.len > 0) {
        return .{
            .path = try allocator.dupe(u8, path),
            .passed = 0,
            .failed = 1,
            .skipped = 0,
            .timed_out = 0,
            .collection_errors = 0,
            .failure_report = run_error,
            .collection_report = null,
        };
    }
    allocator.free(run_error);

    const passed_i32 = vm.getGlobalInt32("__zigPassed") catch 0;
    const failed_i32 = vm.getGlobalInt32("__zigFailed") catch 0;
    const skipped_i32 = vm.getGlobalInt32("__zigSkipped") catch 0;
    const timed_out_i32 = vm.getGlobalInt32("__zigTimedOut") catch 0;
    const collection_errors_i32 = vm.getGlobalInt32("__zigCollectionErrors") catch 0;
    const registered_tests_i32 = vm.getGlobalInt32("__zigRegisteredTests") catch 0;
    const only_mode = vm.getGlobalBool("__zigOnlyMode") catch false;
    const has_runnable = vm.getGlobalBool("__zigHasRunnable") catch false;

    if (
        passed_i32 == 0 and
        failed_i32 == 0 and
        skipped_i32 == 0 and
        timed_out_i32 == 0 and
        collection_errors_i32 == 0
    ) {
        const diagnostic = try std.fmt.allocPrint(
            allocator,
            "collection failed: no tests executed (registered={d}, onlyMode={}, hasRunnable={})",
            .{ registered_tests_i32, only_mode, has_runnable },
        );
        return .{
            .path = try allocator.dupe(u8, path),
            .passed = 0,
            .failed = 0,
            .skipped = 0,
            .timed_out = 0,
            .collection_errors = 1,
            .failure_report = null,
            .collection_report = diagnostic,
        };
    }

    const failures_text = vm.getGlobalStringDup("__zigFailuresText") catch try allocator.dupe(u8, "");
    const collection_text = vm.getGlobalStringDup("__zigCollectionText") catch try allocator.dupe(u8, "");

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = @intCast(@max(passed_i32, 0)),
        .failed = @intCast(@max(failed_i32, 0)),
        .skipped = @intCast(@max(skipped_i32, 0)),
        .timed_out = @intCast(@max(timed_out_i32, 0)),
        .collection_errors = @intCast(@max(collection_errors_i32, 0)),
        .failure_report = if (failures_text.len > 0) failures_text else blk: {
            allocator.free(failures_text);
            break :blk null;
        },
        .collection_report = if (collection_text.len > 0) collection_text else blk: {
            allocator.free(collection_text);
            break :blk null;
        },
    };
}

fn evalRunnerProcessGlobals(allocator: Allocator, vm: *Runtime, root: []const u8, entry_path: []const u8) !void {
    const escaped_root = try escapeProcessJsSingleQuotedString(allocator, root);
    defer allocator.free(escaped_root);
    const escaped_entry = try escapeProcessJsSingleQuotedString(allocator, entry_path);
    defer allocator.free(escaped_entry);

    const source = try std.mem.concat(allocator, u8, &.{
        "globalThis.process = globalThis.process || {};",
        "globalThis.process.env = globalThis.process.env || {};",
        "globalThis.process.cwd = function cwd() { return '",
        escaped_root,
        "'; };",
        "globalThis.process.argv = ['zig-dom', 'test', '",
        escaped_entry,
        "'];",
    });
    defer allocator.free(source);

    try vm.evalScript("<zig-process-globals>", source);
}

fn escapeProcessJsSingleQuotedString(allocator: Allocator, text: []const u8) ![]u8 {
    var builder: std.ArrayList(u8) = .empty;
    errdefer builder.deinit(allocator);

    for (text) |ch| {
        switch (ch) {
            '\\' => try builder.appendSlice(allocator, "\\\\"),
            '\'' => try builder.appendSlice(allocator, "\\'"),
            '\n' => try builder.appendSlice(allocator, "\\n"),
            '\r' => try builder.appendSlice(allocator, "\\r"),
            '\t' => try builder.appendSlice(allocator, "\\t"),
            else => try builder.append(allocator, ch),
        }
    }

    return builder.toOwnedSlice(allocator);
}

fn moduleNormalize(
    state_opt: ?*ModuleLoaderState,
    ctx: *ModuleContext,
    module_base_name: [:0]const u8,
    module_name: [:0]const u8,
) ?[*:0]u8 {
    const state = state_opt orelse return null;

    const resolved = state.normalizeSpecifier(module_base_name, module_name) catch {
        _ = quickjs.c.JS_ThrowReferenceError(
            ctx.cval(),
            "module resolution failed: %s (from %s)",
            module_name.ptr,
            module_base_name.ptr,
        );
        return null;
    };
    defer state.allocator.free(resolved);

    return allocJsCString(ctx, resolved) orelse blk: {
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        break :blk null;
    };
}

fn moduleLoad(
    state_opt: ?*ModuleLoaderState,
    ctx: *ModuleContext,
    module_name: [:0]const u8,
) ?*ModuleDef {
    const state = state_opt orelse return null;
    const module_id: []const u8 = module_name;

    if (state.loaded_modules.get(module_id)) |existing| {
        return existing;
    }

    const source = state.loadModuleSource(module_id) catch |err| {
        _ = quickjs.c.JS_ThrowReferenceError(
            ctx.cval(),
            "module loading failed: %s (%s)",
            module_name.ptr,
            @errorName(err).ptr,
        );
        return null;
    };
    defer state.allocator.free(source);

    const source_z = state.allocator.dupeZ(u8, source) catch {
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        return null;
    };
    defer state.allocator.free(source_z);

    const compiled = ctx.eval(source_z[0..source.len], module_name, .{ .type = .module, .compile_only = true });
    if (compiled.isException()) {
        return null;
    }
    defer compiled.deinit(ctx);

    const module_ptr_any = quickjs.c.JS_VALUE_GET_PTR(compiled.cval()) orelse {
        _ = quickjs.c.JS_ThrowReferenceError(ctx.cval(), "compiled module missing");
        return null;
    };
    const module_ptr: *ModuleDef = @ptrCast(@alignCast(module_ptr_any));

    const key = state.allocator.dupe(u8, module_id) catch {
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        return null;
    };

    state.loaded_modules.put(key, module_ptr) catch {
        state.allocator.free(key);
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        return null;
    };

    return module_ptr;
}

fn allocJsCString(ctx: *ModuleContext, text: []const u8) ?[*:0]u8 {
    const raw = quickjs.c.js_malloc(ctx.cval(), text.len + 1) orelse return null;
    const bytes: [*]u8 = @ptrCast(raw);
    @memcpy(bytes[0..text.len], text);
    bytes[text.len] = 0;
    return @ptrCast(bytes);
}

fn builtInModuleSource(module_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, module_name, bun_specifier)) {
        return bun_shim_source;
    }

    if (std.mem.eql(u8, module_name, bun_test_specifier)) {
        return bun_test_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_url_specifier) or std.mem.eql(u8, module_name, node_url_colon_specifier)) {
        return node_url_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_fs_specifier) or std.mem.eql(u8, module_name, node_fs_colon_specifier)) {
        return node_fs_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_path_specifier) or std.mem.eql(u8, module_name, node_path_colon_specifier)) {
        return node_path_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_util_specifier) or std.mem.eql(u8, module_name, node_util_colon_specifier)) {
        return node_util_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_buffer_specifier) or std.mem.eql(u8, module_name, node_buffer_colon_specifier)) {
        return node_buffer_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_crypto_specifier) or std.mem.eql(u8, module_name, node_crypto_colon_specifier)) {
        return node_crypto_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_http_specifier) or std.mem.eql(u8, module_name, node_http_colon_specifier)) {
        return node_http_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_https_specifier) or std.mem.eql(u8, module_name, node_https_colon_specifier)) {
        return node_https_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_net_specifier) or std.mem.eql(u8, module_name, node_net_colon_specifier)) {
        return node_net_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_zlib_specifier) or std.mem.eql(u8, module_name, node_zlib_colon_specifier)) {
        return node_zlib_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_child_process_specifier) or std.mem.eql(u8, module_name, node_child_process_colon_specifier)) {
        return node_child_process_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_stream_specifier) or std.mem.eql(u8, module_name, node_stream_colon_specifier)) {
        return node_stream_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_stream_web_specifier) or std.mem.eql(u8, module_name, node_stream_web_colon_specifier)) {
        return node_stream_web_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_vm_specifier) or std.mem.eql(u8, module_name, node_vm_colon_specifier)) {
        return node_vm_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_perf_hooks_colon_specifier)) {
        return node_perf_hooks_shim_source;
    }

    if (std.mem.eql(u8, module_name, zig_dom_specifier) or std.mem.eql(u8, module_name, zig_dom_index_specifier)) {
        return zig_dom_index_shim_source;
    }

    if (
        std.mem.eql(u8, module_name, zig_dom_global_registrator_specifier) or
        std.mem.eql(u8, module_name, zig_dom_global_registrar_specifier)
    ) {
        return zig_dom_global_registrator_shim_source;
    }

    return null;
}

fn isMockModuleId(module_id: []const u8) bool {
    return std.mem.startsWith(u8, module_id, "__zig_mock__/");
}

fn isRelativeSpecifier(specifier: []const u8) bool {
    return std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../");
}

fn isCommonJsSource(module_id: []const u8, source: []const u8) bool {
    if (std.mem.endsWith(u8, module_id, ".cjs")) {
        return true;
    }

    if (!std.mem.endsWith(u8, module_id, ".js")) {
        return false;
    }

    if (
        std.mem.indexOf(u8, source, "module.exports") != null or
        std.mem.indexOf(u8, source, "exports.") != null or
        std.mem.indexOf(u8, source, "Object.defineProperty(exports") != null or
        std.mem.indexOf(u8, source, "Object.defineProperty(module") != null
    ) {
        return true;
    }

    if (std.mem.indexOf(u8, source, "require(") == null) {
        return false;
    }

    return std.mem.indexOf(u8, source, "import ") == null and std.mem.indexOf(u8, source, "export ") == null;
}

fn looksLikeJsxSource(source: []const u8) bool {
    return std.mem.indexOf(u8, source, "<") != null and
        (std.mem.indexOf(u8, source, "/>") != null or std.mem.indexOf(u8, source, "</") != null);
}

fn onLoadTransformExtension(loader: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, loader, "ts")) {
        return ".ts";
    }

    if (std.mem.eql(u8, loader, "tsx")) {
        return ".tsx";
    }

    if (std.mem.eql(u8, loader, "jsx")) {
        return ".jsx";
    }

    return null;
}

fn canonicalizePath(allocator: Allocator, io: std.Io, path: []const u8) ![]u8 {
    const resolved = try std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator);
    defer allocator.free(resolved);
    return allocator.dupe(u8, resolved[0..resolved.len]);
}

fn failureFromRuntimeException(
    allocator: Allocator,
    path: []const u8,
    context: []const u8,
    runtime_error: anyerror,
    vm: *Runtime,
) !FileResult {
    var exception: ?Exception = null;
    if (runtime_error == error.EvaluationFailed or runtime_error == error.JobExecutionFailed) {
        exception = vm.takeException() catch null;
    }
    defer if (exception) |exc| exc.deinit(allocator);

    const message = if (exception) |exc|
        try formatExceptionText(allocator, context, exc)
    else
        try std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, @errorName(runtime_error) });

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = 0,
        .failed = 1,
        .skipped = 0,
        .timed_out = 0,
        .collection_errors = 0,
        .failure_report = message,
        .collection_report = null,
    };
}

fn collectionFailureFromRuntimeException(
    allocator: Allocator,
    path: []const u8,
    context: []const u8,
    runtime_error: anyerror,
    vm: *Runtime,
) !FileResult {
    var exception: ?Exception = null;
    if (runtime_error == error.EvaluationFailed or runtime_error == error.JobExecutionFailed) {
        exception = vm.takeException() catch null;
    }
    defer if (exception) |exc| exc.deinit(allocator);

    const message = if (exception) |exc|
        try formatExceptionText(allocator, context, exc)
    else
        try std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, @errorName(runtime_error) });

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = 0,
        .failed = 0,
        .skipped = 0,
        .timed_out = 0,
        .collection_errors = 1,
        .failure_report = null,
        .collection_report = message,
    };
}

fn collectionFailureFromError(
    allocator: Allocator,
    path: []const u8,
    context: []const u8,
    err: anyerror,
) !FileResult {
    const message = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, @errorName(err) });

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = 0,
        .failed = 0,
        .skipped = 0,
        .timed_out = 0,
        .collection_errors = 1,
        .failure_report = null,
        .collection_report = message,
    };
}

fn formatExceptionText(allocator: Allocator, context: []const u8, exception: Exception) ![]u8 {
    if (exception.stack) |stack| {
        return std.fmt.allocPrint(allocator, "{s}: {s}\n{s}", .{ context, exception.message, stack });
    }

    return std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, exception.message });
}

test "isRelativeSpecifier detects relative paths" {
    try std.testing.expect(isRelativeSpecifier("./foo"));
    try std.testing.expect(isRelativeSpecifier("../foo"));
    try std.testing.expect(!isRelativeSpecifier("foo"));
}

test "shim sources resolve built-ins and fallback shims" {
    try std.testing.expect(builtInModuleSource("bun") != null);
    try std.testing.expect(builtInModuleSource("bun:test") != null);
    try std.testing.expect(builtInModuleSource("zig-dom") != null);
    try std.testing.expect(builtInModuleSource("react") == null);
    try std.testing.expect(builtInModuleSource("@testing-library/react") == null);
}

test "collectEsmSpecifiers skips type-only imports and exports" {
    const source =
        \\import type { DriveFile } from "./DriveTypes";
        \\import value from "./value";
        \\export type { SharedType } from "./shared-types";
        \\export { runtimeValue } from "./runtime";
    ;

    const specifiers = try collectEsmSpecifiers(std.testing.allocator, source);
    defer {
        for (specifiers) |specifier| std.testing.allocator.free(specifier);
        std.testing.allocator.free(specifiers);
    }

    try std.testing.expectEqual(@as(usize, 2), specifiers.len);
    try std.testing.expectEqualStrings("./value", specifiers[0]);
    try std.testing.expectEqualStrings("./runtime", specifiers[1]);
}

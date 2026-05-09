const std = @import("std");
const runtime_pkg = @import("../runtime.zig");
const transform = @import("transform.zig");
const yuku_transform = @import("yuku_transform.zig");
const quickjs = @import("quickjs");

const Allocator = std.mem.Allocator;
const Runtime = runtime_pkg.Runtime;
const Exception = runtime_pkg.Exception;
const ModuleContext = runtime_pkg.ModuleContext;
const ModuleDef = runtime_pkg.ModuleDef;

pub const DomMode = union(enum) {
    auto,
    always,
    suffixes: []const []const u8,
};

pub fn defaultDomSuffixes() []const []const u8 {
    return &.{ ".jsx", ".tsx" };
}

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

const cjs_runtime_helpers_source =
    \\globalThis.__zigCjsRegistry = globalThis.__zigCjsRegistry || new Map();
    \\globalThis.__zigCjsNamespaceToRequireValue = function __zigCjsNamespaceToRequireValue(ns) {
    \\  try {
    \\    if (Object.prototype.hasOwnProperty.call(ns, "__zigCommonJSExports")) return ns.__zigCommonJSExports;
    \\    if (Object.prototype.hasOwnProperty.call(ns, "default")) return ns.default;
    \\    return ns;
    \\  } catch {
    \\    return {};
    \\  }
    \\};
    \\globalThis.__zigEsmNamespaceToRequireValue = function __zigEsmNamespaceToRequireValue(ns) {
    \\  const out = {};
    \\  Object.defineProperty(out, "__esModule", { value: true });
    \\  for (const key of Reflect.ownKeys(ns)) {
    \\    if (key === Symbol.toStringTag) continue;
    \\    Object.defineProperty(out, key, {
    \\      enumerable: true,
    \\      configurable: true,
    \\      get: () => ns[key],
    \\    });
    \\  }
    \\  return out;
    \\};
    \\globalThis.__zigLoadCommonJS = function __zigLoadCommonJS(id, dirname, deps, factory) {
    \\  const registry = globalThis.__zigCjsRegistry || (globalThis.__zigCjsRegistry = new Map());
    \\  if (registry.has(id)) return registry.get(id).exports;
    \\  const module = { exports: {} };
    \\  registry.set(id, module);
    \\  const require = (specifier) => {
    \\    const key = String(specifier);
    \\    const load = deps && deps[key];
    \\    return load ? load() : globalThis.__zigNativeRequire(id, key, "");
    \\  };
    \\  require.resolve = (specifier) => String(specifier);
    \\  factory.call(module.exports, module, module.exports, require, id, dirname, globalThis);
    \\  return module.exports;
    \\};
    \\globalThis.__zigGetCjsExports = function __zigGetCjsExports(id) {
    \\  const registry = globalThis.__zigCjsRegistry;
    \\  return registry && registry.has(id) ? registry.get(id).exports : undefined;
    \\};
    \\globalThis.__zigSetCjsJsonExports = function __zigSetCjsJsonExports(id, value) {
    \\  const registry = globalThis.__zigCjsRegistry || (globalThis.__zigCjsRegistry = new Map());
    \\  if (!registry.has(id)) registry.set(id, { exports: value });
    \\  return registry.get(id).exports;
    \\};
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

const native_builtin_stub_source =
    \\export {};
;

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

var active_cjs_loader_state: ?*ModuleLoaderState = null;

const CommonJsImport = struct {
    specifier: []u8,
    resolved: []u8,
    local: []u8,
    json_source: ?[]u8 = null,
    lazy: bool = false,

    fn deinit(self: *CommonJsImport, allocator: Allocator) void {
        allocator.free(self.specifier);
        allocator.free(self.resolved);
        allocator.free(self.local);
        if (self.json_source) |json| allocator.free(json);
    }
};

const NamedImportPart = struct {
    imported: []u8,
    local: []u8,
    specifier: []u8,

    fn deinit(self: *NamedImportPart, allocator: Allocator) void {
        allocator.free(self.imported);
        allocator.free(self.local);
        allocator.free(self.specifier);
    }
};

pub const FileResult = struct {
    path: []u8,
    passed: usize,
    failed: usize,
    skipped: usize,
    timed_out: usize,
    collection_errors: usize,
    expect_calls: usize,
    passed_report: ?[]u8,
    failure_report: ?[]u8,
    collection_report: ?[]u8,

    pub fn deinit(self: *FileResult, allocator: Allocator) void {
        allocator.free(self.path);
        if (self.passed_report) |report| {
            allocator.free(report);
        }
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

const ExportNameSet = struct {
    all: bool = false,
    names: std.StringHashMap(void) = undefined,
    initialized: bool = false,

    fn init() ExportNameSet {
        return .{};
    }

    fn add(self: *ExportNameSet, allocator: Allocator, name: []const u8) !void {
        if (self.all) return;
        if (!self.initialized) {
            self.names = std.StringHashMap(void).init(allocator);
            self.initialized = true;
        }
        const entry = try self.names.getOrPut(name);
        if (!entry.found_existing) {
            entry.key_ptr.* = try allocator.dupe(u8, name);
            entry.value_ptr.* = {};
        }
    }

    fn contains(self: *const ExportNameSet, name: []const u8) bool {
        if (self.all) return true;
        if (!self.initialized) return false;
        return self.names.contains(name);
    }

    fn deinit(self: *ExportNameSet, allocator: Allocator) void {
        if (!self.initialized) return;
        var iterator = self.names.iterator();
        while (iterator.next()) |entry| allocator.free(entry.key_ptr.*);
        self.names.deinit();
        self.initialized = false;
    }
};

const ModuleLoaderState = struct {
    const PathAlias = struct {
        pattern: []u8,
        target: []u8,
    };

    const ProfileModuleKind = enum {
        module,
        cjs,
    };

    const ProfileModuleEntry = struct {
        kind: ProfileModuleKind,
        elapsed_ns: i128,
        path: []u8,
    };

    allocator: Allocator,
    io: std.Io,
    runtime: ?*Runtime,
    entry_module_id: []const u8,
    loaded_modules: std.StringHashMap(*ModuleDef),
    source_cache: std.StringHashMap([]u8),
    mock_module_sources: std.StringHashMap([]u8),
    requested_exports: std.StringHashMap(ExportNameSet),
    path_alias_root: ?[]u8,
    path_aliases: std.ArrayList(PathAlias),
    profile_enabled: bool,
    profile_modules_enabled: bool,
    profile_module_entries: std.ArrayList(ProfileModuleEntry),
    profile_transform_ns: i128,
    profile_onload_ns: i128,
    profile_compile_ns: i128,
    profile_load_source_ns: i128,
    profile_collect_graph_ns: i128,
    profile_setup_eval_ns: i128,
    profile_entry_eval_ns: i128,
    profile_runner_ns: i128,
    profile_transform_count: usize,
    profile_module_count: usize,

    fn init(allocator: Allocator, io: std.Io) ModuleLoaderState {
        return .{
            .allocator = allocator,
            .io = io,
            .runtime = null,
            .entry_module_id = "",
            .loaded_modules = std.StringHashMap(*ModuleDef).init(allocator),
            .source_cache = std.StringHashMap([]u8).init(allocator),
            .mock_module_sources = std.StringHashMap([]u8).init(allocator),
            .requested_exports = std.StringHashMap(ExportNameSet).init(allocator),
            .path_alias_root = null,
            .path_aliases = .empty,
            .profile_enabled = (std.c.getenv("ZIG_DOM_PROFILE") != null and !std.mem.eql(u8, std.mem.span(std.c.getenv("ZIG_DOM_PROFILE").?), "0")) or std.c.getenv("ZIG_DOM_PROFILE_MODULES") != null,
            .profile_modules_enabled = std.c.getenv("ZIG_DOM_PROFILE_MODULES") != null,
            .profile_module_entries = .empty,
            .profile_transform_ns = 0,
            .profile_onload_ns = 0,
            .profile_compile_ns = 0,
            .profile_load_source_ns = 0,
            .profile_collect_graph_ns = 0,
            .profile_setup_eval_ns = 0,
            .profile_entry_eval_ns = 0,
            .profile_runner_ns = 0,
            .profile_transform_count = 0,
            .profile_module_count = 0,
        };
    }

    fn deinit(self: *ModuleLoaderState) void {
        self.clearPathAliases();

        for (self.profile_module_entries.items) |entry| {
            self.allocator.free(entry.path);
        }
        self.profile_module_entries.deinit(self.allocator);

        var mock_iterator = self.mock_module_sources.iterator();
        while (mock_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.mock_module_sources.deinit();
        var requested_iterator = self.requested_exports.iterator();
        while (requested_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.requested_exports.deinit();

        var source_iterator = self.source_cache.iterator();
        while (source_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.source_cache.deinit();

        var loaded_iterator = self.loaded_modules.iterator();
        while (loaded_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.loaded_modules.deinit();
    }

    fn profileNow(self: *ModuleLoaderState) i128 {
        return std.Io.Timestamp.now(self.io, .awake).toNanoseconds();
    }

    fn recordProfileModule(self: *ModuleLoaderState, kind: ProfileModuleKind, elapsed_ns: i128, path: []const u8) !void {
        if (!self.profile_modules_enabled) return;
        try self.profile_module_entries.append(self.allocator, .{
            .kind = kind,
            .elapsed_ns = elapsed_ns,
            .path = try self.allocator.dupe(u8, path),
        });
    }

    fn printProfileModules(self: *ModuleLoaderState) void {
        if (!self.profile_modules_enabled) return;
        std.mem.sort(ProfileModuleEntry, self.profile_module_entries.items, {}, profileModuleSlowerThan);
        for (self.profile_module_entries.items) |entry| {
            switch (entry.kind) {
                .module => std.debug.print("[zig-dom profile module] compile_ms={d:.3} {s}\n", .{
                    @as(f64, @floatFromInt(entry.elapsed_ns)) / 1_000_000.0,
                    entry.path,
                }),
                .cjs => std.debug.print("[zig-dom profile cjs] eval_ms={d:.3} {s}\n", .{
                    @as(f64, @floatFromInt(entry.elapsed_ns)) / 1_000_000.0,
                    entry.path,
                }),
            }
        }
    }

    fn profileModuleSlowerThan(_: void, lhs: ProfileModuleEntry, rhs: ProfileModuleEntry) bool {
        return lhs.elapsed_ns > rhs.elapsed_ns;
    }

    fn requestedExportsFor(self: *ModuleLoaderState, module_id: []const u8) ?*ExportNameSet {
        return self.requested_exports.getPtr(module_id);
    }

    fn readFileCached(self: *ModuleLoaderState, path: []const u8, max_bytes: usize) ![]const u8 {
        if (self.source_cache.get(path)) |source| return source;

        const source = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            path,
            self.allocator,
            .limited(max_bytes),
        );
        errdefer self.allocator.free(source);
        const key = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(key);
        try self.source_cache.put(key, source);
        return source;
    }

    fn recordRequestedExport(self: *ModuleLoaderState, module_id: []const u8, export_name: []const u8) !void {
        const entry = try self.requested_exports.getOrPut(module_id);
        if (!entry.found_existing) {
            entry.key_ptr.* = try self.allocator.dupe(u8, module_id);
            entry.value_ptr.* = ExportNameSet.init();
        }
        try entry.value_ptr.add(self.allocator, export_name);
    }

    fn recordAllRequestedExports(self: *ModuleLoaderState, module_id: []const u8) !void {
        const entry = try self.requested_exports.getOrPut(module_id);
        if (!entry.found_existing) {
            entry.key_ptr.* = try self.allocator.dupe(u8, module_id);
            entry.value_ptr.* = ExportNameSet.init();
        }
        entry.value_ptr.all = true;
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

    fn resolveLoadedModuleIdForMockSpecifier(self: *ModuleLoaderState, specifier: []const u8) !?[]u8 {
        if (self.loaded_modules.contains(specifier)) {
            return @as(?[]u8, try self.allocator.dupe(u8, specifier));
        }

        if (self.entry_module_id.len > 0) {
            if (try self.tryResolveLoadedModuleIdForBase(self.entry_module_id, specifier)) |resolved| {
                return resolved;
            }
        }

        var iterator = self.loaded_modules.iterator();
        while (iterator.next()) |entry| {
            if (try self.tryResolveLoadedModuleIdForBase(entry.key_ptr.*, specifier)) |resolved| {
                return resolved;
            }
        }

        return null;
    }

    fn tryResolveLoadedModuleIdForBase(self: *ModuleLoaderState, module_base_name: []const u8, specifier: []const u8) !?[]u8 {
        const resolved = self.normalizeSpecifierWithoutMocks(module_base_name, specifier) catch |err| switch (err) {
            error.ModuleNotFound, error.UnsupportedExternalModule => return null,
            else => return err,
        };
        defer self.allocator.free(resolved);

        if (!self.loaded_modules.contains(resolved)) {
            return null;
        }

        return @as(?[]u8, try self.allocator.dupe(u8, resolved));
    }

    fn normalizeSpecifierWithoutMocks(self: *ModuleLoaderState, module_base_name: []const u8, module_name: []const u8) ![]u8 {
        if (builtInModuleSource(module_name) != null) {
            return self.allocator.dupe(u8, module_name);
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

    fn loadModuleSource(self: *ModuleLoaderState, module_id: []const u8) ![]u8 {
        if (std.c.getenv("ZIG_DOM_MODULE_DEBUG") != null) {
            std.debug.print("[zig-dom module] {s}\n", .{module_id});
        }

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
            const source = try self.readFileCached(module_id, max_module_source_bytes);

            if (isCommonJsSource(module_id, source)) {
                return try self.loadCommonJsModuleSource(module_id);
            }

            return try self.allocator.dupe(u8, source);
        }

        if (std.mem.eql(u8, default_loader, "json")) {
            const json = try self.readFileCached(module_id, max_module_source_bytes);

            var source: std.ArrayList(u8) = .empty;
            errdefer source.deinit(self.allocator);
            try source.appendSlice(self.allocator, "export default ");
            try source.appendSlice(self.allocator, json);
            try source.appendSlice(self.allocator, ";\n");
            return try source.toOwnedSlice(self.allocator);
        }

        if (std.c.getenv("ZIG_DOM_TRANSFORM_DEBUG") != null) {
            std.debug.print("[zig-dom transform] {s} {s}\n", .{ default_loader, module_id });
        }
        const start = if (self.profile_enabled) self.profileNow() else 0;
        const raw_source = try self.readFileCached(module_id, max_module_source_bytes);
        const linked_source = try self.rewriteBarePackageNamedImports(module_id, raw_source);
        defer self.allocator.free(linked_source);
        const transformed = try yuku_transform.transformSource(self.allocator, module_id, linked_source, default_loader);
        if (self.profile_enabled) {
            self.profile_transform_ns += self.profileNow() - start;
            self.profile_transform_count += 1;
        }
        return transformed;
    }

    fn loadCommonJsModuleSource(self: *ModuleLoaderState, module_id: []const u8) ![]u8 {
        const source = try self.readFileCached(module_id, max_module_source_bytes);

        return self.buildNativeCommonJsModuleSource(module_id, source);
    }

    fn buildNativeCommonJsModuleSource(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) ![]u8 {
        const folded_source = try foldNodeEnvConditionals(self.allocator, source);
        defer self.allocator.free(folded_source);

        const package_rewritten_source = try rewriteKnownCommonJsPackageImports(self, module_id, folded_source);
        defer self.allocator.free(package_rewritten_source);

        const pruned_source = blk: {
            const requested = self.requestedExportsFor(module_id) orelse break :blk try self.allocator.dupe(u8, package_rewritten_source);
            break :blk try pruneUnrequestedCommonJsExports(self.allocator, package_rewritten_source, requested);
        };
        defer self.allocator.free(pruned_source);

        try self.recordCommonJsRequirePropertyRequests(module_id, pruned_source);
        const specifiers = try collectCommonJsSpecifiers(self.allocator, pruned_source);
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
            const resolved = self.normalizeRequireSpecifier(module_id, specifier) catch continue;
            errdefer self.allocator.free(resolved);

            const lazy = try self.shouldLazyLoadCommonJsDependency(resolved);
            const local = if (lazy or std.mem.endsWith(u8, resolved, ".json"))
                try self.allocator.dupe(u8, "")
            else
                try std.fmt.allocPrint(self.allocator, "__zig_cjs_dep_{d}", .{index});
            errdefer self.allocator.free(local);

            const json_source = if (!lazy and std.mem.endsWith(u8, resolved, ".json"))
                try std.Io.Dir.cwd().readFileAlloc(self.io, resolved, self.allocator, .limited(max_module_source_bytes))
            else
                null;
            errdefer if (json_source) |json| self.allocator.free(json);

            try imports.append(self.allocator, .{
                .specifier = try self.allocator.dupe(u8, specifier),
                .resolved = resolved,
                .local = local,
                .json_source = json_source,
                .lazy = lazy,
            });
        }

        const export_names = try self.collectCommonJsExportNamesDeep(module_id, pruned_source);
        defer {
            for (export_names) |name| self.allocator.free(name);
            self.allocator.free(export_names);
        }

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);

        for (imports.items) |item| {
            if (item.lazy or item.json_source != null) continue;
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
            \\const __zigCjsDeps = {
            \\
        );

        for (imports.items) |item| {
            const specifier_literal = try escapeJsSingleQuotedString(self.allocator, item.specifier);
            defer self.allocator.free(specifier_literal);
            const resolved_literal = try escapeJsSingleQuotedString(self.allocator, item.resolved);
            defer self.allocator.free(resolved_literal);
            if (item.json_source) |json| {
                try appendFmt(self.allocator, &out, "  '{s}': () => (", .{specifier_literal});
                try out.appendSlice(self.allocator, json);
                try out.appendSlice(self.allocator, "),\n");
            } else if (item.lazy) {
                try appendFmt(self.allocator, &out, "  '{s}': () => globalThis.__zigNativeRequire('{s}', '{s}', '{s}'),\n", .{ specifier_literal, module_literal, specifier_literal, resolved_literal });
            } else {
                try appendFmt(self.allocator, &out, "  '{s}': () => globalThis.__zigCjsNamespaceToRequireValue({s}),\n", .{ specifier_literal, item.local });
            }
        }

        try out.appendSlice(self.allocator,
            \\};
            \\
        );
        try appendFmt(self.allocator, &out, "const __zigCommonJSExports = globalThis.__zigLoadCommonJS('{s}', '{s}', __zigCjsDeps, function(module, exports, require, __filename, __dirname, global) {{\n", .{ module_literal, dirname_literal });
        try out.appendSlice(self.allocator, pruned_source);
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

        return try out.toOwnedSlice(self.allocator);
    }

    fn shouldLazyLoadCommonJsDependency(self: *ModuleLoaderState, resolved: []const u8) !bool {
        if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) return false;
        if (std.mem.endsWith(u8, resolved, ".json")) return true;

        const loader = transform.loaderForPath(resolved) orelse return false;
        if (!std.mem.eql(u8, loader, "js")) return false;

        const source = self.readFileCached(resolved, max_module_source_bytes) catch return false;

        if (!isCommonJsSource(resolved, source)) return false;
        return try self.commonJsSourceRequiresOnlyLazyCompatible(resolved, source);
    }

    fn commonJsSourceRequiresOnlyLazyCompatible(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) !bool {
        const specifiers = try collectCommonJsSpecifiers(self.allocator, source);
        defer {
            for (specifiers) |specifier| self.allocator.free(specifier);
            self.allocator.free(specifiers);
        }

        for (specifiers) |specifier| {
            const resolved = self.normalizeRequireSpecifier(module_id, specifier) catch return false;
            defer self.allocator.free(resolved);

            if (std.mem.endsWith(u8, resolved, ".json")) continue;
            if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) return false;

            const loader = transform.loaderForPath(resolved) orelse return false;
            if (!std.mem.eql(u8, loader, "js")) return false;

            const child_source = self.readFileCached(resolved, max_module_source_bytes) catch return false;

            if (!isCommonJsSource(resolved, child_source)) return false;
        }

        return true;
    }

    fn buildLazyCommonJsScriptSource(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) ![]u8 {
        const folded_source = try foldNodeEnvConditionals(self.allocator, source);
        defer self.allocator.free(folded_source);
        const package_rewritten_source = try rewriteKnownCommonJsPackageImports(self, module_id, folded_source);
        defer self.allocator.free(package_rewritten_source);

        const module_literal = try escapeJsSingleQuotedString(self.allocator, module_id);
        defer self.allocator.free(module_literal);
        const dirname = std.fs.path.dirname(module_id) orelse ".";
        const dirname_literal = try escapeJsSingleQuotedString(self.allocator, dirname);
        defer self.allocator.free(dirname_literal);

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        try appendFmt(self.allocator, &out, "globalThis.__zigLoadCommonJS('{s}', '{s}', null, function(module, exports, require, __filename, __dirname, global) {{\n", .{ module_literal, dirname_literal });
        try out.appendSlice(self.allocator, package_rewritten_source);
        try out.appendSlice(self.allocator,
            \\
            \\});
            \\
        );
        return try out.toOwnedSlice(self.allocator);
    }

    fn loadCommonJsValue(self: *ModuleLoaderState, ctx: *ModuleContext, parent_id: []const u8, specifier: []const u8, resolved_hint: []const u8) !quickjs.Value {
        const resolved = if (resolved_hint.len > 0)
            try self.allocator.dupe(u8, resolved_hint)
        else
            try self.normalizeRequireSpecifier(parent_id, specifier);
        defer self.allocator.free(resolved);

        if (try self.getCachedCommonJsValue(ctx, resolved)) |cached| {
            return cached;
        }

        if (std.mem.endsWith(u8, resolved, ".json")) {
            return self.loadCommonJsJsonValue(ctx, resolved);
        }

        if (transform.loaderForPath(resolved)) |default_loader| {
            if (try self.loadModuleSourceFromOnLoad(resolved, default_loader)) |hook_source| {
                defer self.allocator.free(hook_source);
                return self.loadOnLoadModuleAsCommonJsValue(ctx, resolved, hook_source);
            }
        }

        const source = blk: {
            const raw = try self.readFileCached(resolved, max_module_source_bytes);
            if (!isCommonJsSource(resolved, raw)) return error.UnsupportedExternalModule;
            break :blk try self.buildLazyCommonJsScriptSource(resolved, raw);
        };
        defer self.allocator.free(source);

        const source_z = try self.allocator.dupeZ(u8, source);
        defer self.allocator.free(source_z);
        const filename_z = try self.allocator.dupeZ(u8, resolved);
        defer self.allocator.free(filename_z);

        const compile_start = if (self.profile_enabled) self.profileNow() else 0;
        const value = ctx.eval(source_z[0..source.len], filename_z, .{});
        if (self.profile_enabled) {
            const elapsed = self.profileNow() - compile_start;
            self.profile_compile_ns += elapsed;
            self.profile_module_count += 1;
            try self.recordProfileModule(.cjs, elapsed, resolved);
        }
        if (value.isException()) return error.EvaluationFailed;
        return value;
    }

    fn loadOnLoadModuleAsCommonJsValue(self: *ModuleLoaderState, ctx: *ModuleContext, module_id: []const u8, source: []const u8) !quickjs.Value {
        const source_z = try self.allocator.dupeZ(u8, source);
        defer self.allocator.free(source_z);
        const filename_z = try self.allocator.dupeZ(u8, module_id);
        defer self.allocator.free(filename_z);

        const compiled = ctx.eval(source_z[0..source.len], filename_z, .{ .type = .module, .compile_only = true });
        if (compiled.isException()) return error.EvaluationFailed;

        try compiled.resolveModule(ctx);

        const result = ctx.evalFunction(compiled);
        if (result.isException()) return error.EvaluationFailed;
        defer result.deinit(ctx);

        if (result.isPromise()) {
            const runtime = self.runtime orelse return error.EvaluationFailed;
            var iterations: usize = 0;
            while (result.promiseState(ctx) == .pending) : (iterations += 1) {
                if (iterations > 100_000) return error.EvaluationFailed;
                _ = runtime.executePendingJob() catch return error.EvaluationFailed;
            }
            if (result.promiseState(ctx) == .rejected) return error.EvaluationFailed;
        }

        const module_ptr_any = quickjs.c.JS_VALUE_GET_PTR(compiled.cval()) orelse return error.EvaluationFailed;
        const module_ptr: *ModuleDef = @ptrCast(@alignCast(module_ptr_any));
        const namespace = module_ptr.getNamespace(ctx);
        if (namespace.isException()) return error.EvaluationFailed;
        defer namespace.deinit(ctx);

        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const converter = global.getPropertyStr(ctx, "__zigEsmNamespaceToRequireValue");
        defer converter.deinit(ctx);
        if (!converter.isFunction(ctx)) return namespace.dup(ctx);

        const args = [_]quickjs.Value{namespace.dup(ctx)};
        const converted = converter.call(ctx, quickjs.Value.undefined, &args);
        args[0].deinit(ctx);
        if (converted.isException()) return error.EvaluationFailed;
        return converted;
    }

    fn loadCommonJsJsonValue(self: *ModuleLoaderState, ctx: *ModuleContext, module_id: []const u8) !quickjs.Value {
        const json = try self.readFileCached(module_id, max_module_source_bytes);

        const filename_z = try self.allocator.dupeZ(u8, module_id);
        defer self.allocator.free(filename_z);

        var parsed = quickjs.Value.parseJSON(ctx, json, filename_z);
        if (parsed.isException()) {
            const exception = ctx.getException();
            exception.deinit(ctx);

            const source = try std.fmt.allocPrint(self.allocator, "({s})", .{json});
            defer self.allocator.free(source);
            const source_z = try self.allocator.dupeZ(u8, source);
            defer self.allocator.free(source_z);
            parsed = ctx.eval(source_z[0..source.len], filename_z, .{});
            if (parsed.isException()) return error.EvaluationFailed;
        }
        errdefer parsed.deinit(ctx);

        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const setter = global.getPropertyStr(ctx, "__zigSetCjsJsonExports");
        defer setter.deinit(ctx);
        if (!setter.isFunction(ctx)) {
            return parsed;
        }

        const id = quickjs.Value.initStringLen(ctx, module_id);
        defer id.deinit(ctx);
        const args = [_]quickjs.Value{ id, parsed };
        const result = setter.call(ctx, quickjs.Value.undefined, &args);
        parsed.deinit(ctx);
        if (result.isException()) return error.EvaluationFailed;
        return result;
    }

    fn getCachedCommonJsValue(self: *ModuleLoaderState, ctx: *ModuleContext, module_id: []const u8) !?quickjs.Value {
        _ = self;
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const getter = global.getPropertyStr(ctx, "__zigGetCjsExports");
        defer getter.deinit(ctx);
        if (!getter.isFunction(ctx)) return null;

        const id = quickjs.Value.initStringLen(ctx, module_id);
        defer id.deinit(ctx);
        const args = [_]quickjs.Value{id};
        const value = getter.call(ctx, quickjs.Value.undefined, &args);
        if (value.isException()) return error.EvaluationFailed;
        if (value.isUndefined()) {
            value.deinit(ctx);
            return null;
        }
        return value;
    }

    fn normalizeRequireSpecifier(self: *ModuleLoaderState, module_base_name: []const u8, module_name: []const u8) ![]u8 {
        if (builtInModuleSource(module_name) != null) {
            return self.allocator.dupe(u8, module_name);
        }

        if (self.mock_module_sources.contains(module_name)) {
            return std.fmt.allocPrint(self.allocator, "__zig_mock__/{s}", .{module_name});
        }

        if (std.fs.path.isAbsolute(module_name)) {
            return self.resolveRequireAbsolutePath(module_name);
        }

        if (isRelativeSpecifier(module_name)) {
            return self.resolveRequireRelativePath(module_base_name, module_name);
        }

        if (try self.resolveNodeModuleRequire(module_base_name, module_name)) |resolved| {
            return resolved;
        }

        return self.normalizeSpecifier(module_base_name, module_name);
    }

    fn resolveRequireRelativePath(self: *ModuleLoaderState, module_base_name: []const u8, specifier: []const u8) ![]u8 {
        if (!std.fs.path.isAbsolute(module_base_name)) return error.ModuleNotFound;
        const base_dir = std.fs.path.dirname(module_base_name) orelse return error.ModuleNotFound;
        const candidate = try std.fs.path.resolve(self.allocator, &.{ base_dir, specifier });
        errdefer self.allocator.free(candidate);
        return self.resolveRequirePathWithProbing(candidate);
    }

    fn resolveRequireAbsolutePath(self: *ModuleLoaderState, specifier: []const u8) ![]u8 {
        const candidate = try std.fs.path.resolve(self.allocator, &.{specifier});
        errdefer self.allocator.free(candidate);
        return self.resolveRequirePathWithProbing(candidate);
    }

    fn resolveRequirePathWithProbing(self: *ModuleLoaderState, candidate: []u8) ![]u8 {
        if (self.pathIsSupportedFile(candidate)) return candidate;

        const extensions = [_][]const u8{ ".js", ".cjs", ".json", ".mjs", ".ts", ".tsx", ".jsx" };
        for (extensions) |extension| {
            const path = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ candidate, extension });
            if (self.pathIsSupportedFile(path)) {
                self.allocator.free(candidate);
                return path;
            }
            self.allocator.free(path);
        }
        for (extensions) |extension| {
            const path = try std.fmt.allocPrint(self.allocator, "{s}/index{s}", .{ candidate, extension });
            if (self.pathIsSupportedFile(path)) {
                self.allocator.free(candidate);
                return path;
            }
            self.allocator.free(path);
        }

        return error.ModuleNotFound;
    }

    fn resolveNodeModuleRequire(self: *ModuleLoaderState, module_base_name: []const u8, module_name: []const u8) !?[]u8 {
        const parsed = parseBarePackageSpecifier(module_name) orelse return null;
        if (!std.fs.path.isAbsolute(module_base_name)) return null;

        var current_dir = try self.allocator.dupe(u8, std.fs.path.dirname(module_base_name) orelse return null);
        defer self.allocator.free(current_dir);

        while (true) {
            const package_dir = try std.fs.path.resolve(self.allocator, &.{ current_dir, "node_modules", parsed.package_name });
            defer self.allocator.free(package_dir);

            if (self.pathIsDirectory(package_dir)) {
                if (try self.resolveNodeModuleRequireFromDirectory(package_dir, parsed.subpath)) |resolved| {
                    return resolved;
                }
            }

            const parent = std.fs.path.dirname(current_dir) orelse break;
            if (parent.len == current_dir.len) break;

            const next_dir = try self.allocator.dupe(u8, parent);
            self.allocator.free(current_dir);
            current_dir = next_dir;
        }

        return null;
    }

    fn resolveNodeModuleRequireFromDirectory(self: *ModuleLoaderState, package_dir: []const u8, subpath: []const u8) !?[]u8 {
        if (subpath.len > 0) {
            if (try self.resolveNodeModuleSubpathFromExportsWithMode(package_dir, subpath, .require)) |resolved| {
                return resolved;
            }

            const subpath_candidate = try std.fs.path.resolve(self.allocator, &.{ package_dir, subpath });
            errdefer self.allocator.free(subpath_candidate);

            if (self.pathIsDirectory(subpath_candidate)) {
                if (try self.resolveNodeModulePackageRoot(subpath_candidate)) |resolved_dir_entry| {
                    self.allocator.free(subpath_candidate);
                    return resolved_dir_entry;
                }
            }

            return self.resolvePathWithProbing(subpath_candidate) catch |err| switch (err) {
                error.ModuleNotFound => {
                    self.allocator.free(subpath_candidate);
                    return null;
                },
                else => return err,
            };
        }

        return self.resolveNodeModulePackageRootWithMode(package_dir, .require);
    }

    fn resolveNodeModulePackageRootWithMode(self: *ModuleLoaderState, package_dir: []const u8, mode: PackageExportMode) !?[]u8 {
        const package_json_path = try std.fs.path.resolve(self.allocator, &.{ package_dir, "package.json" });
        defer self.allocator.free(package_json_path);

        const package_json_stat = std.Io.Dir.cwd().statFile(self.io, package_json_path, .{}) catch return null;
        if (package_json_stat.kind != .file) return null;

        const package_json_source = try self.readFileCached(package_json_path, max_package_json_bytes);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, package_json_source, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root == .object) {
            if (root.object.get("exports")) |exports_value| {
                if (jsonExtractPackageTarget(exports_value, mode)) |entry| {
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
        }

        return null;
    }

    fn recordCommonJsRequirePropertyRequests(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) !void {
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, source, cursor, "require(")) |require_index| {
            const specifier = parseRequireSpecifierAt(source, require_index) orelse {
                cursor = require_index + "require(".len;
                continue;
            };

            const local = findCommonJsRequireBinding(source, require_index) orelse {
                cursor = require_index + "require(".len;
                continue;
            };

            const resolved = self.normalizeRequireSpecifier(module_id, specifier) catch {
                cursor = require_index + "require(".len;
                continue;
            };
            defer self.allocator.free(resolved);

            var found_property = false;
            if (commonJsRequireBindingNeedsAllExports(source, local)) {
                try self.recordAllRequestedExports(resolved);
                cursor = require_index + "require(".len;
                continue;
            }

            var property_cursor: usize = 0;
            while (std.mem.indexOfPos(u8, source, property_cursor, local)) |local_index| {
                const after_local = local_index + local.len;
                if ((local_index == 0 or !isIdentifierContinue(source[local_index - 1])) and
                    after_local < source.len and
                    source[after_local] == '.' and
                    after_local + 1 < source.len and
                    isIdentifierContinue(source[after_local + 1]))
                {
                    const name_start = after_local + 1;
                    const name_end = readIdentifierEnd(source, name_start);
                    if (name_end > name_start and !std.mem.eql(u8, source[name_start..name_end], "default")) {
                        try self.recordRequestedExport(resolved, source[name_start..name_end]);
                        found_property = true;
                    }
                    property_cursor = name_end;
                    continue;
                }
                property_cursor = after_local;
            }

            if (!found_property) {
                try self.recordAllRequestedExports(resolved);
            }

            cursor = require_index + "require(".len;
        }
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
            if (!isRelativeSpecifier(specifier) and !isCommonJsReexportSpecifier(source, specifier)) continue;

            const resolved = self.normalizeRequireSpecifier(module_id, specifier) catch continue;
            defer self.allocator.free(resolved);
            if (scanned.contains(resolved)) continue;
            if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) continue;

            const child_source = self.readFileCached(resolved, max_module_source_bytes) catch continue;

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
        const start = if (self.profile_enabled) self.profileNow() else 0;
        const debug_onload = std.c.getenv("ZIG_DOM_ONLOAD_DEBUG") != null;
        if (debug_onload) {
            std.debug.print("[zig-dom onload] check {s} loader={s}\n", .{ module_id, default_loader });
        }
        var hook_result = (try runtime.loadFromOnLoad(module_id)) orelse {
            if (self.profile_enabled) self.profile_onload_ns += self.profileNow() - start;
            if (debug_onload) {
                std.debug.print("[zig-dom onload] miss {s}\n", .{module_id});
            }
            return null;
        };
        if (self.profile_enabled) self.profile_onload_ns += self.profileNow() - start;
        defer hook_result.deinit(self.allocator);

        const effective_loader = hook_result.loader orelse default_loader;
        if (debug_onload) {
            const requested_text = if (self.requestedExportsFor(module_id)) |requested|
                if (requested.all) "all" else "some"
            else
                "none";
            std.debug.print("[zig-dom onload] hit {s} loader={s} requested={s} bytes={d}\n", .{ module_id, effective_loader, requested_text, hook_result.contents.len });
        }
        if (std.mem.eql(u8, effective_loader, "js")) {
            const js_onload_source = blk: {
                const requested = self.requestedExportsFor(module_id) orelse break :blk try self.allocator.dupe(u8, hook_result.contents);
                if (requested.all) break :blk try self.allocator.dupe(u8, hook_result.contents);
                break :blk try pruneUnrequestedTsExports(self.allocator, hook_result.contents, requested);
            };
            defer self.allocator.free(js_onload_source);

            if (looksLikeJsxSource(js_onload_source)) {
                return try self.transformOnLoadContents(module_id, "jsx", js_onload_source);
            }

            const rewritten = try self.rewriteBarePackageNamedImports(module_id, js_onload_source);
            defer self.allocator.free(rewritten);
            return try pruneUnusedImports(self.allocator, rewritten);
        }

        if (std.mem.eql(u8, effective_loader, "ts") or
            std.mem.eql(u8, effective_loader, "tsx") or
            std.mem.eql(u8, effective_loader, "jsx"))
        {
            const transformed = try self.transformOnLoadContents(module_id, effective_loader, hook_result.contents);
            return transformed;
        }

        if (std.mem.eql(u8, effective_loader, "json")) {
            return try self.wrapJsonModuleSource(hook_result.contents);
        }

        return error.UnsupportedTransformLoader;
    }

    fn wrapJsonModuleSource(self: *ModuleLoaderState, json: []const u8) ![]u8 {
        var source: std.ArrayList(u8) = .empty;
        errdefer source.deinit(self.allocator);
        try source.appendSlice(self.allocator, "export default ");
        try source.appendSlice(self.allocator, json);
        try source.appendSlice(self.allocator, ";\n");
        return try source.toOwnedSlice(self.allocator);
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
        const can_tree_shake = std.mem.eql(u8, loader, "ts") or
            std.mem.eql(u8, loader, "tsx") or
            std.mem.eql(u8, loader, "jsx");
        const source = if (can_tree_shake) blk: {
            const requested = self.requestedExportsFor(module_id) orelse break :blk try self.rewriteBarePackageNamedImports(module_id, contents);
            const export_pruned = try pruneUnrequestedTsExports(self.allocator, contents, requested);
            defer self.allocator.free(export_pruned);
            const const_pruned = try pruneUnusedTsConstDeclarations(self.allocator, export_pruned);
            defer self.allocator.free(const_pruned);
            break :blk try self.rewriteBarePackageNamedImports(module_id, const_pruned);
        } else try self.rewriteBarePackageNamedImports(module_id, contents);
        defer self.allocator.free(source);

        const transformed = try yuku_transform.transformSource(self.allocator, module_id, source, loader);
        defer self.allocator.free(transformed);
        return pruneUnusedImports(self.allocator, transformed);
    }

    fn rewriteBarePackageNamedImports(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);

        var cursor: usize = 0;
        var rewrite_index: usize = 0;
        while (std.mem.indexOfPos(u8, source, cursor, "import")) |start| {
            if (!hasWordAt(source, start, "import")) {
                try out.appendSlice(self.allocator, source[cursor .. start + "import".len]);
                cursor = start + "import".len;
                continue;
            }

            const end = findImportStatementEnd(source, start);
            const statement = source[start..end];
            const parsed = parseImportStatement(statement) orelse {
                try out.appendSlice(self.allocator, source[cursor..end]);
                cursor = end;
                continue;
            };

            const replacement = try self.buildBareNamedImportReplacement(module_id, parsed, rewrite_index);
            if (replacement) |owned| {
                defer self.allocator.free(owned);
                try out.appendSlice(self.allocator, source[cursor..start]);
                try out.appendSlice(self.allocator, owned);
                rewrite_index += 1;
                cursor = end;
                if (cursor < source.len and source[cursor] == ';') cursor += 1;
                continue;
            }

            try out.appendSlice(self.allocator, source[cursor..end]);
            cursor = end;
        }

        try out.appendSlice(self.allocator, source[cursor..]);
        const owned = try out.toOwnedSlice(self.allocator);
        return owned;
    }

    fn buildBareNamedImportReplacement(
        self: *ModuleLoaderState,
        module_id: []const u8,
        parsed: ParsedImportStatement,
        rewrite_index: usize,
    ) !?[]u8 {
        if (self.runtime) |runtime| {
            try self.syncMockModulesFromRuntime(runtime);
        }
        if (parsed.all or !isBarePackageRootSpecifier(parsed.specifier)) return null;
        if (self.mock_module_sources.contains(parsed.specifier)) return null;
        const bindings = std.mem.trim(u8, parsed.bindings, " \t\r\n");
        if (!std.mem.startsWith(u8, bindings, "{") or !std.mem.endsWith(u8, bindings, "}")) return null;
        if (try self.hasOnLoadForSpecifier(module_id, parsed.specifier)) return null;

        var imports: std.ArrayList(NamedImportPart) = .empty;
        defer {
            for (imports.items) |*part| part.deinit(self.allocator);
            imports.deinit(self.allocator);
        }

        var parts = std.mem.tokenizeScalar(u8, bindings[1 .. bindings.len - 1], ',');
        while (parts.next()) |raw_part| {
            const part = std.mem.trim(u8, raw_part, " \t\r\n");
            if (part.len == 0 or std.mem.startsWith(u8, part, "type ")) continue;
            const as_index = std.mem.indexOf(u8, part, " as ");
            const imported = std.mem.trim(u8, if (as_index) |idx| part[0..idx] else part, " \t\r\n");
            const local = std.mem.trim(u8, if (as_index) |idx| part[idx + " as ".len ..] else part, " \t\r\n");
            if (!isValidIdentifier(imported) or !isValidIdentifier(local)) return null;

            const subpath_specifier = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ parsed.specifier, imported });
            errdefer self.allocator.free(subpath_specifier);
            const resolved = self.normalizeSpecifier(module_id, subpath_specifier) catch {
                self.allocator.free(subpath_specifier);
                return null;
            };
            self.allocator.free(resolved);

            try imports.append(self.allocator, .{
                .imported = try self.allocator.dupe(u8, imported),
                .local = try self.allocator.dupe(u8, local),
                .specifier = subpath_specifier,
            });
        }

        if (imports.items.len == 0) return null;

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        for (imports.items, 0..) |part, index| {
            const ns = try std.fmt.allocPrint(self.allocator, "__zig_pkg_{d}_{d}", .{ rewrite_index, index });
            defer self.allocator.free(ns);
            try appendFmt(self.allocator, &out, "import * as {s} from \"{s}\";\n", .{ ns, part.specifier });
            try appendFmt(self.allocator, &out, "const {s} = ({s}.default && {s}.default.__esModule && \"default\" in {s}.default) ? {s}.default.default : ({s}.default ?? {s}.{s} ?? {s});\n", .{ part.local, ns, ns, ns, ns, ns, ns, part.imported, ns });
        }
        const owned = try out.toOwnedSlice(self.allocator);
        return owned;
    }

    fn hasOnLoadForSpecifier(self: *ModuleLoaderState, module_id: []const u8, specifier: []const u8) anyerror!bool {
        const runtime = self.runtime orelse return false;
        const resolved = self.normalizeSpecifier(module_id, specifier) catch return false;
        defer self.allocator.free(resolved);
        return try runtime.matchesOnLoad(resolved);
    }

    fn recordStaticImportRequests(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) !void {
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, source, cursor, "import")) |start| {
            if (!hasWordAt(source, start, "import")) {
                cursor = start + "import".len;
                continue;
            }

            const end = findImportStatementEnd(source, start);
            const statement = source[start..end];
            const parsed = parseImportStatement(statement) orelse {
                cursor = end;
                continue;
            };

            const resolved = self.normalizeSpecifier(module_id, parsed.specifier) catch {
                cursor = end;
                continue;
            };
            defer self.allocator.free(resolved);

            if (parsed.all) {
                try self.recordAllRequestedExports(resolved);
            } else {
                try self.recordImportBindings(resolved, parsed.bindings);
            }

            cursor = end;
        }
    }

    fn collectImportGraph(self: *ModuleLoaderState, module_id: []const u8) !void {
        var visited = std.StringHashMap(void).init(self.allocator);
        defer {
            var iterator = visited.iterator();
            while (iterator.next()) |entry| self.allocator.free(entry.key_ptr.*);
            visited.deinit();
        }

        try self.collectImportGraphInto(module_id, &visited);
    }

    fn collectImportGraphInto(self: *ModuleLoaderState, module_id: []const u8, visited: *std.StringHashMap(void)) !void {
        if (visited.contains(module_id)) return;
        const visited_key = try self.allocator.dupe(u8, module_id);
        errdefer self.allocator.free(visited_key);
        try visited.put(visited_key, {});

        if (builtInModuleSource(module_id) != null or isMockModuleId(module_id)) return;

        const source = try self.loadModuleSource(module_id);
        defer self.allocator.free(source);

        var imports: std.ArrayList([]u8) = .empty;
        defer {
            for (imports.items) |item| self.allocator.free(item);
            imports.deinit(self.allocator);
        }

        try self.recordStaticImportRequestsAndCollect(module_id, source, &imports);
        for (imports.items) |import_id| {
            try self.collectImportGraphInto(import_id, visited);
        }
    }

    fn recordStaticImportRequestsAndCollect(
        self: *ModuleLoaderState,
        module_id: []const u8,
        source: []const u8,
        imports: *std.ArrayList([]u8),
    ) !void {
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, source, cursor, "import")) |start| {
            if (!hasWordAt(source, start, "import")) {
                cursor = start + "import".len;
                continue;
            }

            const end = findImportStatementEnd(source, start);
            const statement = source[start..end];
            const parsed = parseImportStatement(statement) orelse {
                cursor = end;
                continue;
            };

            const resolved = self.normalizeSpecifier(module_id, parsed.specifier) catch {
                cursor = end;
                continue;
            };
            errdefer self.allocator.free(resolved);

            if (parsed.all) {
                try self.recordAllRequestedExports(resolved);
            } else {
                try self.recordImportBindings(resolved, parsed.bindings);
            }

            try imports.append(self.allocator, resolved);
            cursor = end;
        }
    }

    fn recordImportBindings(self: *ModuleLoaderState, resolved: []const u8, bindings: []const u8) !void {
        const trimmed = std.mem.trim(u8, bindings, " \t\r\n");
        if (trimmed.len == 0) return;

        if (std.mem.startsWith(u8, trimmed, "{") and std.mem.endsWith(u8, trimmed, "}")) {
            var parts = std.mem.tokenizeScalar(u8, trimmed[1 .. trimmed.len - 1], ',');
            while (parts.next()) |raw_part| {
                const part = std.mem.trim(u8, raw_part, " \t\r\n");
                if (part.len == 0 or std.mem.startsWith(u8, part, "type ")) continue;
                const as_index = std.mem.indexOf(u8, part, " as ");
                const name = std.mem.trim(u8, if (as_index) |idx| part[0..idx] else part, " \t\r\n");
                if (name.len > 0) try self.recordRequestedExport(resolved, name);
            }
            return;
        }

        if (std.mem.startsWith(u8, trimmed, "* as ")) {
            try self.recordAllRequestedExports(resolved);
            return;
        }

        if (std.mem.indexOfScalar(u8, trimmed, ',')) |comma| {
            try self.recordRequestedExport(resolved, "default");
            try self.recordImportBindings(resolved, trimmed[comma + 1 ..]);
            return;
        }

        try self.recordRequestedExport(resolved, "default");
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
        return self.resolveNodeModuleSubpathFromExportsWithMode(package_dir, subpath, .import);
    }

    fn resolveNodeModuleSubpathFromExportsWithMode(self: *ModuleLoaderState, package_dir: []const u8, subpath: []const u8, mode: PackageExportMode) !?[]u8 {
        const package_json_path = try std.fs.path.resolve(self.allocator, &.{ package_dir, "package.json" });
        defer self.allocator.free(package_json_path);

        const package_json_stat = std.Io.Dir.cwd().statFile(self.io, package_json_path, .{}) catch return null;
        if (package_json_stat.kind != .file) {
            return null;
        }

        const package_json_source = try self.readFileCached(package_json_path, max_package_json_bytes);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, package_json_source, .{});
        defer parsed.deinit();

        const root = parsed.value;
        const target = jsonResolvePackageSubpath(self.allocator, root, subpath, mode) orelse return null;
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

        const package_json_source = try self.readFileCached(package_json_path, max_package_json_bytes);

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

const PackageExportMode = enum { import, require };

fn jsonResolvePackageSubpathImport(allocator: Allocator, root: std.json.Value, subpath: []const u8) ?[]u8 {
    return jsonResolvePackageSubpath(allocator, root, subpath, .import);
}

fn jsonResolvePackageSubpath(allocator: Allocator, root: std.json.Value, subpath: []const u8, mode: PackageExportMode) ?[]u8 {
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
        if (jsonExtractPackageTarget(exact_export, mode)) |target| {
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
        const target = jsonExtractPackageTarget(entry.value_ptr.*, mode) orelse continue;
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

fn jsonExtractPackageTarget(value: std.json.Value, mode: PackageExportMode) ?[]const u8 {
    return switch (mode) {
        .import => jsonExtractImportTarget(value),
        .require => jsonExtractRequireTarget(value),
    };
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

fn jsonExtractRequireTarget(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        .object => |object| blk: {
            if (object.get(".")) |root_export| {
                if (jsonExtractRequireTarget(root_export)) |target| break :blk target;
            }
            if (object.get("node")) |node_export| {
                if (jsonExtractRequireTarget(node_export)) |target| break :blk target;
            }
            if (object.get("require")) |require_export| {
                if (jsonExtractRequireTarget(require_export)) |target| break :blk target;
            }
            if (object.get("default")) |default_export| {
                if (jsonExtractRequireTarget(default_export)) |target| break :blk target;
            }
            if (object.get("import")) |import_export| {
                if (jsonExtractRequireTarget(import_export)) |target| break :blk target;
            }
            break :blk null;
        },
        .array => |array| blk: {
            for (array.items) |item| {
                if (jsonExtractRequireTarget(item)) |target| break :blk target;
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

        if (std.mem.startsWith(u8, source[cursor..], "Object.defineProperty(exports,")) {
            var name_index = cursor + "Object.defineProperty(exports,".len;
            skipTrivia(source, &name_index);
            if (parseQuotedSpecifier(source, name_index)) |literal| {
                const name = literal.specifier;
                if (!std.mem.eql(u8, name, "default") and !std.mem.eql(u8, name, "__esModule")) {
                    try appendSpecifier(allocator, names, dedup, name);
                }
                cursor = literal.next_index;
                continue;
            }
        }

        cursor += 1;
    }
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

fn isCommonJsReexportSpecifier(source: []const u8, specifier: []const u8) bool {
    var cursor: usize = 0;
    while (std.mem.indexOf(u8, source[cursor..], specifier)) |relative| {
        const specifier_start = cursor + relative;
        if (specifier_start == 0) return false;
        const quote = source[specifier_start - 1];
        if (quote != '\'' and quote != '"') {
            cursor = specifier_start + specifier.len;
            continue;
        }
        const after = specifier_start + specifier.len;
        if (after >= source.len or source[after] != quote) {
            cursor = after;
            continue;
        }

        const before = source[0 .. specifier_start - 1];
        const require_index = std.mem.lastIndexOf(u8, before, "require(") orelse {
            cursor = after;
            continue;
        };
        const var_index = std.mem.lastIndexOf(u8, before[0..require_index], "var ") orelse std.mem.lastIndexOf(u8, before[0..require_index], "const ") orelse std.mem.lastIndexOf(u8, before[0..require_index], "let ") orelse {
            cursor = after;
            continue;
        };
        var name_start = var_index;
        while (name_start < before.len and before[name_start] != ' ') : (name_start += 1) {}
        while (name_start < before.len and std.ascii.isWhitespace(before[name_start])) : (name_start += 1) {}
        var name_end = name_start;
        while (name_end < before.len and isIdentifierChar(before[name_end])) : (name_end += 1) {}
        if (name_end <= name_start) {
            cursor = after;
            continue;
        }
        const name = before[name_start..name_end];
        var pattern_buf: [128]u8 = undefined;
        if (name.len + "Object.keys().forEach".len >= pattern_buf.len) return false;
        const pattern = std.fmt.bufPrint(&pattern_buf, "Object.keys({s}).forEach", .{name}) catch return false;
        return std.mem.indexOf(u8, source[after..], pattern) != null;
    }
    return false;
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

pub fn runFiles(allocator: Allocator, io: std.Io, paths: []const []u8, setup_paths: []const []const u8, dom_mode: DomMode) !Summary {
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
        var file_result = try runSingleFile(allocator, io, path, setup_paths, dom_mode);
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

fn shouldInstallDom(
    dom_mode: DomMode,
    entry_module_id: []const u8,
    setup_module_ids: []const []u8,
) bool {
    const suffixes = switch (dom_mode) {
        .always => return true,
        .auto => defaultDomSuffixes(),
        .suffixes => |items| items,
    };

    if (pathImpliesDom(entry_module_id, suffixes)) return true;
    for (setup_module_ids) |setup_module_id| {
        if (pathImpliesDom(setup_module_id, suffixes)) return true;
    }

    return false;
}

fn pathImpliesDom(path: []const u8, suffixes: []const []const u8) bool {
    for (suffixes) |suffix| {
        if (suffix.len > 0 and std.mem.endsWith(u8, path, suffix)) return true;
    }
    return false;
}

pub fn runSingleFile(allocator: Allocator, io: std.Io, path: []const u8, setup_paths: []const []const u8, dom_mode: DomMode) !FileResult {
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

    const install_dom = shouldInstallDom(dom_mode, entry_module_id, setup_module_ids.items);

    var vm = try Runtime.initWithDom(allocator, io, install_dom);
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
    module_loader_state.entry_module_id = entry_module_id;
    active_cjs_loader_state = &module_loader_state;
    defer active_cjs_loader_state = null;

    installNativeRequire(&vm) catch |err| {
        return failureFromRuntimeException(allocator, path, "failed to initialize native CommonJS loader", err, &vm);
    };
    defer vm.evalScript(
        "<zig-cjs-cleanup>",
        "try { if (globalThis.__zigCjsRegistry) globalThis.__zigCjsRegistry.clear(); delete globalThis.__zigCjsRegistry; delete globalThis.__zigNativeRequire; delete globalThis.__zigApplyMockModuleExports; delete globalThis.__zigPatchLoadedModuleExportByNamespace; } catch {}",
    ) catch {};

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
        module_loader_state.recordStaticImportRequests(setup_module_id, setup_source) catch |err| {
            return collectionFailureFromError(allocator, path, "collection failed", err);
        };

        vm.evalScript("<zig-setup-dom-probe-begin>", setup_dom_probe_begin_source) catch |err| {
            return failureFromRuntimeException(allocator, path, "failed to prepare setup environment", err, &vm);
        };

        const setup_eval_start = if (module_loader_state.profile_enabled) module_loader_state.profileNow() else 0;
        vm.evalModule(setup_module_id, setup_source) catch |err| {
            vm.evalScript("<zig-setup-dom-probe-end>", setup_dom_probe_end_source) catch {};
            return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
        };
        while (vm.isJobPending()) {
            _ = vm.executePendingJob() catch |err| {
                vm.evalScript("<zig-setup-dom-probe-end>", setup_dom_probe_end_source) catch {};
                return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
            };
        }
        vm.evalScript("<zig-setup-dom-probe-end>", setup_dom_probe_end_source) catch |err| {
            return failureFromRuntimeException(allocator, path, "failed to restore setup environment", err, &vm);
        };
        if (module_loader_state.profile_enabled) {
            module_loader_state.profile_setup_eval_ns += module_loader_state.profileNow() - setup_eval_start;
        }
    }

    module_loader_state.syncMockModulesFromRuntime(&vm) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };

    const collect_graph_start = if (module_loader_state.profile_enabled) module_loader_state.profileNow() else 0;
    module_loader_state.collectImportGraph(entry_module_id) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };
    if (module_loader_state.profile_enabled) {
        module_loader_state.profile_collect_graph_ns += module_loader_state.profileNow() - collect_graph_start;
    }

    const entry_source = module_loader_state.loadModuleSource(entry_module_id) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };
    defer allocator.free(entry_source);
    module_loader_state.recordStaticImportRequests(entry_module_id, entry_source) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };

    const entry_eval_start = if (module_loader_state.profile_enabled) module_loader_state.profileNow() else 0;
    vm.evalModule(entry_module_id, entry_source) catch |err| {
        return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
    };

    while (vm.isJobPending()) {
        _ = vm.executePendingJob() catch |err| {
            return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
        };
    }
    if (module_loader_state.profile_enabled) {
        module_loader_state.profile_entry_eval_ns += module_loader_state.profileNow() - entry_eval_start;
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
                .expect_calls = 0,
                .passed_report = null,
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

    if (module_loader_state.profile_enabled) {
        module_loader_state.printProfileModules();
    }

    const runner_start = if (module_loader_state.profile_enabled) module_loader_state.profileNow() else 0;
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
                .expect_calls = 0,
                .passed_report = null,
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
            .expect_calls = 0,
            .passed_report = null,
            .failure_report = try allocator.dupe(u8, "Runner stalled with unresolved async work."),
            .collection_report = null,
        };
    }
    if (module_loader_state.profile_enabled) {
        module_loader_state.profile_runner_ns += module_loader_state.profileNow() - runner_start;
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
            .expect_calls = 0,
            .passed_report = null,
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

    if (passed_i32 == 0 and
        failed_i32 == 0 and
        skipped_i32 == 0 and
        timed_out_i32 == 0 and
        collection_errors_i32 == 0)
    {
        if (registered_tests_i32 == 0 and !only_mode and !has_runnable) {
            return .{
                .path = try allocator.dupe(u8, path),
                .passed = 0,
                .failed = 0,
                .skipped = 0,
                .timed_out = 0,
                .collection_errors = 0,
                .expect_calls = 0,
                .passed_report = null,
                .failure_report = null,
                .collection_report = null,
            };
        }

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
            .expect_calls = 0,
            .passed_report = null,
            .failure_report = null,
            .collection_report = diagnostic,
        };
    }

    const passed_text = vm.getGlobalStringDup("__zigPassedText") catch try allocator.dupe(u8, "");
    const failures_text = vm.getGlobalStringDup("__zigFailuresText") catch try allocator.dupe(u8, "");
    const collection_text = vm.getGlobalStringDup("__zigCollectionText") catch try allocator.dupe(u8, "");
    const expect_calls_i32 = vm.getGlobalInt32("__zigExpectCalls") catch 0;

    if (module_loader_state.profile_enabled) {
        std.debug.print(
            "[zig-dom profile] modules={d} transforms={d} transform_ms={d:.3} onload_ms={d:.3} load_source_ms={d:.3} collect_graph_ms={d:.3} setup_eval_ms={d:.3} entry_eval_ms={d:.3} runner_ms={d:.3} compile_ms={d:.3}\n",
            .{
                module_loader_state.profile_module_count,
                module_loader_state.profile_transform_count,
                @as(f64, @floatFromInt(module_loader_state.profile_transform_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_onload_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_load_source_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_collect_graph_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_setup_eval_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_entry_eval_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_runner_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_compile_ns)) / 1_000_000.0,
            },
        );
    }

    return .{
        .path = try allocator.dupe(u8, path),
        .passed = @intCast(@max(passed_i32, 0)),
        .failed = @intCast(@max(failed_i32, 0)),
        .skipped = @intCast(@max(skipped_i32, 0)),
        .timed_out = @intCast(@max(timed_out_i32, 0)),
        .collection_errors = @intCast(@max(collection_errors_i32, 0)),
        .expect_calls = @intCast(@max(expect_calls_i32, 0)),
        .passed_report = if (passed_text.len > 0) passed_text else blk: {
            allocator.free(passed_text);
            break :blk null;
        },
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

fn installNativeRequire(vm: *Runtime) !void {
    const ctx = vm.adapter.ctx;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const func = quickjs.Value.initCFunction(ctx, jsNativeRequire, "__zigNativeRequire", 3);
    if (func.isException()) return error.EvaluationFailed;
    global.setPropertyStr(ctx, "__zigNativeRequire", func) catch return error.EvaluationFailed;

    const apply_mock_exports = quickjs.Value.initCFunction(ctx, jsApplyMockModuleExports, "__zigApplyMockModuleExports", 2);
    if (apply_mock_exports.isException()) return error.EvaluationFailed;
    global.setPropertyStr(ctx, "__zigApplyMockModuleExports", apply_mock_exports) catch return error.EvaluationFailed;

    const patch_namespace_export = quickjs.Value.initCFunction(ctx, jsPatchLoadedModuleExportByNamespace, "__zigPatchLoadedModuleExportByNamespace", 3);
    if (patch_namespace_export.isException()) return error.EvaluationFailed;
    global.setPropertyStr(ctx, "__zigPatchLoadedModuleExportByNamespace", patch_namespace_export) catch return error.EvaluationFailed;

    vm.evalScript("<zig-cjs-runtime-helpers>", cjs_runtime_helpers_source) catch return error.EvaluationFailed;
}

fn jsNativeRequire(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const state = active_cjs_loader_state orelse {
        _ = quickjs.c.JS_ThrowReferenceError(ctx.cval(), "native CommonJS loader is not active");
        return quickjs.Value.exception;
    };
    if (args.len < 2) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "__zigNativeRequire expects parent and specifier");
        return quickjs.Value.exception;
    }

    const parent = dupArgString(state.allocator, ctx, args[0]) catch return quickjs.Value.exception;
    defer state.allocator.free(parent);
    const specifier = dupArgString(state.allocator, ctx, args[1]) catch return quickjs.Value.exception;
    defer state.allocator.free(specifier);
    const resolved_hint = if (args.len > 2)
        dupArgString(state.allocator, ctx, args[2]) catch return quickjs.Value.exception
    else
        state.allocator.dupe(u8, "") catch return quickjs.Value.exception;
    defer state.allocator.free(resolved_hint);

    return state.loadCommonJsValue(ctx, parent, specifier, resolved_hint) catch |err| {
        if (err == error.EvaluationFailed) {
            return quickjs.Value.exception;
        }
        _ = quickjs.c.JS_ThrowReferenceError(
            ctx.cval(),
            "native CommonJS require failed: %s from %s (%s)",
            specifier.ptr,
            parent.ptr,
            @errorName(err).ptr,
        );
        return quickjs.Value.exception;
    };
}

fn jsApplyMockModuleExports(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const state = active_cjs_loader_state orelse {
        _ = quickjs.c.JS_ThrowReferenceError(ctx.cval(), "native module loader is not active");
        return quickjs.Value.exception;
    };

    if (args.len < 2) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "__zigApplyMockModuleExports expects specifier and exports");
        return quickjs.Value.exception;
    }

    const specifier = dupArgString(state.allocator, ctx, args[0]) catch return quickjs.Value.exception;
    defer state.allocator.free(specifier);

    const maybe_resolved = state.resolveLoadedModuleIdForMockSpecifier(specifier) catch return quickjs.Value.exception;
    defer if (maybe_resolved) |resolved| state.allocator.free(resolved);

    const resolved_module_id = maybe_resolved orelse return quickjs.Value.undefined;
    const module_ptr = state.loaded_modules.get(resolved_module_id) orelse return quickjs.Value.undefined;
    const produced = quickjs.Value.fromCVal(args[1]);

    patchLoadedModuleExports(state.allocator, ctx, module_ptr, produced) catch {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "mock.module() failed to patch already-loaded module exports");
        return quickjs.Value.exception;
    };

    return quickjs.Value.undefined;
}

fn jsPatchLoadedModuleExportByNamespace(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const state = active_cjs_loader_state orelse return quickjs.Value.initBool(false);
    if (args.len < 3) return quickjs.Value.initBool(false);

    const namespace = quickjs.Value.fromCVal(args[0]);
    if (!namespace.isObject()) return quickjs.Value.initBool(false);

    const export_name = dupArgString(state.allocator, ctx, args[1]) catch return quickjs.Value.exception;
    defer state.allocator.free(export_name);
    const export_name_z = state.allocator.dupeZ(u8, export_name) catch return quickjs.Value.exception;
    defer state.allocator.free(export_name_z);

    const replacement = quickjs.Value.fromCVal(args[2]);

    var iterator = state.loaded_modules.iterator();
    while (iterator.next()) |entry| {
        const module_ptr = entry.value_ptr.*;
        const candidate_namespace = module_ptr.getNamespace(ctx);
        defer candidate_namespace.deinit(ctx);
        if (candidate_namespace.isException() or !candidate_namespace.isObject()) continue;
        if (!candidate_namespace.isSameValue(ctx, namespace)) continue;

        if (!module_ptr.setExport(ctx, export_name_z, replacement.dup(ctx))) return quickjs.Value.initBool(false);
        return quickjs.Value.initBool(true);
    }

    return quickjs.Value.initBool(false);
}

fn patchLoadedModuleExports(allocator: Allocator, ctx: *quickjs.Context, module_ptr: *ModuleDef, produced: quickjs.Value) !void {
    var module_exports = produced.dup(ctx);
    defer module_exports.deinit(ctx);

    if (!module_exports.isObject() and !module_exports.isFunction(ctx)) {
        const boxed = quickjs.Value.initObject(ctx);
        if (boxed.isException()) return error.EvaluationFailed;
        errdefer boxed.deinit(ctx);
        boxed.setPropertyStr(ctx, "default", module_exports.dup(ctx)) catch return error.EvaluationFailed;
        module_exports.deinit(ctx);
        module_exports = boxed;
    }

    const namespace = module_ptr.getNamespace(ctx);
    defer namespace.deinit(ctx);
    if (namespace.isException() or !namespace.isObject()) return error.EvaluationFailed;

    const keys = objectKeys(ctx, namespace);
    defer keys.deinit(ctx);
    const key_count = keys.getLength(ctx) catch 0;

    var index: i64 = 0;
    while (index < key_count) : (index += 1) {
        const key = keys.getPropertyUint32(ctx, @intCast(index));
        defer key.deinit(ctx);
        if (!key.isString()) continue;

        const key_text = key.toCStringLen(ctx) orelse continue;
        defer ctx.freeCString(key_text.ptr);
        const key_slice = key_text.ptr[0..key_text.len];

        const key_z = try allocator.dupeZ(u8, key_slice);
        defer allocator.free(key_z);

        const replacement = if (std.mem.eql(u8, key_slice, "default")) blk: {
            const default_value = module_exports.getPropertyStr(ctx, "default");
            if (default_value.isException()) return error.EvaluationFailed;
            if (!default_value.isUndefined()) break :blk default_value;
            default_value.deinit(ctx);
            break :blk module_exports.dup(ctx);
        } else module_exports.getPropertyStr(ctx, key_z);
        defer replacement.deinit(ctx);
        if (replacement.isException()) return error.EvaluationFailed;

        if (!module_ptr.setExport(ctx, key_z, replacement.dup(ctx))) {
            return error.EvaluationFailed;
        }
    }
}

fn objectKeys(ctx: *quickjs.Context, value: quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const object_ctor = global.getPropertyStr(ctx, "Object");
    defer object_ctor.deinit(ctx);
    const keys_fn = object_ctor.getPropertyStr(ctx, "keys");
    defer keys_fn.deinit(ctx);
    if (!keys_fn.isFunction(ctx)) return quickjs.Value.initArray(ctx);
    var args = [_]quickjs.Value{value.dup(ctx)};
    defer args[0].deinit(ctx);
    return keys_fn.call(ctx, object_ctor, &args);
}

fn dupArgString(allocator: Allocator, ctx: *quickjs.Context, value: quickjs.c.JSValue) ![]u8 {
    const js_value = quickjs.Value.fromCVal(value);
    const c_text = js_value.toCStringLen(ctx) orelse return error.ValueConversionFailed;
    defer ctx.freeCString(c_text.ptr);
    return allocator.dupe(u8, c_text.ptr[0..c_text.len]);
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

    if (loadNativeBuiltInModule(ctx, module_name)) |native_module| {
        const key = state.allocator.dupe(u8, module_id) catch {
            _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
            return null;
        };

        state.loaded_modules.put(key, native_module) catch {
            state.allocator.free(key);
            _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
            return null;
        };

        return native_module;
    }

    const load_source_start = if (state.profile_enabled) state.profileNow() else 0;
    const source = state.loadModuleSource(module_id) catch |err| {
        _ = quickjs.c.JS_ThrowReferenceError(
            ctx.cval(),
            "module loading failed: %s (%s)",
            module_name.ptr,
            @errorName(err).ptr,
        );
        return null;
    };
    if (state.profile_enabled) {
        state.profile_load_source_ns += state.profileNow() - load_source_start;
    }
    defer state.allocator.free(source);
    state.recordStaticImportRequests(module_id, source) catch {
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        return null;
    };

    const source_z = state.allocator.dupeZ(u8, source) catch {
        _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
        return null;
    };
    defer state.allocator.free(source_z);

    const compile_start = if (state.profile_enabled) state.profileNow() else 0;
    const compiled = ctx.eval(source_z[0..source.len], module_name, .{ .type = .module, .compile_only = true });
    if (state.profile_enabled) {
        const elapsed = state.profileNow() - compile_start;
        state.profile_compile_ns += elapsed;
        state.profile_module_count += 1;
        state.recordProfileModule(.module, elapsed, module_id) catch {
            _ = quickjs.c.JS_ThrowOutOfMemory(ctx.cval());
            return null;
        };
    }
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

fn loadNativeBuiltInModule(ctx: *ModuleContext, module_name: [:0]const u8) ?*ModuleDef {
    if (std.mem.eql(u8, module_name, bun_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeBunModule) orelse return null;
        if (!module.addExport(ctx, "plugin")) return null;
        if (!module.addExport(ctx, "$")) return null;
        if (!module.addExport(ctx, "file")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, bun_test_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeBunTestModule) orelse return null;
        if (!module.addExport(ctx, "test")) return null;
        if (!module.addExport(ctx, "it")) return null;
        if (!module.addExport(ctx, "describe")) return null;
        if (!module.addExport(ctx, "expect")) return null;
        if (!module.addExport(ctx, "mock")) return null;
        if (!module.addExport(ctx, "spyOn")) return null;
        if (!module.addExport(ctx, "beforeAll")) return null;
        if (!module.addExport(ctx, "beforeEach")) return null;
        if (!module.addExport(ctx, "afterEach")) return null;
        if (!module.addExport(ctx, "afterAll")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_stream_web_specifier) or std.mem.eql(u8, module_name, node_stream_web_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeStreamWebModule) orelse return null;
        if (!module.addExport(ctx, "ReadableStream")) return null;
        if (!module.addExport(ctx, "WritableStream")) return null;
        if (!module.addExport(ctx, "TransformStream")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    return null;
}

fn initNativeBunModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    return exportApiMembersAsModule(ctx, module, "__zigBunApi", &.{ "plugin", "$", "file" });
}

fn initNativeBunTestModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    return exportApiMembersAsModule(ctx, module, "__zigBunTestApi", &.{
        "test",
        "it",
        "describe",
        "expect",
        "mock",
        "spyOn",
        "beforeAll",
        "beforeEach",
        "afterEach",
        "afterAll",
    });
}

fn initNativeNodeStreamWebModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    return exportGlobalMembersAsModule(ctx, module, &.{ "ReadableStream", "WritableStream", "TransformStream" });
}

fn exportApiMembersAsModule(
    ctx: *ModuleContext,
    module: *ModuleDef,
    global_api_name: [*:0]const u8,
    comptime member_names: []const [:0]const u8,
) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const api = global.getPropertyStr(ctx, global_api_name);
    defer api.deinit(ctx);

    if (api.isException()) return false;

    if (!api.isObject()) {
        _ = quickjs.c.JS_ThrowReferenceError(ctx.cval(), "native module API is not installed: %s", global_api_name);
        return false;
    }

    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);

    if (default_export.isException()) return false;

    inline for (member_names) |member_name| {
        const member_value = api.getPropertyStr(ctx, member_name.ptr);
        defer member_value.deinit(ctx);
        if (member_value.isException()) return false;

        default_export.setPropertyStr(ctx, member_name.ptr, member_value.dup(ctx)) catch return false;
        if (!module.setExport(ctx, member_name, member_value.dup(ctx))) return false;
    }

    if (!module.setExport(ctx, "default", default_export.dup(ctx))) return false;
    return true;
}

fn exportGlobalMembersAsModule(
    ctx: *ModuleContext,
    module: *ModuleDef,
    comptime member_names: []const [:0]const u8,
) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);

    if (default_export.isException()) return false;

    inline for (member_names) |member_name| {
        const member_value = global.getPropertyStr(ctx, member_name.ptr);
        defer member_value.deinit(ctx);
        if (member_value.isException()) return false;

        default_export.setPropertyStr(ctx, member_name.ptr, member_value.dup(ctx)) catch return false;
        if (!module.setExport(ctx, member_name, member_value.dup(ctx))) return false;
    }

    if (!module.setExport(ctx, "default", default_export.dup(ctx))) return false;
    return true;
}

fn builtInModuleSource(module_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, module_name, bun_specifier)) {
        return native_builtin_stub_source;
    }

    if (std.mem.eql(u8, module_name, bun_test_specifier)) {
        return native_builtin_stub_source;
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
        return native_builtin_stub_source;
    }

    if (std.mem.eql(u8, module_name, node_vm_specifier) or std.mem.eql(u8, module_name, node_vm_colon_specifier)) {
        return node_vm_shim_source;
    }

    if (std.mem.eql(u8, module_name, node_perf_hooks_colon_specifier)) {
        return node_perf_hooks_shim_source;
    }

    return null;
}

fn isMockModuleId(module_id: []const u8) bool {
    return std.mem.startsWith(u8, module_id, "__zig_mock__/");
}

fn isRelativeSpecifier(specifier: []const u8) bool {
    return std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../");
}

fn isBarePackageRootSpecifier(specifier: []const u8) bool {
    if (specifier.len == 0) return false;
    if (isRelativeSpecifier(specifier) or std.fs.path.isAbsolute(specifier)) return false;
    if (builtInModuleSource(specifier) != null) return false;
    if (std.mem.indexOfScalar(u8, specifier, ':') != null) return false;

    if (specifier[0] == '@') {
        var slash_count: usize = 0;
        for (specifier) |ch| {
            if (ch == '/') slash_count += 1;
        }
        return slash_count == 1;
    }

    return std.mem.indexOfScalar(u8, specifier, '/') == null;
}

fn isCommonJsSource(module_id: []const u8, source: []const u8) bool {
    if (std.mem.endsWith(u8, module_id, ".cjs")) {
        return true;
    }

    if (!std.mem.endsWith(u8, module_id, ".js")) {
        return false;
    }

    if (std.mem.indexOf(u8, source, "module.exports") != null or
        std.mem.indexOf(u8, source, "exports.") != null or
        std.mem.indexOf(u8, source, "Object.defineProperty(exports") != null or
        std.mem.indexOf(u8, source, "Object.defineProperty(module") != null)
    {
        return true;
    }

    if (std.mem.indexOf(u8, source, "typeof exports") != null and
        std.mem.indexOf(u8, source, "typeof module") != null)
    {
        return true;
    }

    if (std.mem.indexOf(u8, source, "require(") == null) {
        return false;
    }

    return std.mem.indexOf(u8, source, "import ") == null and std.mem.indexOf(u8, source, "export ") == null;
}

fn foldNodeEnvConditionals(allocator: Allocator, source: []const u8) ![]u8 {
    const node_env = if (std.c.getenv("NODE_ENV")) |value| std.mem.span(value) else "test";
    const is_production = std.mem.eql(u8, node_env, "production");

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < source.len) {
        const match = findNodeEnvConditional(source, cursor) orelse {
            try out.appendSlice(allocator, source[cursor..]);
            break;
        };

        try out.appendSlice(allocator, source[cursor..match.start]);
        const take_then = if (match.equals_production) is_production else !is_production;
        try out.appendSlice(allocator, if (take_then) match.then_body else match.else_body);
        cursor = match.end;
    }

    return out.toOwnedSlice(allocator);
}

fn rewriteKnownCommonJsPackageImports(state: *ModuleLoaderState, module_id: []const u8, source: []const u8) ![]u8 {
    if (try rewriteCommonJsRootBarrelRequire(state, module_id, source)) |rewritten| {
        return rewritten;
    }
    return state.allocator.dupe(u8, source);
}

fn rewriteCommonJsRootBarrelRequire(state: *ModuleLoaderState, module_id: []const u8, source: []const u8) !?[]u8 {
    const require_index = findBareRootRequire(source) orelse return null;
    const specifier = parseRequireSpecifierAt(source, require_index) orelse return null;
    const binding = findCommonJsRequireBinding(source, require_index) orelse return null;
    const root_module_id = state.normalizeRequireSpecifier(module_id, specifier) catch return null;
    defer state.allocator.free(root_module_id);
    if (std.mem.eql(u8, root_module_id, module_id)) return null;

    const root_source = state.readFileCached(root_module_id, max_module_source_bytes) catch return null;
    if (!isCommonJsSource(root_module_id, root_source)) return null;

    var rewrites: std.ArrayList(CommonJsBarrelPropertyRewrite) = .empty;
    defer {
        for (rewrites.items) |*rewrite| rewrite.deinit(state.allocator);
        rewrites.deinit(state.allocator);
    }

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, binding)) |binding_index| {
        const after_binding = binding_index + binding.len;
        if ((binding_index == 0 or !isIdentifierContinue(source[binding_index - 1])) and
            after_binding < source.len and
            source[after_binding] == '.' and
            after_binding + 1 < source.len and
            isIdentifierContinue(source[after_binding + 1]))
        {
            const prop_start = after_binding + 1;
            const prop_end = readIdentifierEnd(source, prop_start);
            const name = source[prop_start..prop_end];
            if (!barrelRewriteListContains(rewrites.items, name)) {
                const rewrite = try commonJsBarrelRewriteForExport(state, root_module_id, root_source, name) orelse return null;
                try rewrites.append(state.allocator, rewrite);
            }
            cursor = prop_end;
            continue;
        }
        cursor = after_binding;
    }

    if (rewrites.items.len == 0) return null;

    var replacement: std.ArrayList(u8) = .empty;
    errdefer replacement.deinit(state.allocator);
    try appendFmt(state.allocator, &replacement, "var {s} = {{", .{binding});
    for (rewrites.items, 0..) |rewrite, index| {
        if (index > 0) try replacement.appendSlice(state.allocator, ",");
        try appendFmt(
            state.allocator,
            &replacement,
            "\n  {s}: require(\"{s}\").{s}",
            .{ rewrite.export_name, rewrite.resolved_specifier, rewrite.member_name },
        );
    }
    try replacement.appendSlice(state.allocator, "\n}");
    const replacement_source = try replacement.toOwnedSlice(state.allocator);
    defer state.allocator.free(replacement_source);

    const statement_start = findStatementStart(source, require_index);
    const statement_end = findStatementEnd(source, statement_start);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(state.allocator);
    try out.appendSlice(state.allocator, source[0..statement_start]);
    try out.appendSlice(state.allocator, replacement_source);
    if (statement_end < source.len and source[statement_end] == ';') {
        try out.append(state.allocator, ';');
        try out.appendSlice(state.allocator, source[statement_end + 1 ..]);
    } else {
        try out.appendSlice(state.allocator, source[statement_end..]);
    }
    return try out.toOwnedSlice(state.allocator);
}

fn findBareRootRequire(source: []const u8) ?usize {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "require(")) |index| {
        const specifier = parseRequireSpecifierAt(source, index) orelse {
            cursor = index + "require(".len;
            continue;
        };
        if (isBarePackageRootSpecifier(specifier) and findCommonJsRequireBinding(source, index) != null) {
            return index;
        }
        cursor = index + "require(".len;
    }
    return null;
}

const CommonJsBarrelPropertyRewrite = struct {
    export_name: []u8,
    resolved_specifier: []u8,
    member_name: []u8,

    fn deinit(self: *CommonJsBarrelPropertyRewrite, allocator: Allocator) void {
        allocator.free(self.export_name);
        allocator.free(self.resolved_specifier);
        allocator.free(self.member_name);
    }
};

fn barrelRewriteListContains(items: []const CommonJsBarrelPropertyRewrite, name: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item.export_name, name)) return true;
    }
    return false;
}

fn commonJsBarrelRewriteForExport(
    state: *ModuleLoaderState,
    root_module_id: []const u8,
    root_source: []const u8,
    name: []const u8,
) !?CommonJsBarrelPropertyRewrite {
    const export_index = findDefinePropertyExport(root_source, name) orelse return null;
    const statement_end = findStatementEnd(root_source, export_index);
    const statement = root_source[export_index..statement_end];
    const return_index = std.mem.indexOf(u8, statement, "return ") orelse return null;
    const return_expr = std.mem.trim(u8, statement[return_index + "return ".len ..], " \t\r\n;");
    const dot_index = std.mem.indexOfScalar(u8, return_expr, '.') orelse return null;
    const local = return_expr[0..dot_index];
    if (local.len == 0 or !std.mem.startsWith(u8, local, "_")) return null;
    const member_start = dot_index + 1;
    const member_end = readIdentifierEnd(return_expr, member_start);
    if (member_end == member_start) return null;
    const member = return_expr[member_start..member_end];
    const required = findCommonJsLocalRequireSpecifier(root_source, local) orelse return null;
    const resolved = try state.normalizeRequireSpecifier(root_module_id, required);
    errdefer state.allocator.free(resolved);
    return .{
        .export_name = try state.allocator.dupe(u8, name),
        .resolved_specifier = resolved,
        .member_name = try state.allocator.dupe(u8, member),
    };
}

fn findDefinePropertyExport(source: []const u8, name: []const u8) ?usize {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "Object.defineProperty(exports,")) |index| {
        if (parseDefinePropertyExportName(source[index..])) |export_name| {
            if (std.mem.eql(u8, export_name, name)) return index;
        }
        cursor = index + "Object.defineProperty(exports,".len;
    }
    return null;
}

fn findCommonJsLocalRequireSpecifier(source: []const u8, local: []const u8) ?[]const u8 {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "require(")) |require_index| {
        const binding = findCommonJsRequireBinding(source, require_index) orelse {
            cursor = require_index + "require(".len;
            continue;
        };
        if (std.mem.eql(u8, binding, local)) {
            return parseRequireSpecifierAt(source, require_index);
        }
        cursor = require_index + "require(".len;
    }
    return null;
}

fn findStatementStart(source: []const u8, index: usize) usize {
    var cursor = index;
    while (cursor > 0 and source[cursor - 1] != '\n' and source[cursor - 1] != ';') : (cursor -= 1) {}
    return cursor;
}

const NodeEnvConditional = struct {
    start: usize,
    end: usize,
    equals_production: bool,
    then_body: []const u8,
    else_body: []const u8,
};

fn findNodeEnvConditional(source: []const u8, start: usize) ?NodeEnvConditional {
    const equality_pattern = "if (process.env.NODE_ENV === 'production')";
    const inequality_pattern = "if (process.env.NODE_ENV !== 'production')";

    var cursor = start;
    while (cursor < source.len) {
        const equality_index = std.mem.indexOfPos(u8, source, cursor, equality_pattern);
        const inequality_index = std.mem.indexOfPos(u8, source, cursor, inequality_pattern);

        const match_start, const pattern_len, const equals_production = blk: {
            if (equality_index == null and inequality_index == null) return null;
            if (equality_index) |eq| {
                if (inequality_index == null or eq < inequality_index.?) {
                    break :blk .{ eq, equality_pattern.len, true };
                }
            }
            break :blk .{ inequality_index.?, inequality_pattern.len, false };
        };

        var then_open = match_start + pattern_len;
        while (then_open < source.len and std.ascii.isWhitespace(source[then_open])) : (then_open += 1) {}
        if (then_open >= source.len or source[then_open] != '{') {
            cursor = match_start + 1;
            continue;
        }

        const then_close = findMatchingBrace(source, then_open) orelse {
            cursor = match_start + 1;
            continue;
        };
        var else_index = then_close + 1;
        while (else_index < source.len and std.ascii.isWhitespace(source[else_index])) : (else_index += 1) {}
        if (!std.mem.startsWith(u8, source[else_index..], "else")) {
            cursor = match_start + 1;
            continue;
        }

        var else_open = else_index + "else".len;
        while (else_open < source.len and std.ascii.isWhitespace(source[else_open])) : (else_open += 1) {}
        if (else_open >= source.len or source[else_open] != '{') {
            cursor = match_start + 1;
            continue;
        }

        const else_close = findMatchingBrace(source, else_open) orelse {
            cursor = match_start + 1;
            continue;
        };
        return .{
            .start = match_start,
            .end = else_close + 1,
            .equals_production = equals_production,
            .then_body = source[then_open + 1 .. then_close],
            .else_body = source[else_open + 1 .. else_close],
        };
    }

    return null;
}

fn findMatchingBrace(source: []const u8, open_index: usize) ?usize {
    if (open_index >= source.len or source[open_index] != '{') return null;

    var depth: usize = 0;
    var cursor = open_index;
    var quote: ?u8 = null;
    var escaped = false;

    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (quote) |q| {
            if (escaped) {
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == q) {
                quote = null;
            }
            continue;
        }

        if (ch == '"' or ch == '\'' or ch == '`') {
            quote = ch;
            continue;
        }

        if (ch == '{') {
            depth += 1;
        } else if (ch == '}') {
            depth -= 1;
            if (depth == 0) return cursor;
        }
    }

    return null;
}

fn looksLikeJsxSource(source: []const u8) bool {
    return std.mem.indexOf(u8, source, "<") != null and
        (std.mem.indexOf(u8, source, "/>") != null or std.mem.indexOf(u8, source, "</") != null);
}

fn pruneUnusedImports(allocator: Allocator, source: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < source.len) {
        if (source[cursor] == ' ' or source[cursor] == '\t' or source[cursor] == '\n' or source[cursor] == '\r') {
            try out.append(allocator, source[cursor]);
            cursor += 1;
            continue;
        }

        if (std.mem.startsWith(u8, source[cursor..], "import ")) {
            const statement_end = findImportStatementEnd(source, cursor);
            const statement = source[cursor..statement_end];
            if (isUnusedImportStatement(source, statement, statement_end)) {
                cursor = statement_end;
                if (cursor < source.len and source[cursor] == ';') cursor += 1;
                continue;
            }

            try out.appendSlice(allocator, source[cursor..statement_end]);
            cursor = statement_end;
            if (cursor < source.len and source[cursor] == ';') {
                try out.append(allocator, source[cursor]);
                cursor += 1;
            }
            continue;
        }

        try out.append(allocator, source[cursor]);
        cursor += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn findImportStatementEnd(source: []const u8, start: usize) usize {
    var cursor = start;
    var quote: ?u8 = null;
    var escaped = false;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (quote) |q| {
            if (escaped) {
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == q) {
                quote = null;
            }
            continue;
        }
        if (ch == '"' or ch == '\'' or ch == '`') {
            quote = ch;
            continue;
        }
        if (ch == ';') return cursor;
    }
    return source.len;
}

const ParsedImportStatement = struct {
    specifier: []const u8,
    bindings: []const u8,
    all: bool,
};

fn parseImportStatement(statement: []const u8) ?ParsedImportStatement {
    const trimmed = std.mem.trim(u8, statement, " \t\r\n;");
    if (!std.mem.startsWith(u8, trimmed, "import")) return null;
    if (!hasWordAt(trimmed, 0, "import")) return null;
    const rest = std.mem.trim(u8, trimmed["import".len..], " \t\r\n");

    if (rest.len > 0 and (rest[0] == '"' or rest[0] == '\'')) {
        const specifier = parseImportQuotedSpecifier(rest) orelse return null;
        return .{ .specifier = specifier, .bindings = "", .all = true };
    }

    const from_index = findImportFromIndex(rest) orelse return null;
    const bindings = std.mem.trim(u8, rest[0..from_index], " \t\r\n");
    const from_rest = std.mem.trim(u8, rest[from_index + "from".len ..], " \t\r\n");
    const specifier = parseImportQuotedSpecifier(from_rest) orelse return null;
    return .{
        .specifier = specifier,
        .bindings = bindings,
        .all = std.mem.startsWith(u8, bindings, "* as "),
    };
}

fn findImportFromIndex(source: []const u8) ?usize {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "from")) |index| {
        const before_ok = index == 0 or !isIdentifierContinue(source[index - 1]);
        const after = index + "from".len;
        const after_ok = after >= source.len or !isIdentifierContinue(source[after]);
        if (before_ok and after_ok) return index;
        cursor = after;
    }
    return null;
}

fn parseImportQuotedSpecifier(source: []const u8) ?[]const u8 {
    if (source.len < 2) return null;
    const quote = source[0];
    if (quote != '"' and quote != '\'') return null;
    var cursor: usize = 1;
    while (cursor < source.len) : (cursor += 1) {
        if (source[cursor] == quote) return source[1..cursor];
    }
    return null;
}

fn parseRequireSpecifierAt(source: []const u8, require_index: usize) ?[]const u8 {
    if (!std.mem.startsWith(u8, source[require_index..], "require(")) return null;
    var cursor = require_index + "require(".len;
    while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}
    if (cursor >= source.len or (source[cursor] != '"' and source[cursor] != '\'')) return null;
    return parseImportQuotedSpecifier(source[cursor..]);
}

fn findCommonJsRequireBinding(source: []const u8, require_index: usize) ?[]const u8 {
    var line_start = require_index;
    while (line_start > 0 and source[line_start - 1] != '\n' and source[line_start - 1] != ';') : (line_start -= 1) {}
    const prefix = std.mem.trim(u8, source[line_start..require_index], " \t\r\n");
    if (!std.mem.startsWith(u8, prefix, "var ")) return null;
    const after_var = std.mem.trim(u8, prefix["var ".len..], " \t\r\n");
    const name_end = readIdentifierEnd(after_var, 0);
    if (name_end == 0) return null;
    const after_name = std.mem.trim(u8, after_var[name_end..], " \t\r\n");
    if (!std.mem.startsWith(u8, after_name, "=")) return null;
    return after_var[0..name_end];
}

fn commonJsRequireBindingNeedsAllExports(source: []const u8, local: []const u8) bool {
    var stack_buffer: [256]u8 = undefined;
    if (local.len + "Object.keys()".len > stack_buffer.len) return true;
    const object_keys = std.fmt.bufPrint(&stack_buffer, "Object.keys({s})", .{local}) catch return true;
    if (std.mem.indexOf(u8, source, object_keys) != null) return true;

    const object_entries = std.fmt.bufPrint(&stack_buffer, "Object.entries({s})", .{local}) catch return true;
    if (std.mem.indexOf(u8, source, object_entries) != null) return true;

    const own_names = std.fmt.bufPrint(&stack_buffer, "Object.getOwnPropertyNames({s})", .{local}) catch return true;
    return std.mem.indexOf(u8, source, own_names) != null;
}

fn pruneUnrequestedTsExports(allocator: Allocator, source: []const u8, requested: *const ExportNameSet) ![]u8 {
    if (requested.all) return allocator.dupe(u8, source);

    const preserve_dependencies = shouldPreserveExportDependencyScan(source);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < source.len) {
        if (std.mem.startsWith(u8, source[cursor..], "export const ")) {
            const name_start = cursor + "export const ".len;
            const name_end = readIdentifierEnd(source, name_start);
            if (name_end > name_start) {
                const name = source[name_start..name_end];
                const statement_end = findStatementEnd(source, cursor);
                // Keep exported declarations that are still referenced by retained code.
                if (!requested.contains(name) and (!preserve_dependencies or !identifierUsedAfter(source, statement_end, name))) {
                    cursor = statement_end;
                    if (cursor < source.len and source[cursor] == ';') cursor += 1;
                    continue;
                }
            }
        }

        try out.append(allocator, source[cursor]);
        cursor += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn shouldPreserveExportDependencyScan(source: []const u8) bool {
    // Avoid quadratic scans for very large generated export files (for example,
    // icon barrels created by onLoad hooks). For regular source files we still
    // preserve transitive exported-const dependencies.
    if (source.len <= 128 * 1024) return true;

    var export_count: usize = 0;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "export const ")) |start| {
        export_count += 1;
        if (export_count >= 256) return false;
        cursor = start + "export const ".len;
    }

    return true;
}

fn pruneUnrequestedCommonJsExports(allocator: Allocator, source: []const u8, requested: *const ExportNameSet) ![]u8 {
    if (requested.all) return allocator.dupe(u8, source);
    if (!hasPrunableDefinePropertyExport(source)) {
        return allocator.dupe(u8, source);
    }

    const exports_pruned = try pruneUnrequestedCommonJsExportAssignments(allocator, source, requested);
    defer allocator.free(exports_pruned);
    const vars_pruned = try pruneUnusedVarDeclarations(allocator, exports_pruned);
    defer allocator.free(vars_pruned);
    return pruneUnusedVarDeclarations(allocator, vars_pruned);
}

fn pruneUnrequestedCommonJsExportAssignments(allocator: Allocator, source: []const u8, requested: *const ExportNameSet) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < source.len) {
        if (std.mem.startsWith(u8, source[cursor..], "Object.defineProperty(exports,")) {
            const name = parseDefinePropertyExportName(source[cursor..]);
            const statement_end = findStatementEnd(source, cursor);
            if (name) |export_name| {
                if (!requested.contains(export_name) and !std.mem.eql(u8, export_name, "__esModule") and startsStatementAt(source, cursor)) {
                    cursor = statement_end;
                    if (cursor < source.len and source[cursor] == ';') cursor += 1;
                    continue;
                }
            }
        }

        try out.append(allocator, source[cursor]);
        cursor += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn hasPrunableDefinePropertyExport(source: []const u8) bool {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "Object.defineProperty(exports,")) |index| {
        if (parseDefinePropertyExportName(source[index..])) |name| {
            if (!std.mem.eql(u8, name, "__esModule")) return true;
        }
        cursor = index + "Object.defineProperty(exports,".len;
    }
    return false;
}

fn parseDefinePropertyExportName(source: []const u8) ?[]const u8 {
    const prefix = "Object.defineProperty(exports,";
    if (!std.mem.startsWith(u8, source, prefix)) return null;
    var cursor = prefix.len;
    while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) : (cursor += 1) {}
    if (cursor >= source.len or (source[cursor] != '"' and source[cursor] != '\'')) return null;
    return parseImportQuotedSpecifier(source[cursor..]);
}

fn pruneUnusedVarDeclarations(allocator: Allocator, source: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < source.len) {
        if (std.mem.startsWith(u8, source[cursor..], "var ")) {
            const name_start = cursor + "var ".len;
            const name_end = readIdentifierEnd(source, name_start);
            if (name_end > name_start) {
                const name = source[name_start..name_end];
                const statement_end = findStatementEnd(source, cursor);
                if (!identifierUsedAfter(source, statement_end, name)) {
                    cursor = statement_end;
                    if (cursor < source.len and source[cursor] == ';') cursor += 1;
                    continue;
                }
            }
        }

        try out.append(allocator, source[cursor]);
        cursor += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn pruneUnusedTsConstDeclarations(allocator: Allocator, source: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < source.len) {
        if (std.mem.startsWith(u8, source[cursor..], "const ") and !isExportedConstPrefix(source, cursor)) {
            const name_start = cursor + "const ".len;
            const name_end = readIdentifierEnd(source, name_start);
            if (name_end > name_start) {
                const name = source[name_start..name_end];
                const statement_end = findStatementEnd(source, cursor);
                if (!identifierUsedAfter(source, statement_end, name)) {
                    cursor = statement_end;
                    if (cursor < source.len and source[cursor] == ';') cursor += 1;
                    continue;
                }
            }
        }

        try out.append(allocator, source[cursor]);
        cursor += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn isExportedConstPrefix(source: []const u8, const_index: usize) bool {
    if (const_index < "export ".len) return false;
    return std.mem.eql(u8, source[const_index - "export ".len .. const_index], "export ");
}

fn readIdentifierEnd(source: []const u8, start: usize) usize {
    var cursor = start;
    while (cursor < source.len and isIdentifierContinue(source[cursor])) : (cursor += 1) {}
    return cursor;
}

fn findStatementEnd(source: []const u8, start: usize) usize {
    var cursor = start;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var quote: ?u8 = null;
    var escaped = false;

    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (quote) |q| {
            if (escaped) {
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == q) {
                quote = null;
            }
            continue;
        }

        if (ch == '"' or ch == '\'' or ch == '`') {
            quote = ch;
            continue;
        }

        switch (ch) {
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth > 0) brace_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            ';' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) return cursor;
            },
            '\n' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) return cursor;
            },
            else => {},
        }
    }

    return source.len;
}

fn startsStatementAt(source: []const u8, index: usize) bool {
    var cursor = index;
    while (cursor > 0) {
        cursor -= 1;
        switch (source[cursor]) {
            ' ', '\t', '\r' => continue,
            '\n', ';', '{', '}' => return true,
            else => return false,
        }
    }
    return true;
}

fn isUnusedImportStatement(source: []const u8, statement: []const u8, statement_end: usize) bool {
    const trimmed = std.mem.trim(u8, statement, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, "import ")) return false;
    if (findImportFromIndex(trimmed) == null) return false;

    const bindings_start = "import ".len;
    const from_index = findImportFromIndex(trimmed) orelse return false;
    const bindings = std.mem.trim(u8, trimmed[bindings_start..from_index], " \t");
    if (bindings.len == 0 or std.mem.eql(u8, bindings, "type")) return true;
    if (std.mem.startsWith(u8, bindings, "{") and std.mem.endsWith(u8, bindings, "}")) {
        var inner = std.mem.tokenizeScalar(u8, bindings[1 .. bindings.len - 1], ',');
        while (inner.next()) |raw_part| {
            const part = std.mem.trim(u8, raw_part, " \t");
            if (part.len == 0 or std.mem.startsWith(u8, part, "type ")) continue;
            const as_index = std.mem.indexOf(u8, part, " as ");
            const name = std.mem.trim(u8, if (as_index) |idx| part[idx + " as ".len ..] else part, " \t");
            if (identifierUsedAfter(source, statement_end, name)) return false;
        }
        return true;
    }

    if (std.mem.startsWith(u8, bindings, "* as ")) {
        return !identifierUsedAfter(source, statement_end, std.mem.trim(u8, bindings["* as ".len..], " \t"));
    }

    if (std.mem.indexOfScalar(u8, bindings, ',') == null) {
        return !identifierUsedAfter(source, statement_end, bindings);
    }

    return false;
}

fn identifierUsedAfter(source: []const u8, start: usize, identifier: []const u8) bool {
    if (identifier.len == 0) return false;
    var cursor = start;
    while (std.mem.indexOf(u8, source[cursor..], identifier)) |relative| {
        const index = cursor + relative;
        const before_ok = index == 0 or !isIdentifierContinue(source[index - 1]);
        const after = index + identifier.len;
        const after_ok = after >= source.len or !isIdentifierContinue(source[after]);
        if (before_ok and after_ok) return true;
        cursor = after;
    }
    return false;
}

fn isIdentifierContinue(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$';
}

fn isValidIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    const first = name[0];
    if (!(std.ascii.isAlphabetic(first) or first == '_' or first == '$')) return false;
    for (name[1..]) |ch| {
        if (!isIdentifierContinue(ch)) return false;
    }
    return true;
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

test "pruneUnusedImports removes only unused import statements" {
    const source = "import { unused } from \"pkg\";export const value = 1;\n";
    const out = try pruneUnusedImports(std.testing.allocator, source);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("export const value = 1;\n", out);
}

test "foldNodeEnvConditionals keeps only active CommonJS branch" {
    const source =
        \\if (process.env.NODE_ENV !== 'production') {
        \\  checkDCE();
        \\}
        \\if (process.env.NODE_ENV === 'production') {
        \\  module.exports = require('./prod.js');
        \\} else {
        \\  module.exports = require('./dev.js');
        \\}
    ;
    const out = try foldNodeEnvConditionals(std.testing.allocator, source);
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "require('./dev.js')") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "require('./prod.js')") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "checkDCE") != null);
}

test "onLoad tree shake prunes unrequested exports before transform" {
    var requested = ExportNameSet.init();
    defer requested.deinit(std.testing.allocator);
    try requested.add(std.testing.allocator, "used");

    const source =
        \\import { darken } from "polished";
        \\export const used = "used";
        \\export const unused = darken(0.2, "#fff");
        \\const helper = darken(0.1, "#000");
    ;
    const export_pruned = try pruneUnrequestedTsExports(std.testing.allocator, source, &requested);
    defer std.testing.allocator.free(export_pruned);
    const const_pruned = try pruneUnusedTsConstDeclarations(std.testing.allocator, export_pruned);
    defer std.testing.allocator.free(const_pruned);
    const import_pruned = try pruneUnusedImports(std.testing.allocator, const_pruned);
    defer std.testing.allocator.free(import_pruned);

    try std.testing.expect(std.mem.indexOf(u8, import_pruned, "export const used") != null);
    try std.testing.expect(std.mem.indexOf(u8, import_pruned, "unused") == null);
    try std.testing.expect(std.mem.indexOf(u8, import_pruned, "helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, import_pruned, "darken") == null);
}

test "onLoad tree shake keeps referenced exported const dependencies" {
    var requested = ExportNameSet.init();
    defer requested.deinit(std.testing.allocator);
    try requested.add(std.testing.allocator, "derived");

    const source =
        \\export const base = { color: "#fff" };
        \\const local = base.color;
        \\export const derived = local;
    ;

    const export_pruned = try pruneUnrequestedTsExports(std.testing.allocator, source, &requested);
    defer std.testing.allocator.free(export_pruned);
    const const_pruned = try pruneUnusedTsConstDeclarations(std.testing.allocator, export_pruned);
    defer std.testing.allocator.free(const_pruned);

    try std.testing.expect(std.mem.indexOf(u8, const_pruned, "export const base") != null);
    try std.testing.expect(std.mem.indexOf(u8, const_pruned, "export const derived") != null);
}

test "CommonJS export pruning removes unrequested defineProperty barrels" {
    var requested = ExportNameSet.init();
    defer requested.deinit(std.testing.allocator);
    try requested.add(std.testing.allocator, "Avatar");

    const source =
        \\Object.defineProperty(exports, "__esModule", { value: true });
        \\Object.defineProperty(exports, "Avatar", {
        \\  enumerable: true,
        \\  get: function () { return _Avatar.default; }
        \\});
        \\Object.defineProperty(exports, "Button", {
        \\  enumerable: true,
        \\  get: function () { return _Button.default; }
        \\});
        \\var _Avatar = require("./Avatar");
        \\var _Button = require("./Button");
    ;
    const pruned = try pruneUnrequestedCommonJsExports(std.testing.allocator, source, &requested);
    defer std.testing.allocator.free(pruned);

    try std.testing.expect(std.mem.indexOf(u8, pruned, "__esModule") != null);
    try std.testing.expect(std.mem.indexOf(u8, pruned, "Avatar") != null);
    try std.testing.expect(std.mem.indexOf(u8, pruned, "Button") == null);
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
        .expect_calls = 0,
        .passed_report = null,
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
        .expect_calls = 0,
        .passed_report = null,
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
        .expect_calls = 0,
        .passed_report = null,
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
    try std.testing.expect(builtInModuleSource("zig-dom") == null);
    try std.testing.expect(builtInModuleSource("react") == null);
    try std.testing.expect(builtInModuleSource("@testing-library/react") == null);
}

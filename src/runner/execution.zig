const std = @import("std");
const runtime_pkg = @import("../runtime.zig");
const transform = @import("transform.zig");
const traversal = @import("traversal.zig");
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
    \\try {
    \\  globalThis.__zigRunner.run();
    \\  globalThis.__zigDone = true;
    \\} catch (error) {
    \\  const details = error && error.stack ? String(error.stack) : String(error);
    \\  globalThis.__zigRunError = details;
    \\  globalThis.__zigDone = true;
    \\}
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
    \\globalThis.__zigSetupDocumentSaved = undefined;
    \\try {
    \\  if (globalThis.document && globalThis.document.nodeName) {
    \\    globalThis.__zigSetupDocumentSaved = globalThis.document;
    \\    globalThis.document = new Proxy(globalThis.document, {
    \\      get(target, prop, receiver) {
    \\        if (prop === "nodeName") return undefined;
    \\        return Reflect.get(target, prop, receiver);
    \\      }
    \\    });
    \\    globalThis.__zigSetupDocumentNodeNameHidden = true;
    \\  }
    \\} catch {}
;

const setup_dom_probe_end_source =
    \\try {
    \\  if (globalThis.__zigSetupDocumentNodeNameHidden && globalThis.__zigSetupDocumentSaved) {
    \\    globalThis.document = globalThis.__zigSetupDocumentSaved;
    \\  }
    \\} catch {}
    \\globalThis.__zigSetupDocumentSaved = undefined;
    \\globalThis.__zigSetupDocumentNodeNameHidden = false;
;

const sync_window_globals_source =
    \\try {
    \\  if (globalThis.window && globalThis.window !== globalThis) {
    \\    const names = Object.getOwnPropertyNames(globalThis.window);
    \\    for (const name of names) {
    \\      if (name in globalThis) continue;
    \\      Object.defineProperty(globalThis, name, {
    \\        configurable: true,
    \\        enumerable: true,
    \\        get() { return globalThis.window[name]; },
    \\        set(value) { globalThis.window[name] = value; },
    \\      });
    \\    }
    \\  }
    \\} catch {}
;

const bun_specifier = "bun";
const bun_test_specifier = "bun:test";
const happy_dom_global_registrator_specifier = "@happy-dom/global-registrator";
const testing_library_dom_specifier = "@testing-library/dom";
const testing_library_react_specifier = "@testing-library/react";
const node_url_specifier = "url";
const node_url_colon_specifier = "node:url";
const node_assert_specifier = "assert";
const node_assert_colon_specifier = "node:assert";
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
const node_perf_hooks_specifier = "perf_hooks";
const node_perf_hooks_colon_specifier = "node:perf_hooks";
const node_specifier_prefix = "node:";

const native_node_builtin_specifiers = [_][]const u8{
    node_assert_specifier,
    node_url_specifier,
    node_fs_specifier,
    node_path_specifier,
    node_util_specifier,
    node_buffer_specifier,
    node_crypto_specifier,
    node_http_specifier,
    node_https_specifier,
    node_net_specifier,
    node_zlib_specifier,
    node_child_process_specifier,
    node_stream_specifier,
    node_stream_web_specifier,
    node_vm_specifier,
    node_perf_hooks_specifier,
};

const native_builtin_stub_source =
    \\export {};
;

const testing_library_dom_export_names = [_][:0]const u8{
    "screen",
    "within",
    "queries",
    "queryByText",
    "queryAllByText",
    "getByText",
    "getAllByText",
    "findByText",
    "findAllByText",
    "queryByTestId",
    "queryAllByTestId",
    "getByTestId",
    "getAllByTestId",
    "findByTestId",
    "findAllByTestId",
    "queryByLabelText",
    "queryAllByLabelText",
    "getByLabelText",
    "getAllByLabelText",
    "findByLabelText",
    "findAllByLabelText",
    "queryByRole",
    "queryAllByRole",
    "getByRole",
    "getAllByRole",
    "findByRole",
    "findAllByRole",
    "queryByDisplayValue",
    "queryAllByDisplayValue",
    "getByDisplayValue",
    "getAllByDisplayValue",
    "findByDisplayValue",
    "findAllByDisplayValue",
    "queryByPlaceholderText",
    "queryAllByPlaceholderText",
    "getByPlaceholderText",
    "getAllByPlaceholderText",
    "findByPlaceholderText",
    "findAllByPlaceholderText",
    "queryByTitle",
    "queryAllByTitle",
    "getByTitle",
    "getAllByTitle",
    "findByTitle",
    "findAllByTitle",
    "queryByAltText",
    "queryAllByAltText",
    "getByAltText",
    "getAllByAltText",
    "findByAltText",
    "findAllByAltText",
    "fireEvent",
    "cleanup",
    "getConfig",
    "configure",
    "setConfig",
    "waitFor",
    "waitForElementToBeRemoved",
};

const testing_library_react_export_names = [_][:0]const u8{
    "render",
    "renderHook",
    "screen",
    "within",
    "queries",
    "queryByText",
    "queryAllByText",
    "getByText",
    "getAllByText",
    "findByText",
    "findAllByText",
    "queryByTestId",
    "queryAllByTestId",
    "getByTestId",
    "getAllByTestId",
    "findByTestId",
    "findAllByTestId",
    "queryByLabelText",
    "queryAllByLabelText",
    "getByLabelText",
    "getAllByLabelText",
    "findByLabelText",
    "findAllByLabelText",
    "queryByRole",
    "queryAllByRole",
    "getByRole",
    "getAllByRole",
    "findByRole",
    "findAllByRole",
    "queryByDisplayValue",
    "queryAllByDisplayValue",
    "getByDisplayValue",
    "getAllByDisplayValue",
    "findByDisplayValue",
    "findAllByDisplayValue",
    "queryByPlaceholderText",
    "queryAllByPlaceholderText",
    "getByPlaceholderText",
    "getAllByPlaceholderText",
    "findByPlaceholderText",
    "findAllByPlaceholderText",
    "queryByTitle",
    "queryAllByTitle",
    "getByTitle",
    "getAllByTitle",
    "findByTitle",
    "findAllByTitle",
    "queryByAltText",
    "queryAllByAltText",
    "getByAltText",
    "getAllByAltText",
    "findByAltText",
    "findAllByAltText",
    "fireEvent",
    "cleanup",
    "getConfig",
    "configure",
    "setConfig",
    "waitFor",
    "waitForElementToBeRemoved",
    "act",
};

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

    const OnLoadTransformCacheKey = struct {
        loader_tag: u8,
        dir_hash: u64,
        content_hash: u64,
        content_len: usize,
    };

    allocator: Allocator,
    io: std.Io,
    runtime: ?*Runtime,
    entry_module_id: []const u8,
    loaded_modules: std.StringHashMap(*ModuleDef),
    source_cache: std.StringHashMap([]u8),
    onload_transform_cache: std.AutoHashMap(OnLoadTransformCacheKey, []u8),
    specifier_cache: std.StringHashMap([]u8),
    require_specifier_cache: std.StringHashMap([]u8),
    cjs_lazy_compat_cache: std.StringHashMap(bool),
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
    profile_normalize_calls: usize,
    profile_normalize_ns: i128,
    profile_normalize_failures: usize,
    profile_normalize_builtin_hits: usize,
    profile_normalize_mock_hits: usize,
    profile_normalize_alias_hits: usize,
    profile_normalize_absolute_hits: usize,
    profile_normalize_relative_hits: usize,
    profile_normalize_node_module_hits: usize,
    profile_resolve_node_module_calls: usize,
    profile_resolve_node_module_ns: i128,
    profile_resolve_node_module_hits: usize,
    profile_resolve_node_module_misses: usize,
    profile_resolve_node_module_dirs_scanned: usize,
    profile_resolve_node_module_require_calls: usize,
    profile_resolve_node_module_require_ns: i128,
    profile_resolve_node_module_require_hits: usize,
    profile_resolve_node_module_require_misses: usize,
    profile_resolve_node_module_require_dirs_scanned: usize,
    profile_source_cache_calls: usize,
    profile_source_cache_hits: usize,
    profile_source_cache_misses: usize,
    profile_source_cache_read_ns: i128,
    profile_source_cache_read_bytes: usize,
    profile_import_scan_calls: usize,
    profile_import_scan_ns: i128,
    profile_import_scan_statements: usize,
    profile_import_scan_resolved: usize,
    profile_import_scan_resolve_failures: usize,
    profile_import_graph_modules: usize,
    profile_rewrite_named_import_calls: usize,
    profile_rewrite_named_import_ns: i128,
    profile_rewrite_named_import_replacements: usize,
    profile_load_module_source_calls: usize,
    profile_load_builtin_count: usize,
    profile_load_mock_count: usize,
    profile_load_onload_hit_count: usize,
    profile_load_onload_miss_count: usize,
    profile_load_js_count: usize,
    profile_load_cjs_count: usize,
    profile_load_json_count: usize,
    profile_load_transformed_count: usize,
    profile_transform_rewrite_ns: i128,
    profile_transform_engine_ns: i128,
    profile_module_normalize_calls: usize,
    profile_module_normalize_ns: i128,
    profile_module_normalize_failures: usize,
    profile_module_load_calls: usize,
    profile_module_load_cache_hits: usize,
    profile_module_load_builtin_hits: usize,
    profile_cjs_require_calls: usize,
    profile_cjs_require_ns: i128,
    profile_cjs_require_cache_hits: usize,
    profile_cjs_require_cache_misses: usize,
    profile_cjs_require_json_count: usize,
    profile_cjs_require_onload_count: usize,
    profile_cjs_require_compile_count: usize,
    profile_cjs_require_compile_ns: i128,
    profile_require_specifier_cache_hits: usize,
    profile_require_specifier_cache_misses: usize,
    profile_cjs_lazy_compat_cache_hits: usize,
    profile_cjs_lazy_compat_cache_misses: usize,

    fn init(allocator: Allocator, io: std.Io) ModuleLoaderState {
        return .{
            .allocator = allocator,
            .io = io,
            .runtime = null,
            .entry_module_id = "",
            .loaded_modules = std.StringHashMap(*ModuleDef).init(allocator),
            .source_cache = std.StringHashMap([]u8).init(allocator),
            .onload_transform_cache = std.AutoHashMap(OnLoadTransformCacheKey, []u8).init(allocator),
            .specifier_cache = std.StringHashMap([]u8).init(allocator),
            .require_specifier_cache = std.StringHashMap([]u8).init(allocator),
            .cjs_lazy_compat_cache = std.StringHashMap(bool).init(allocator),
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
            .profile_normalize_calls = 0,
            .profile_normalize_ns = 0,
            .profile_normalize_failures = 0,
            .profile_normalize_builtin_hits = 0,
            .profile_normalize_mock_hits = 0,
            .profile_normalize_alias_hits = 0,
            .profile_normalize_absolute_hits = 0,
            .profile_normalize_relative_hits = 0,
            .profile_normalize_node_module_hits = 0,
            .profile_resolve_node_module_calls = 0,
            .profile_resolve_node_module_ns = 0,
            .profile_resolve_node_module_hits = 0,
            .profile_resolve_node_module_misses = 0,
            .profile_resolve_node_module_dirs_scanned = 0,
            .profile_resolve_node_module_require_calls = 0,
            .profile_resolve_node_module_require_ns = 0,
            .profile_resolve_node_module_require_hits = 0,
            .profile_resolve_node_module_require_misses = 0,
            .profile_resolve_node_module_require_dirs_scanned = 0,
            .profile_source_cache_calls = 0,
            .profile_source_cache_hits = 0,
            .profile_source_cache_misses = 0,
            .profile_source_cache_read_ns = 0,
            .profile_source_cache_read_bytes = 0,
            .profile_import_scan_calls = 0,
            .profile_import_scan_ns = 0,
            .profile_import_scan_statements = 0,
            .profile_import_scan_resolved = 0,
            .profile_import_scan_resolve_failures = 0,
            .profile_import_graph_modules = 0,
            .profile_rewrite_named_import_calls = 0,
            .profile_rewrite_named_import_ns = 0,
            .profile_rewrite_named_import_replacements = 0,
            .profile_load_module_source_calls = 0,
            .profile_load_builtin_count = 0,
            .profile_load_mock_count = 0,
            .profile_load_onload_hit_count = 0,
            .profile_load_onload_miss_count = 0,
            .profile_load_js_count = 0,
            .profile_load_cjs_count = 0,
            .profile_load_json_count = 0,
            .profile_load_transformed_count = 0,
            .profile_transform_rewrite_ns = 0,
            .profile_transform_engine_ns = 0,
            .profile_module_normalize_calls = 0,
            .profile_module_normalize_ns = 0,
            .profile_module_normalize_failures = 0,
            .profile_module_load_calls = 0,
            .profile_module_load_cache_hits = 0,
            .profile_module_load_builtin_hits = 0,
            .profile_cjs_require_calls = 0,
            .profile_cjs_require_ns = 0,
            .profile_cjs_require_cache_hits = 0,
            .profile_cjs_require_cache_misses = 0,
            .profile_cjs_require_json_count = 0,
            .profile_cjs_require_onload_count = 0,
            .profile_cjs_require_compile_count = 0,
            .profile_cjs_require_compile_ns = 0,
            .profile_require_specifier_cache_hits = 0,
            .profile_require_specifier_cache_misses = 0,
            .profile_cjs_lazy_compat_cache_hits = 0,
            .profile_cjs_lazy_compat_cache_misses = 0,
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

        var onload_transform_cache_iterator = self.onload_transform_cache.iterator();
        while (onload_transform_cache_iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.onload_transform_cache.deinit();

        var specifier_iterator = self.specifier_cache.iterator();
        while (specifier_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.specifier_cache.deinit();

        var require_specifier_iterator = self.require_specifier_cache.iterator();
        while (require_specifier_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.require_specifier_cache.deinit();

        var cjs_lazy_compat_iterator = self.cjs_lazy_compat_cache.iterator();
        while (cjs_lazy_compat_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.cjs_lazy_compat_cache.deinit();

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
        if (self.profile_enabled) self.profile_source_cache_calls += 1;
        if (self.source_cache.get(path)) |source| {
            if (self.profile_enabled) self.profile_source_cache_hits += 1;
            return source;
        }
        if (self.profile_enabled) self.profile_source_cache_misses += 1;

        const read_start = if (self.profile_enabled) self.profileNow() else 0;

        const source = try std.Io.Dir.cwd().readFileAlloc(
            self.io,
            path,
            self.allocator,
            .limited(max_bytes),
        );
        if (self.profile_enabled) {
            self.profile_source_cache_read_ns += self.profileNow() - read_start;
            self.profile_source_cache_read_bytes += source.len;
        }
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
        const profile = self.profile_enabled;
        if (profile) self.profile_normalize_calls += 1;
        const start = if (profile) self.profileNow() else 0;
        defer if (profile) {
            self.profile_normalize_ns += self.profileNow() - start;
        };
        errdefer if (profile) {
            self.profile_normalize_failures += 1;
        };

        if (self.runtime) |runtime| {
            try self.syncMockModulesFromRuntime(runtime);
        }

        if (builtInModuleSource(module_name) != null) {
            if (profile) self.profile_normalize_builtin_hits += 1;
            return self.allocator.dupe(u8, module_name);
        }

        if (self.mock_module_sources.contains(module_name)) {
            if (profile) self.profile_normalize_mock_hits += 1;
            return std.fmt.allocPrint(self.allocator, "__zig_mock__/{s}", .{module_name});
        }

        const cache_key = try std.fmt.allocPrint(self.allocator, "{s}\x1f{s}", .{ module_base_name, module_name });
        defer self.allocator.free(cache_key);
        if (self.specifier_cache.get(cache_key)) |cached| {
            return self.allocator.dupe(u8, cached);
        }

        const resolved = blk: {
            if (try self.resolvePathAlias(module_base_name, module_name)) |resolved| {
                if (profile) self.profile_normalize_alias_hits += 1;
                break :blk resolved;
            }

            if (std.fs.path.isAbsolute(module_name)) {
                if (profile) self.profile_normalize_absolute_hits += 1;
                break :blk try self.resolveAbsolutePath(module_name);
            }

            if (isRelativeSpecifier(module_name)) {
                if (profile) self.profile_normalize_relative_hits += 1;
                break :blk try self.resolveRelativePath(module_base_name, module_name);
            }

            if (try self.resolveNodeModule(module_base_name, module_name)) |resolved| {
                if (profile) self.profile_normalize_node_module_hits += 1;
                break :blk resolved;
            }

            return error.UnsupportedExternalModule;
        };
        errdefer self.allocator.free(resolved);

        const key_copy = try self.allocator.dupe(u8, cache_key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, resolved);
        errdefer self.allocator.free(value_copy);
        try self.specifier_cache.put(key_copy, value_copy);

        return resolved;
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
        if (self.profile_enabled) self.profile_load_module_source_calls += 1;
        if (std.c.getenv("ZIG_DOM_MODULE_DEBUG") != null) {
            std.debug.print("[zig-dom module] {s}\n", .{module_id});
        }

        if (builtInModuleSource(module_id)) |shim_source| {
            if (self.profile_enabled) self.profile_load_builtin_count += 1;
            return self.allocator.dupe(u8, shim_source);
        }

        if (isMockModuleId(module_id)) {
            if (self.profile_enabled) self.profile_load_mock_count += 1;
            const specifier = module_id["__zig_mock__/".len..];
            const source = self.mock_module_sources.get(specifier) orelse return error.ModuleNotFound;
            return self.allocator.dupe(u8, source);
        }

        const default_loader = transform.loaderForPath(module_id) orelse return error.UnsupportedModuleExtension;

        if (try self.loadModuleSourceFromOnLoad(module_id, default_loader)) |hook_source| {
            return hook_source;
        }

        if (std.mem.eql(u8, default_loader, "js")) {
            if (self.profile_enabled) self.profile_load_js_count += 1;
            const source = try self.readFileCached(module_id, max_module_source_bytes);

            if (isCommonJsSource(module_id, source)) {
                if (self.profile_enabled) self.profile_load_cjs_count += 1;
                return try self.loadCommonJsModuleSource(module_id);
            }

            return try self.rewriteTestingLibraryNamedImports(module_id, source);
        }

        if (std.mem.eql(u8, default_loader, "json")) {
            if (self.profile_enabled) self.profile_load_json_count += 1;
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
        if (self.profile_enabled) self.profile_load_transformed_count += 1;
        const start = if (self.profile_enabled) self.profileNow() else 0;
        const raw_source = try self.readFileCached(module_id, max_module_source_bytes);
        const testing_library_rewritten = try self.rewriteTestingLibraryNamedImports(module_id, raw_source);
        defer self.allocator.free(testing_library_rewritten);
        const rewrite_start = if (self.profile_enabled) self.profileNow() else 0;
        const linked_source = try self.rewriteBarePackageNamedImports(module_id, testing_library_rewritten);
        if (self.profile_enabled) {
            self.profile_transform_rewrite_ns += self.profileNow() - rewrite_start;
        }
        defer self.allocator.free(linked_source);
        const transform_start = if (self.profile_enabled) self.profileNow() else 0;
        const transformed = try yuku_transform.transformSource(self.allocator, module_id, linked_source, default_loader);
        if (self.profile_enabled) {
            self.profile_transform_engine_ns += self.profileNow() - transform_start;
        }
        if (std.c.getenv("ZIG_DOM_DUMP_TRANSFORMED")) |dump_path_raw| {
            if (std.mem.indexOf(u8, module_id, "Tree.test.tsx") != null) {
                _ = std.Io.Dir.cwd().writeFile(self.io, .{
                    .sub_path = std.mem.span(dump_path_raw),
                    .data = transformed,
                }) catch {};
            }
        }
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
            \\const __zigCommonJSDefault = (__zigCommonJSExports != null && __zigCommonJSExports.__esModule && Object.prototype.hasOwnProperty.call(__zigCommonJSExports, 'default'))
            \\  ? __zigCommonJSExports.default
            \\  : __zigCommonJSExports;
            \\export default __zigCommonJSDefault;
            \\
        );

        for (export_names) |name| {
            try appendFmt(self.allocator, &out, "export const {s} = __zigCommonJSExports == null ? undefined : __zigCommonJSExports.{s};\n", .{ name, name });
        }

        return try out.toOwnedSlice(self.allocator);
    }

    fn shouldLazyLoadCommonJsDependency(self: *ModuleLoaderState, resolved: []const u8) !bool {
        if (self.cjs_lazy_compat_cache.get(resolved)) |cached| {
            if (self.profile_enabled) self.profile_cjs_lazy_compat_cache_hits += 1;
            return cached;
        }
        if (self.profile_enabled) self.profile_cjs_lazy_compat_cache_misses += 1;

        if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) return false;
        if (std.mem.endsWith(u8, resolved, ".json")) return true;

        const loader = transform.loaderForPath(resolved) orelse return false;
        if (!std.mem.eql(u8, loader, "js")) return false;

        const source = self.readFileCached(resolved, max_module_source_bytes) catch return false;

        if (!isCommonJsSource(resolved, source)) {
            const key = try self.allocator.dupe(u8, resolved);
            errdefer self.allocator.free(key);
            try self.cjs_lazy_compat_cache.put(key, false);
            return false;
        }

        const lazy = try self.commonJsSourceRequiresOnlyLazyCompatible(resolved, source);
        const key = try self.allocator.dupe(u8, resolved);
        errdefer self.allocator.free(key);
        try self.cjs_lazy_compat_cache.put(key, lazy);
        return lazy;
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
            if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) continue;

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
        const profile = self.profile_enabled;
        if (profile) self.profile_cjs_require_calls += 1;
        const start = if (profile) self.profileNow() else 0;
        defer if (profile) {
            self.profile_cjs_require_ns += self.profileNow() - start;
        };

        const resolved = if (resolved_hint.len > 0)
            try self.allocator.dupe(u8, resolved_hint)
        else
            try self.normalizeRequireSpecifier(parent_id, specifier);
        defer self.allocator.free(resolved);

        if (try self.getCachedCommonJsValue(ctx, resolved)) |cached| {
            if (profile) self.profile_cjs_require_cache_hits += 1;
            return cached;
        }
        if (profile) self.profile_cjs_require_cache_misses += 1;

        if (builtInModuleSource(resolved) != null) {
            const global = ctx.getGlobalObject();
            defer global.deinit(ctx);
            if (std.mem.eql(u8, resolved, node_crypto_specifier) or std.mem.eql(u8, resolved, node_crypto_colon_specifier)) {
                const crypto_value = global.getPropertyStr(ctx, "crypto");
                defer crypto_value.deinit(ctx);
                if (!crypto_value.isException() and crypto_value.isObject()) {
                    return crypto_value.dup(ctx);
                }
            }
            return quickjs.Value.initObject(ctx);
        }

        if (std.mem.endsWith(u8, resolved, ".json")) {
            if (profile) self.profile_cjs_require_json_count += 1;
            return self.loadCommonJsJsonValue(ctx, resolved);
        }

        if (transform.loaderForPath(resolved)) |default_loader| {
            if (try self.loadModuleSourceFromOnLoad(resolved, default_loader)) |hook_source| {
                if (profile) self.profile_cjs_require_onload_count += 1;
                defer self.allocator.free(hook_source);
                return self.loadOnLoadModuleAsCommonJsValue(ctx, resolved, hook_source);
            }
        }

        const source = blk: {
            const raw = try self.readFileCached(resolved, max_module_source_bytes);
            if (!isCommonJsSource(resolved, raw)) {
                if (sourceHasCodePattern(raw, "import ") or sourceHasCodePattern(raw, "export ")) {
                    return error.UnsupportedExternalModule;
                }
            }
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
            self.profile_cjs_require_compile_count += 1;
            self.profile_cjs_require_compile_ns += elapsed;
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
                if (!runtime.isJobPending() and !runtime.hasPendingNativeTimers()) return error.EvaluationFailed;
                _ = runtime.executePendingJobOrNativeTimer() catch return error.EvaluationFailed;
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
        const cache_key = try std.fmt.allocPrint(self.allocator, "{s}\x1f{s}", .{ module_base_name, module_name });
        defer self.allocator.free(cache_key);

        if (self.require_specifier_cache.get(cache_key)) |cached| {
            if (self.profile_enabled) self.profile_require_specifier_cache_hits += 1;
            return self.allocator.dupe(u8, cached);
        }
        if (self.profile_enabled) self.profile_require_specifier_cache_misses += 1;

        const resolved = blk: {
            if (builtInModuleSource(module_name) != null) {
                break :blk try self.allocator.dupe(u8, module_name);
            }

            if (self.mock_module_sources.contains(module_name)) {
                break :blk try std.fmt.allocPrint(self.allocator, "__zig_mock__/{s}", .{module_name});
            }

            if (std.fs.path.isAbsolute(module_name)) {
                break :blk try self.resolveRequireAbsolutePath(module_name);
            }

            if (isRelativeSpecifier(module_name)) {
                break :blk try self.resolveRequireRelativePath(module_base_name, module_name);
            }

            if (try self.resolveNodeModuleRequire(module_base_name, module_name)) |node_resolved| {
                break :blk node_resolved;
            }

            break :blk try self.normalizeSpecifier(module_base_name, module_name);
        };
        errdefer self.allocator.free(resolved);

        const key_copy = try self.allocator.dupe(u8, cache_key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, resolved);
        errdefer self.allocator.free(value_copy);
        try self.require_specifier_cache.put(key_copy, value_copy);

        return resolved;
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
        const profile = self.profile_enabled;
        if (profile) self.profile_resolve_node_module_require_calls += 1;
        const start = if (profile) self.profileNow() else 0;
        defer if (profile) {
            self.profile_resolve_node_module_require_ns += self.profileNow() - start;
        };

        const parsed = parseBarePackageSpecifier(module_name) orelse return null;
        if (!std.fs.path.isAbsolute(module_base_name)) return null;

        var current_dir = try self.allocator.dupe(u8, std.fs.path.dirname(module_base_name) orelse return null);
        defer self.allocator.free(current_dir);

        while (true) {
            if (profile) self.profile_resolve_node_module_require_dirs_scanned += 1;
            const package_dir = try std.fs.path.resolve(self.allocator, &.{ current_dir, "node_modules", parsed.package_name });
            defer self.allocator.free(package_dir);

            if (self.pathIsDirectory(package_dir)) {
                if (try self.resolveNodeModuleRequireFromDirectory(package_dir, parsed.subpath)) |resolved| {
                    if (profile) self.profile_resolve_node_module_require_hits += 1;
                    return resolved;
                }
            }

            const parent = std.fs.path.dirname(current_dir) orelse break;
            if (parent.len == current_dir.len) break;

            const next_dir = try self.allocator.dupe(u8, parent);
            self.allocator.free(current_dir);
            current_dir = next_dir;
        }

        if (profile) self.profile_resolve_node_module_require_misses += 1;
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
                if (try self.resolveNodeModulePackageRootWithMode(subpath_candidate, .require)) |resolved_dir_entry| {
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
            if (self.profile_enabled) self.profile_load_onload_miss_count += 1;
            if (debug_onload) {
                std.debug.print("[zig-dom onload] miss {s}\n", .{module_id});
            }
            return null;
        };
        if (self.profile_enabled) self.profile_onload_ns += self.profileNow() - start;
        if (self.profile_enabled) self.profile_load_onload_hit_count += 1;
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
            const js_onload_source = try self.allocator.dupe(u8, hook_result.contents);
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
        const loader_tag = loaderTagForTransform(loader) orelse return error.UnsupportedTransformLoader;
        const module_dir = std.fs.path.dirname(module_id) orelse "";
        const cache_key: OnLoadTransformCacheKey = .{
            .loader_tag = loader_tag,
            .dir_hash = std.hash.Wyhash.hash(0, module_dir),
            .content_hash = std.hash.Wyhash.hash(0, contents),
            .content_len = contents.len,
        };
        if (self.onload_transform_cache.get(cache_key)) |cached| {
            return self.allocator.dupe(u8, cached);
        }

        const testing_library_rewritten = try self.rewriteTestingLibraryNamedImports(module_id, contents);
        defer self.allocator.free(testing_library_rewritten);
        const source = try self.rewriteBarePackageNamedImports(module_id, testing_library_rewritten);
        defer self.allocator.free(source);

        const transformed = try yuku_transform.transformSource(self.allocator, module_id, source, loader);
        const cache_entry = try self.onload_transform_cache.getOrPut(cache_key);
        if (!cache_entry.found_existing) {
            cache_entry.value_ptr.* = try self.allocator.dupe(u8, transformed);
        }
        if (std.c.getenv("ZIG_DOM_DUMP_TRANSFORMED")) |dump_path_raw| {
            if (std.mem.indexOf(u8, module_id, "Tree.test.tsx") != null) {
                _ = std.Io.Dir.cwd().writeFile(self.io, .{
                    .sub_path = std.mem.span(dump_path_raw),
                    .data = transformed,
                }) catch {};
            }
        }
        return transformed;
    }

    fn loaderTagForTransform(loader: []const u8) ?u8 {
        if (std.mem.eql(u8, loader, "ts")) return 1;
        if (std.mem.eql(u8, loader, "tsx")) return 2;
        if (std.mem.eql(u8, loader, "jsx")) return 3;
        return null;
    }

    fn rewriteTestingLibraryNamedImports(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) ![]u8 {
        if (std.mem.indexOf(u8, module_id, "/node_modules/") != null) return self.allocator.dupe(u8, source);
        if (std.mem.indexOf(u8, source, "@testing-library/") == null) return self.allocator.dupe(u8, source);

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);

        var cursor: usize = 0;
        while (nextStaticImportKeyword(source, cursor)) |start| {
            const end = findImportStatementEnd(source, start);
            const statement = source[start..end];
            const parsed = parseImportStatement(statement) orelse {
                try out.appendSlice(self.allocator, source[cursor..end]);
                cursor = end;
                continue;
            };

            const replacement = try buildTestingLibraryNamedImportReplacement(self.allocator, parsed);
            if (replacement) |rewritten| {
                defer self.allocator.free(rewritten);
                try out.appendSlice(self.allocator, source[cursor..start]);
                try out.appendSlice(self.allocator, rewritten);
                cursor = end;
                if (cursor < source.len and source[cursor] == ';') cursor += 1;
                continue;
            }

            try out.appendSlice(self.allocator, source[cursor..end]);
            cursor = end;
        }

        try out.appendSlice(self.allocator, source[cursor..]);
        return out.toOwnedSlice(self.allocator);
    }

    fn rewriteBarePackageNamedImports(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) ![]u8 {
        const profile = self.profile_enabled;
        if (profile) self.profile_rewrite_named_import_calls += 1;
        const profile_start = if (profile) self.profileNow() else 0;
        defer if (profile) {
            self.profile_rewrite_named_import_ns += self.profileNow() - profile_start;
        };

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);

        var cursor: usize = 0;
        var rewrite_index: usize = 0;
        while (nextStaticImportKeyword(source, cursor)) |start| {
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
        if (profile) self.profile_rewrite_named_import_replacements += rewrite_index;
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

        var saw_part = false;
        var parts = std.mem.tokenizeScalar(u8, bindings[1 .. bindings.len - 1], ',');
        while (parts.next()) |raw_part| {
            const part = std.mem.trim(u8, raw_part, " \t\r\n");
            if (part.len == 0) continue;
            saw_part = true;
            if (std.mem.startsWith(u8, part, "type ")) continue;
            const as_index = std.mem.indexOf(u8, part, " as ");
            const imported = std.mem.trim(u8, if (as_index) |idx| part[0..idx] else part, " \t\r\n");
            const local = std.mem.trim(u8, if (as_index) |idx| part[idx + " as ".len ..] else part, " \t\r\n");
            if (!isValidIdentifier(imported) or !isValidIdentifier(local)) return null;

            try imports.append(self.allocator, .{
                .imported = try self.allocator.dupe(u8, imported),
                .local = try self.allocator.dupe(u8, local),
                .specifier = try self.allocator.dupe(u8, parsed.specifier),
            });
        }

        if (imports.items.len == 0) {
            if (saw_part) return @as(?[]u8, try self.allocator.dupe(u8, ""));
            return null;
        }

        var use_subpath_specifiers = true;
        for (imports.items) |*part| {
            const subpath_specifier = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ parsed.specifier, part.imported }) catch {
                use_subpath_specifiers = false;
                break;
            };
            const resolved = self.normalizeSpecifier(module_id, subpath_specifier) catch {
                self.allocator.free(subpath_specifier);
                const rewrite = try self.resolveCommonJsBarrelNamedImport(module_id, parsed.specifier, part.imported);
                if (rewrite) |barrel| {
                    defer self.allocator.free(barrel.export_name);
                    self.allocator.free(part.specifier);
                    part.specifier = barrel.resolved_specifier;
                    self.allocator.free(part.imported);
                    part.imported = barrel.member_name;
                    continue;
                }
                use_subpath_specifiers = false;
                break;
            };
            self.allocator.free(resolved);
            self.allocator.free(part.specifier);
            part.specifier = subpath_specifier;
        }

        if (!use_subpath_specifiers) return null;

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

    fn resolveCommonJsBarrelNamedImport(
        self: *ModuleLoaderState,
        module_id: []const u8,
        package_specifier: []const u8,
        imported_name: []const u8,
    ) !?CommonJsBarrelPropertyRewrite {
        const root_module_id = self.normalizeSpecifier(module_id, package_specifier) catch return null;
        defer self.allocator.free(root_module_id);
        if (builtInModuleSource(root_module_id) != null or isMockModuleId(root_module_id)) return null;

        const root_source = self.readFileCached(root_module_id, max_module_source_bytes) catch return null;
        if (!isCommonJsSource(root_module_id, root_source)) return null;
        return commonJsBarrelRewriteForExport(self, root_module_id, root_source, imported_name);
    }

    fn hasOnLoadForSpecifier(self: *ModuleLoaderState, module_id: []const u8, specifier: []const u8) anyerror!bool {
        const runtime = self.runtime orelse return false;
        const resolved = self.normalizeSpecifier(module_id, specifier) catch return false;
        defer self.allocator.free(resolved);
        return try runtime.matchesOnLoad(resolved);
    }

    fn recordStaticImportRequests(self: *ModuleLoaderState, module_id: []const u8, source: []const u8) !void {
        const profile = self.profile_enabled;
        if (profile) self.profile_import_scan_calls += 1;
        const profile_start = if (profile) self.profileNow() else 0;
        defer if (profile) {
            self.profile_import_scan_ns += self.profileNow() - profile_start;
        };

        var cursor: usize = 0;
        while (nextStaticImportKeyword(source, cursor)) |start| {
            const end = findImportStatementEnd(source, start);
            const statement = source[start..end];
            const parsed = parseImportStatement(statement) orelse {
                cursor = end;
                continue;
            };
            if (profile) self.profile_import_scan_statements += 1;

            const resolved = self.normalizeSpecifier(module_id, parsed.specifier) catch {
                if (profile) self.profile_import_scan_resolve_failures += 1;
                cursor = end;
                continue;
            };
            defer self.allocator.free(resolved);
            if (profile) self.profile_import_scan_resolved += 1;

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
        if (self.profile_enabled) self.profile_import_graph_modules += 1;
        const visited_key = try self.allocator.dupe(u8, module_id);
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
        const profile = self.profile_enabled;
        if (profile) self.profile_import_scan_calls += 1;
        const profile_start = if (profile) self.profileNow() else 0;
        defer if (profile) {
            self.profile_import_scan_ns += self.profileNow() - profile_start;
        };

        var cursor: usize = 0;
        while (nextStaticImportKeyword(source, cursor)) |start| {
            const end = findImportStatementEnd(source, start);
            const statement = source[start..end];
            const parsed = parseImportStatement(statement) orelse {
                cursor = end;
                continue;
            };
            if (profile) self.profile_import_scan_statements += 1;

            const resolved = self.normalizeSpecifier(module_id, parsed.specifier) catch {
                if (profile) self.profile_import_scan_resolve_failures += 1;
                cursor = end;
                continue;
            };
            errdefer self.allocator.free(resolved);
            if (profile) self.profile_import_scan_resolved += 1;

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
        const profile = self.profile_enabled;
        if (profile) self.profile_resolve_node_module_calls += 1;
        const start = if (profile) self.profileNow() else 0;
        defer if (profile) {
            self.profile_resolve_node_module_ns += self.profileNow() - start;
        };

        const parsed = parseBarePackageSpecifier(module_name) orelse return null;
        if (!std.fs.path.isAbsolute(module_base_name)) {
            return null;
        }

        var current_dir = try self.allocator.dupe(u8, std.fs.path.dirname(module_base_name) orelse return null);
        defer self.allocator.free(current_dir);

        while (true) {
            if (profile) self.profile_resolve_node_module_dirs_scanned += 1;
            const package_dir = try std.fs.path.resolve(self.allocator, &.{ current_dir, "node_modules", parsed.package_name });
            defer self.allocator.free(package_dir);

            if (self.pathIsDirectory(package_dir)) {
                const resolved = try self.resolveNodeModuleFromDirectory(package_dir, parsed.subpath);
                if (profile) self.profile_resolve_node_module_hits += 1;
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

        if (profile) self.profile_resolve_node_module_misses += 1;
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

        if (jsonObjectString(root.object, "module")) |entry| {
            if (try self.resolveNodeModulePackageEntryPath(package_dir, entry)) |resolved| {
                return resolved;
            }
        }
        if (jsonObjectString(root.object, "main")) |entry| {
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

fn nextStaticImportKeyword(source: []const u8, start_index: usize) ?usize {
    return nextCodeKeyword(source, start_index, "import");
}

fn nextCodeKeyword(source: []const u8, start_index: usize, keyword: []const u8) ?usize {
    var cursor = start_index;
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

        if (hasWordAt(source, cursor, keyword)) return cursor;
        cursor += 1;
    }

    return null;
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
        const setup_jobs_timeout_ms: i64 = 10_000;
        const setup_jobs_start_ts = std.Io.Clock.Timestamp.now(io, .awake);
        while (vm.isJobPending()) {
            const setup_jobs_elapsed_ms = setup_jobs_start_ts.untilNow(io).raw.toMilliseconds();
            if (setup_jobs_elapsed_ms > setup_jobs_timeout_ms) {
                vm.evalScript("<zig-setup-dom-probe-end>", setup_dom_probe_end_source) catch {};
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
                    .collection_report = try allocator.dupe(u8, "collection failed: setup async jobs timed out"),
                };
            }
            _ = vm.executePendingJob() catch |err| {
                vm.evalScript("<zig-setup-dom-probe-end>", setup_dom_probe_end_source) catch {};
                return collectionFailureFromRuntimeException(allocator, path, "collection failed", err, &vm);
            };
        }
        vm.evalScript("<zig-setup-dom-probe-end>", setup_dom_probe_end_source) catch |err| {
            return failureFromRuntimeException(allocator, path, "failed to restore setup environment", err, &vm);
        };
        vm.evalScript("<zig-sync-window-globals>", sync_window_globals_source) catch |err| {
            return failureFromRuntimeException(allocator, path, "failed to sync setup globals", err, &vm);
        };
        if (module_loader_state.profile_enabled) {
            module_loader_state.profile_setup_eval_ns += module_loader_state.profileNow() - setup_eval_start;
        }
    }

    module_loader_state.syncMockModulesFromRuntime(&vm) catch |err| {
        return collectionFailureFromError(allocator, path, "collection failed", err);
    };

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

    const entry_jobs_timeout_ms: i64 = 10_000;
    const entry_jobs_start_ts = std.Io.Clock.Timestamp.now(io, .awake);
    while (vm.isJobPending()) {
        const entry_jobs_elapsed_ms = entry_jobs_start_ts.untilNow(io).raw.toMilliseconds();
        if (entry_jobs_elapsed_ms > entry_jobs_timeout_ms) {
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
                .collection_report = try allocator.dupe(u8, "collection failed: entry async jobs timed out"),
            };
        }
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

    const post_flush_jobs_timeout_ms: i64 = 10_000;
    const post_flush_jobs_start_ts = std.Io.Clock.Timestamp.now(io, .awake);
    while (vm.isJobPending()) {
        const post_flush_jobs_elapsed_ms = post_flush_jobs_start_ts.untilNow(io).raw.toMilliseconds();
        if (post_flush_jobs_elapsed_ms > post_flush_jobs_timeout_ms) {
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
                .collection_report = try allocator.dupe(u8, "collection failed: post-flush async jobs timed out"),
            };
        }
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
            const timeout_message = try std.fmt.allocPrint(
                allocator,
                "Runner timed out while waiting for async jobs (jobs_pending={}, timers_pending={}, registered_tests={d}, has_runnable={}, only_mode={}).",
                .{
                    vm.isJobPending(),
                    vm.hasPendingNativeTimers(),
                    vm.getGlobalInt32("__zigRegisteredTests") catch -1,
                    vm.getGlobalBool("__zigHasRunnable") catch false,
                    vm.getGlobalBool("__zigOnlyMode") catch false,
                },
            );
            return .{
                .path = try allocator.dupe(u8, path),
                .passed = 0,
                .failed = 0,
                .skipped = 0,
                .timed_out = 1,
                .collection_errors = 0,
                .expect_calls = 0,
                .passed_report = null,
                .failure_report = timeout_message,
                .collection_report = null,
            };
        }

        if (vm.isJobPending() or vm.hasPendingNativeTimers()) {
            _ = vm.executePendingJobOrNativeTimer() catch |err| {
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
        std.debug.print(
            "[zig-dom profile imports] normalize(calls={d} ms={d:.3} fail={d} builtin={d} mock={d} alias={d} abs={d} rel={d} node={d}) node_resolve(calls={d} hits={d} miss={d} dirs={d} ms={d:.3}) require_resolve(calls={d} hits={d} miss={d} dirs={d} ms={d:.3}) import_scan(calls={d} stmts={d} resolved={d} fail={d} graph_modules={d} ms={d:.3}) rewrite(calls={d} replacements={d} ms={d:.3})\n",
            .{
                module_loader_state.profile_normalize_calls,
                @as(f64, @floatFromInt(module_loader_state.profile_normalize_ns)) / 1_000_000.0,
                module_loader_state.profile_normalize_failures,
                module_loader_state.profile_normalize_builtin_hits,
                module_loader_state.profile_normalize_mock_hits,
                module_loader_state.profile_normalize_alias_hits,
                module_loader_state.profile_normalize_absolute_hits,
                module_loader_state.profile_normalize_relative_hits,
                module_loader_state.profile_normalize_node_module_hits,
                module_loader_state.profile_resolve_node_module_calls,
                module_loader_state.profile_resolve_node_module_hits,
                module_loader_state.profile_resolve_node_module_misses,
                module_loader_state.profile_resolve_node_module_dirs_scanned,
                @as(f64, @floatFromInt(module_loader_state.profile_resolve_node_module_ns)) / 1_000_000.0,
                module_loader_state.profile_resolve_node_module_require_calls,
                module_loader_state.profile_resolve_node_module_require_hits,
                module_loader_state.profile_resolve_node_module_require_misses,
                module_loader_state.profile_resolve_node_module_require_dirs_scanned,
                @as(f64, @floatFromInt(module_loader_state.profile_resolve_node_module_require_ns)) / 1_000_000.0,
                module_loader_state.profile_import_scan_calls,
                module_loader_state.profile_import_scan_statements,
                module_loader_state.profile_import_scan_resolved,
                module_loader_state.profile_import_scan_resolve_failures,
                module_loader_state.profile_import_graph_modules,
                @as(f64, @floatFromInt(module_loader_state.profile_import_scan_ns)) / 1_000_000.0,
                module_loader_state.profile_rewrite_named_import_calls,
                module_loader_state.profile_rewrite_named_import_replacements,
                @as(f64, @floatFromInt(module_loader_state.profile_rewrite_named_import_ns)) / 1_000_000.0,
            },
        );
        std.debug.print(
            "[zig-dom profile loader] module_normalize(calls={d} fail={d} ms={d:.3}) module_load(calls={d} cache_hit={d} builtin_hit={d}) load_source(calls={d} builtin={d} mock={d} onload_hit={d} onload_miss={d} js={d} cjs={d} json={d} transformed={d}) transform_split(rewrite_ms={d:.3} yuku_ms={d:.3}) cjs_require(calls={d} cache_hit={d} cache_miss={d} json={d} onload={d} compile_count={d} compile_ms={d:.3} total_ms={d:.3}) require_spec_cache(hit={d} miss={d}) cjs_lazy_cache(hit={d} miss={d})\n",
            .{
                module_loader_state.profile_module_normalize_calls,
                module_loader_state.profile_module_normalize_failures,
                @as(f64, @floatFromInt(module_loader_state.profile_module_normalize_ns)) / 1_000_000.0,
                module_loader_state.profile_module_load_calls,
                module_loader_state.profile_module_load_cache_hits,
                module_loader_state.profile_module_load_builtin_hits,
                module_loader_state.profile_load_module_source_calls,
                module_loader_state.profile_load_builtin_count,
                module_loader_state.profile_load_mock_count,
                module_loader_state.profile_load_onload_hit_count,
                module_loader_state.profile_load_onload_miss_count,
                module_loader_state.profile_load_js_count,
                module_loader_state.profile_load_cjs_count,
                module_loader_state.profile_load_json_count,
                module_loader_state.profile_load_transformed_count,
                @as(f64, @floatFromInt(module_loader_state.profile_transform_rewrite_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_transform_engine_ns)) / 1_000_000.0,
                module_loader_state.profile_cjs_require_calls,
                module_loader_state.profile_cjs_require_cache_hits,
                module_loader_state.profile_cjs_require_cache_misses,
                module_loader_state.profile_cjs_require_json_count,
                module_loader_state.profile_cjs_require_onload_count,
                module_loader_state.profile_cjs_require_compile_count,
                @as(f64, @floatFromInt(module_loader_state.profile_cjs_require_compile_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_cjs_require_ns)) / 1_000_000.0,
                module_loader_state.profile_require_specifier_cache_hits,
                module_loader_state.profile_require_specifier_cache_misses,
                module_loader_state.profile_cjs_lazy_compat_cache_hits,
                module_loader_state.profile_cjs_lazy_compat_cache_misses,
            },
        );
        std.debug.print(
            "[zig-dom profile cache] source_cache(calls={d} hits={d} misses={d} read_ms={d:.3} read_mb={d:.3})\n",
            .{
                module_loader_state.profile_source_cache_calls,
                module_loader_state.profile_source_cache_hits,
                module_loader_state.profile_source_cache_misses,
                @as(f64, @floatFromInt(module_loader_state.profile_source_cache_read_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(module_loader_state.profile_source_cache_read_bytes)) / (1024.0 * 1024.0),
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

    const parent_value = quickjs.Value.fromCVal(args[0]);
    const parent_c = parent_value.toCStringLen(ctx) orelse {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "__zigNativeRequire parent must be a string");
        return quickjs.Value.exception;
    };
    defer ctx.freeCString(parent_c.ptr);

    const specifier_value = quickjs.Value.fromCVal(args[1]);
    const specifier_c = specifier_value.toCStringLen(ctx) orelse {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "__zigNativeRequire specifier must be a string");
        return quickjs.Value.exception;
    };
    defer ctx.freeCString(specifier_c.ptr);

    const parent_slice = parent_c.ptr[0..parent_c.len];
    const specifier_slice = specifier_c.ptr[0..specifier_c.len];

    if (args.len > 2) {
        const resolved_hint_value = quickjs.Value.fromCVal(args[2]);
        const resolved_hint_c = resolved_hint_value.toCStringLen(ctx) orelse {
            _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "__zigNativeRequire resolved hint must be a string");
            return quickjs.Value.exception;
        };
        defer ctx.freeCString(resolved_hint_c.ptr);

        return state.loadCommonJsValue(
            ctx,
            parent_slice,
            specifier_slice,
            resolved_hint_c.ptr[0..resolved_hint_c.len],
        ) catch |err| {
            if (err == error.EvaluationFailed) {
                return quickjs.Value.exception;
            }
            _ = quickjs.c.JS_ThrowReferenceError(
                ctx.cval(),
                "native CommonJS require failed: %s from %s (%s)",
                specifier_c.ptr,
                parent_c.ptr,
                @errorName(err).ptr,
            );
            return quickjs.Value.exception;
        };
    }

    return state.loadCommonJsValue(ctx, parent_slice, specifier_slice, "") catch |err| {
        if (err == error.EvaluationFailed) {
            return quickjs.Value.exception;
        }
        _ = quickjs.c.JS_ThrowReferenceError(
            ctx.cval(),
            "native CommonJS require failed: %s from %s (%s)",
            specifier_c.ptr,
            parent_c.ptr,
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

    patchLoadedModuleExports(state.allocator, ctx, module_ptr, produced) catch return quickjs.Value.undefined;

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
    const profile = state.profile_enabled;
    if (profile) state.profile_module_normalize_calls += 1;
    const start = if (profile) state.profileNow() else 0;
    defer if (profile) {
        state.profile_module_normalize_ns += state.profileNow() - start;
    };

    const resolved = state.normalizeSpecifier(module_base_name, module_name) catch {
        if (profile) state.profile_module_normalize_failures += 1;
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
    if (state.profile_enabled) state.profile_module_load_calls += 1;
    const module_id: []const u8 = module_name;

    if (state.loaded_modules.get(module_id)) |existing| {
        if (state.profile_enabled) state.profile_module_load_cache_hits += 1;
        return existing;
    }

    if (loadNativeBuiltInModule(ctx, module_name)) |native_module| {
        if (state.profile_enabled) state.profile_module_load_builtin_hits += 1;
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

    if (std.mem.eql(u8, module_name, happy_dom_global_registrator_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeHappyDomGlobalRegistratorModule) orelse return null;
        if (!module.addExport(ctx, "GlobalRegistrator")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, testing_library_dom_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeTestingLibraryDomModule) orelse return null;
        inline for (testing_library_dom_export_names) |member_name| {
            if (!module.addExport(ctx, member_name)) return null;
        }
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, testing_library_react_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeTestingLibraryReactModule) orelse return null;
        inline for (testing_library_react_export_names) |member_name| {
            if (!module.addExport(ctx, member_name)) return null;
        }
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_assert_specifier) or std.mem.eql(u8, module_name, node_assert_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeAssertModule) orelse return null;
        if (!module.addExport(ctx, "default")) return null;
        if (!module.addExport(ctx, "ok")) return null;
        if (!module.addExport(ctx, "fail")) return null;
        if (!module.addExport(ctx, "strictEqual")) return null;
        if (!module.addExport(ctx, "notStrictEqual")) return null;
        if (!module.addExport(ctx, "strict")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_url_specifier) or std.mem.eql(u8, module_name, node_url_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeUrlModule) orelse return null;
        if (!module.addExport(ctx, "URL")) return null;
        if (!module.addExport(ctx, "URLSearchParams")) return null;
        if (!module.addExport(ctx, "pathToFileURL")) return null;
        if (!module.addExport(ctx, "fileURLToPath")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_fs_specifier) or std.mem.eql(u8, module_name, node_fs_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeFsModule) orelse return null;
        if (!module.addExport(ctx, "readFileSync")) return null;
        if (!module.addExport(ctx, "writeFileSync")) return null;
        if (!module.addExport(ctx, "mkdirSync")) return null;
        if (!module.addExport(ctx, "readdirSync")) return null;
        if (!module.addExport(ctx, "existsSync")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_path_specifier) or std.mem.eql(u8, module_name, node_path_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodePathModule) orelse return null;
        if (!module.addExport(ctx, "join")) return null;
        if (!module.addExport(ctx, "resolve")) return null;
        if (!module.addExport(ctx, "dirname")) return null;
        if (!module.addExport(ctx, "basename")) return null;
        if (!module.addExport(ctx, "extname")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_util_specifier) or std.mem.eql(u8, module_name, node_util_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeUtilModule) orelse return null;
        if (!module.addExport(ctx, "inspect")) return null;
        if (!module.addExport(ctx, "format")) return null;
        if (!module.addExport(ctx, "promisify")) return null;
        if (!module.addExport(ctx, "TextEncoder")) return null;
        if (!module.addExport(ctx, "TextDecoder")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_buffer_specifier) or std.mem.eql(u8, module_name, node_buffer_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeBufferModule) orelse return null;
        if (!module.addExport(ctx, "Buffer")) return null;
        if (!module.addExport(ctx, "Blob")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_crypto_specifier) or std.mem.eql(u8, module_name, node_crypto_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeCryptoModule) orelse return null;
        if (!module.addExport(ctx, "randomUUID")) return null;
        if (!module.addExport(ctx, "webcrypto")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_http_specifier) or std.mem.eql(u8, module_name, node_http_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeHttpModule) orelse return null;
        if (!module.addExport(ctx, "request")) return null;
        if (!module.addExport(ctx, "get")) return null;
        if (!module.addExport(ctx, "createServer")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_https_specifier) or std.mem.eql(u8, module_name, node_https_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeHttpsModule) orelse return null;
        if (!module.addExport(ctx, "request")) return null;
        if (!module.addExport(ctx, "get")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_net_specifier) or std.mem.eql(u8, module_name, node_net_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeNetModule) orelse return null;
        if (!module.addExport(ctx, "createConnection")) return null;
        if (!module.addExport(ctx, "createServer")) return null;
        if (!module.addExport(ctx, "isIP")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_zlib_specifier) or std.mem.eql(u8, module_name, node_zlib_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeZlibModule) orelse return null;
        if (!module.addExport(ctx, "gzipSync")) return null;
        if (!module.addExport(ctx, "gunzipSync")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_child_process_specifier) or std.mem.eql(u8, module_name, node_child_process_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeChildProcessModule) orelse return null;
        if (!module.addExport(ctx, "spawn")) return null;
        if (!module.addExport(ctx, "exec")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_stream_specifier) or std.mem.eql(u8, module_name, node_stream_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeStreamModule) orelse return null;
        if (!module.addExport(ctx, "Readable")) return null;
        if (!module.addExport(ctx, "Writable")) return null;
        if (!module.addExport(ctx, "Transform")) return null;
        if (!module.addExport(ctx, "Duplex")) return null;
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

    if (std.mem.eql(u8, module_name, node_vm_specifier) or std.mem.eql(u8, module_name, node_vm_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodeVmModule) orelse return null;
        if (!module.addExport(ctx, "runInNewContext")) return null;
        if (!module.addExport(ctx, "runInContext")) return null;
        if (!module.addExport(ctx, "runInThisContext")) return null;
        if (!module.addExport(ctx, "Script")) return null;
        if (!module.addExport(ctx, "default")) return null;
        return module;
    }

    if (std.mem.eql(u8, module_name, node_perf_hooks_specifier) or std.mem.eql(u8, module_name, node_perf_hooks_colon_specifier)) {
        const module = ModuleDef.init(ctx, module_name, initNativeNodePerfHooksModule) orelse return null;
        if (!module.addExport(ctx, "performance")) return null;
        if (!module.addExport(ctx, "PerformanceObserver")) return null;
        if (!module.addExport(ctx, "PerformanceEntry")) return null;
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

fn initNativeHappyDomGlobalRegistratorModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const registrator = quickjs.Value.initObject(ctx);
    defer registrator.deinit(ctx);
    if (registrator.isException()) return false;

    const register_fn = quickjs.Value.initCFunction(ctx, jsNoop, "register", 1);
    defer register_fn.deinit(ctx);
    if (register_fn.isException()) return false;

    registrator.setPropertyStr(ctx, "register", register_fn.dup(ctx)) catch return false;
    if (!module.setExport(ctx, "GlobalRegistrator", registrator.dup(ctx))) return false;
    if (!module.setExport(ctx, "default", registrator.dup(ctx))) return false;
    return true;
}

fn jsNoop(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn initNativeTestingLibraryDomModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    return exportApiMembersAsModule(ctx, module, "__zigTestingLibraryDom", &testing_library_dom_export_names);
}

fn initNativeTestingLibraryReactModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    return exportApiMembersAsModule(ctx, module, "__zigTestingLibraryReact", &testing_library_react_export_names);
}

fn initNativeNodeStreamWebModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    return exportGlobalMembersAsModule(ctx, module, &.{ "ReadableStream", "WritableStream", "TransformStream" });
}

fn initNativeNodeAssertModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const assert_fn = quickjs.Value.initCFunction(ctx, jsNodeAssert, "assert", 2);
    defer assert_fn.deinit(ctx);
    if (assert_fn.isException()) return false;

    const fail_fn = quickjs.Value.initCFunction(ctx, jsNodeAssertFail, "fail", 1);
    defer fail_fn.deinit(ctx);
    if (fail_fn.isException()) return false;

    const strict_equal_fn = quickjs.Value.initCFunction(ctx, jsNodeAssertStrictEqual, "strictEqual", 3);
    defer strict_equal_fn.deinit(ctx);
    if (strict_equal_fn.isException()) return false;

    const not_strict_equal_fn = quickjs.Value.initCFunction(ctx, jsNodeAssertNotStrictEqual, "notStrictEqual", 3);
    defer not_strict_equal_fn.deinit(ctx);
    if (not_strict_equal_fn.isException()) return false;

    assert_fn.setPropertyStr(ctx, "ok", assert_fn.dup(ctx)) catch return false;
    assert_fn.setPropertyStr(ctx, "fail", fail_fn.dup(ctx)) catch return false;
    assert_fn.setPropertyStr(ctx, "strictEqual", strict_equal_fn.dup(ctx)) catch return false;
    assert_fn.setPropertyStr(ctx, "notStrictEqual", not_strict_equal_fn.dup(ctx)) catch return false;
    assert_fn.setPropertyStr(ctx, "strict", assert_fn.dup(ctx)) catch return false;

    if (!module.setExport(ctx, "default", assert_fn.dup(ctx))) return false;
    if (!module.setExport(ctx, "ok", assert_fn.dup(ctx))) return false;
    if (!module.setExport(ctx, "fail", fail_fn.dup(ctx))) return false;
    if (!module.setExport(ctx, "strictEqual", strict_equal_fn.dup(ctx))) return false;
    if (!module.setExport(ctx, "notStrictEqual", not_strict_equal_fn.dup(ctx))) return false;
    if (!module.setExport(ctx, "strict", assert_fn.dup(ctx))) return false;
    return true;
}

fn jsNodeAssert(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const condition = if (args.len > 0) quickjs.Value.fromCVal(args[0]).toBool(ctx) catch false else false;
    if (condition) return quickjs.Value.undefined;
    _ = quickjs.c.JS_ThrowInternalError(ctx.cval(), "Assertion failed");
    return quickjs.Value.exception;
}

fn jsNodeAssertFail(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    _ = quickjs.c.JS_ThrowInternalError(ctx.cval(), "Assertion failed");
    return quickjs.Value.exception;
}

fn jsNodeAssertStrictEqual(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len < 2) {
        _ = quickjs.c.JS_ThrowInternalError(ctx.cval(), "Assertion failed");
        return quickjs.Value.exception;
    }
    const left = quickjs.Value.fromCVal(args[0]);
    const right = quickjs.Value.fromCVal(args[1]);
    if (left.isStrictEqual(ctx, right)) return quickjs.Value.undefined;
    _ = quickjs.c.JS_ThrowInternalError(ctx.cval(), "Assertion failed");
    return quickjs.Value.exception;
}

fn jsNodeAssertNotStrictEqual(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len < 2) return quickjs.Value.undefined;
    const left = quickjs.Value.fromCVal(args[0]);
    const right = quickjs.Value.fromCVal(args[1]);
    if (!left.isStrictEqual(ctx, right)) return quickjs.Value.undefined;
    _ = quickjs.c.JS_ThrowInternalError(ctx.cval(), "Assertion failed");
    return quickjs.Value.exception;
}

fn setModuleExportValue(
    ctx: *ModuleContext,
    module: *ModuleDef,
    default_export: quickjs.Value,
    export_name: [:0]const u8,
    value: quickjs.Value,
) bool {
    default_export.setPropertyStr(ctx, export_name.ptr, value.dup(ctx)) catch return false;
    if (!module.setExport(ctx, export_name, value.dup(ctx))) return false;
    return true;
}

fn finishModuleDefaultExport(ctx: *ModuleContext, module: *ModuleDef, default_export: quickjs.Value) bool {
    if (!module.setExport(ctx, "default", default_export.dup(ctx))) return false;
    return true;
}

fn initNativeNodeUrlModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const url_ctor = global.getPropertyStr(ctx, "URL");
    defer url_ctor.deinit(ctx);
    if (url_ctor.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "URL", url_ctor)) return false;

    const search_params_ctor = global.getPropertyStr(ctx, "URLSearchParams");
    defer search_params_ctor.deinit(ctx);
    if (search_params_ctor.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "URLSearchParams", search_params_ctor)) return false;

    const path_to_file_url = quickjs.Value.initCFunction(ctx, jsNodeUrlPathToFileURL, "pathToFileURL", 1);
    defer path_to_file_url.deinit(ctx);
    if (path_to_file_url.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "pathToFileURL", path_to_file_url)) return false;

    const file_url_to_path = quickjs.Value.initCFunction(ctx, jsNodeUrlFileURLToPath, "fileURLToPath", 1);
    defer file_url_to_path.deinit(ctx);
    if (file_url_to_path.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "fileURLToPath", file_url_to_path)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeFsModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const read_file_sync = quickjs.Value.initCFunction(ctx, jsNodeFsReadFileSync, "readFileSync", 2);
    defer read_file_sync.deinit(ctx);
    if (read_file_sync.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "readFileSync", read_file_sync)) return false;

    const write_file_sync = quickjs.Value.initCFunction(ctx, jsNodeFsWriteFileSync, "writeFileSync", 0);
    defer write_file_sync.deinit(ctx);
    if (write_file_sync.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "writeFileSync", write_file_sync)) return false;

    const mkdir_sync = quickjs.Value.initCFunction(ctx, jsNodeFsMkdirSync, "mkdirSync", 0);
    defer mkdir_sync.deinit(ctx);
    if (mkdir_sync.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "mkdirSync", mkdir_sync)) return false;

    const readdir_sync = quickjs.Value.initCFunction(ctx, jsNodeFsReaddirSync, "readdirSync", 0);
    defer readdir_sync.deinit(ctx);
    if (readdir_sync.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "readdirSync", readdir_sync)) return false;

    const exists_sync = quickjs.Value.initCFunction(ctx, jsNodeFsExistsSync, "existsSync", 1);
    defer exists_sync.deinit(ctx);
    if (exists_sync.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "existsSync", exists_sync)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodePathModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const join = quickjs.Value.initCFunction(ctx, jsNodePathJoin, "join", 0);
    defer join.deinit(ctx);
    if (join.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "join", join)) return false;

    const resolve = quickjs.Value.initCFunction(ctx, jsNodePathResolve, "resolve", 0);
    defer resolve.deinit(ctx);
    if (resolve.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "resolve", resolve)) return false;

    const dirname = quickjs.Value.initCFunction(ctx, jsNodePathDirname, "dirname", 1);
    defer dirname.deinit(ctx);
    if (dirname.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "dirname", dirname)) return false;

    const basename = quickjs.Value.initCFunction(ctx, jsNodePathBasename, "basename", 1);
    defer basename.deinit(ctx);
    if (basename.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "basename", basename)) return false;

    const extname = quickjs.Value.initCFunction(ctx, jsNodePathExtname, "extname", 1);
    defer extname.deinit(ctx);
    if (extname.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "extname", extname)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeUtilModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const inspect = quickjs.Value.initCFunction(ctx, jsNodeUtilInspect, "inspect", 1);
    defer inspect.deinit(ctx);
    if (inspect.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "inspect", inspect)) return false;

    const format = quickjs.Value.initCFunction(ctx, jsNodeUtilFormat, "format", 0);
    defer format.deinit(ctx);
    if (format.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "format", format)) return false;

    const promisify = quickjs.Value.initCFunction(ctx, jsNodeUtilPromisify, "promisify", 1);
    defer promisify.deinit(ctx);
    if (promisify.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "promisify", promisify)) return false;

    const text_encoder = global.getPropertyStr(ctx, "TextEncoder");
    defer text_encoder.deinit(ctx);
    if (text_encoder.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "TextEncoder", text_encoder)) return false;

    const text_decoder = global.getPropertyStr(ctx, "TextDecoder");
    defer text_decoder.deinit(ctx);
    if (text_decoder.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "TextDecoder", text_decoder)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeBufferModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const buffer_ctor = quickjs.Value.initCFunction2(ctx, jsNodeBufferCtor, "Buffer", 1, .constructor_or_func, 0);
    defer buffer_ctor.deinit(ctx);
    if (buffer_ctor.isException()) return false;

    const from = quickjs.Value.initCFunction(ctx, jsNodeBufferFrom, "from", 1);
    defer from.deinit(ctx);
    if (from.isException()) return false;
    buffer_ctor.setPropertyStr(ctx, "from", from.dup(ctx)) catch return false;

    const is_buffer = quickjs.Value.initCFunction(ctx, jsNodeBufferIsBuffer, "isBuffer", 1);
    defer is_buffer.deinit(ctx);
    if (is_buffer.isException()) return false;
    buffer_ctor.setPropertyStr(ctx, "isBuffer", is_buffer.dup(ctx)) catch return false;

    if (!setModuleExportValue(ctx, module, default_export, "Buffer", buffer_ctor)) return false;

    const blob = global.getPropertyStr(ctx, "Blob");
    defer blob.deinit(ctx);
    if (blob.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "Blob", blob)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeCryptoModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const random_uuid = quickjs.Value.initCFunction(ctx, jsNodeCryptoRandomUUID, "randomUUID", 0);
    defer random_uuid.deinit(ctx);
    if (random_uuid.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "randomUUID", random_uuid)) return false;

    const crypto_value = global.getPropertyStr(ctx, "crypto");
    defer crypto_value.deinit(ctx);
    const webcrypto = if (!crypto_value.isException() and crypto_value.isObject()) crypto_value.dup(ctx) else quickjs.Value.initObject(ctx);
    defer webcrypto.deinit(ctx);
    if (webcrypto.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "webcrypto", webcrypto)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeHttpModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const request = quickjs.Value.initCFunction(ctx, jsNodeHttpRequest, "request", 0);
    defer request.deinit(ctx);
    if (request.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "request", request)) return false;

    const get = quickjs.Value.initCFunction(ctx, jsNodeHttpGet, "get", 0);
    defer get.deinit(ctx);
    if (get.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "get", get)) return false;

    const create_server = quickjs.Value.initCFunction(ctx, jsNodeHttpCreateServer, "createServer", 0);
    defer create_server.deinit(ctx);
    if (create_server.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "createServer", create_server)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeHttpsModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const request = quickjs.Value.initCFunction(ctx, jsNodeHttpsRequest, "request", 0);
    defer request.deinit(ctx);
    if (request.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "request", request)) return false;

    const get = quickjs.Value.initCFunction(ctx, jsNodeHttpsGet, "get", 0);
    defer get.deinit(ctx);
    if (get.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "get", get)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeNetModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const create_connection = quickjs.Value.initCFunction(ctx, jsNodeNetCreateConnection, "createConnection", 0);
    defer create_connection.deinit(ctx);
    if (create_connection.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "createConnection", create_connection)) return false;

    const create_server = quickjs.Value.initCFunction(ctx, jsNodeNetCreateServer, "createServer", 0);
    defer create_server.deinit(ctx);
    if (create_server.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "createServer", create_server)) return false;

    const is_ip = quickjs.Value.initCFunction(ctx, jsNodeNetIsIp, "isIP", 1);
    defer is_ip.deinit(ctx);
    if (is_ip.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "isIP", is_ip)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeZlibModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const gzip_sync = quickjs.Value.initCFunction(ctx, jsNodeZlibGzipSync, "gzipSync", 0);
    defer gzip_sync.deinit(ctx);
    if (gzip_sync.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "gzipSync", gzip_sync)) return false;

    const gunzip_sync = quickjs.Value.initCFunction(ctx, jsNodeZlibGunzipSync, "gunzipSync", 0);
    defer gunzip_sync.deinit(ctx);
    if (gunzip_sync.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "gunzipSync", gunzip_sync)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeChildProcessModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const spawn = quickjs.Value.initCFunction(ctx, jsNodeChildProcessSpawn, "spawn", 0);
    defer spawn.deinit(ctx);
    if (spawn.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "spawn", spawn)) return false;

    const exec = quickjs.Value.initCFunction(ctx, jsNodeChildProcessExec, "exec", 0);
    defer exec.deinit(ctx);
    if (exec.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "exec", exec)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeStreamModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const readable = quickjs.Value.initCFunction2(ctx, jsNodeStreamCtor, "Readable", 0, .constructor_or_func, 0);
    defer readable.deinit(ctx);
    if (readable.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "Readable", readable)) return false;

    const writable = quickjs.Value.initCFunction2(ctx, jsNodeStreamCtor, "Writable", 0, .constructor_or_func, 0);
    defer writable.deinit(ctx);
    if (writable.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "Writable", writable)) return false;

    const transform_value = quickjs.Value.initCFunction2(ctx, jsNodeStreamCtor, "Transform", 0, .constructor_or_func, 0);
    defer transform_value.deinit(ctx);
    if (transform_value.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "Transform", transform_value)) return false;

    const duplex = quickjs.Value.initCFunction2(ctx, jsNodeStreamCtor, "Duplex", 0, .constructor_or_func, 0);
    defer duplex.deinit(ctx);
    if (duplex.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "Duplex", duplex)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodeVmModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const run_in_new_context = quickjs.Value.initCFunction(ctx, jsNodeVmRunInNewContext, "runInNewContext", 0);
    defer run_in_new_context.deinit(ctx);
    if (run_in_new_context.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "runInNewContext", run_in_new_context)) return false;

    const run_in_context = quickjs.Value.initCFunction(ctx, jsNodeVmRunInContext, "runInContext", 0);
    defer run_in_context.deinit(ctx);
    if (run_in_context.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "runInContext", run_in_context)) return false;

    const run_in_this_context = quickjs.Value.initCFunction(ctx, jsNodeVmRunInThisContext, "runInThisContext", 0);
    defer run_in_this_context.deinit(ctx);
    if (run_in_this_context.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "runInThisContext", run_in_this_context)) return false;

    const script_ctor = quickjs.Value.initCFunction2(ctx, jsNodeVmScriptCtor, "Script", 0, .constructor_or_func, 0);
    defer script_ctor.deinit(ctx);
    if (script_ctor.isException()) return false;

    const script_proto = script_ctor.getPropertyStr(ctx, "prototype");
    defer script_proto.deinit(ctx);
    if (script_proto.isException() or !script_proto.isObject()) return false;
    const script_run = quickjs.Value.initCFunction(ctx, jsNodeVmScriptRunInThisContext, "runInThisContext", 0);
    defer script_run.deinit(ctx);
    if (script_run.isException()) return false;
    script_proto.setPropertyStr(ctx, "runInThisContext", script_run.dup(ctx)) catch return false;

    if (!setModuleExportValue(ctx, module, default_export, "Script", script_ctor)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn initNativeNodePerfHooksModule(ctx: *ModuleContext, module: *ModuleDef) bool {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const default_export = quickjs.Value.initObject(ctx);
    defer default_export.deinit(ctx);
    if (default_export.isException()) return false;

    const performance = global.getPropertyStr(ctx, "performance");
    defer performance.deinit(ctx);
    if (performance.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "performance", performance)) return false;

    const observer_ctor = quickjs.Value.initCFunction2(ctx, jsNodePerfObserverCtor, "PerformanceObserver", 1, .constructor_or_func, 0);
    defer observer_ctor.deinit(ctx);
    if (observer_ctor.isException()) return false;
    const observer_proto = observer_ctor.getPropertyStr(ctx, "prototype");
    defer observer_proto.deinit(ctx);
    if (observer_proto.isException() or !observer_proto.isObject()) return false;
    const observer_observe = quickjs.Value.initCFunction(ctx, jsNodePerfObserverObserve, "observe", 1);
    defer observer_observe.deinit(ctx);
    if (observer_observe.isException()) return false;
    observer_proto.setPropertyStr(ctx, "observe", observer_observe.dup(ctx)) catch return false;
    const observer_disconnect = quickjs.Value.initCFunction(ctx, jsNodePerfObserverDisconnect, "disconnect", 0);
    defer observer_disconnect.deinit(ctx);
    if (observer_disconnect.isException()) return false;
    observer_proto.setPropertyStr(ctx, "disconnect", observer_disconnect.dup(ctx)) catch return false;
    const observer_take_records = quickjs.Value.initCFunction(ctx, jsNodePerfObserverTakeRecords, "takeRecords", 0);
    defer observer_take_records.deinit(ctx);
    if (observer_take_records.isException()) return false;
    observer_proto.setPropertyStr(ctx, "takeRecords", observer_take_records.dup(ctx)) catch return false;
    if (!setModuleExportValue(ctx, module, default_export, "PerformanceObserver", observer_ctor)) return false;

    const entry_ctor = quickjs.Value.initCFunction2(ctx, jsNodePerfEntryCtor, "PerformanceEntry", 0, .constructor_or_func, 0);
    defer entry_ctor.deinit(ctx);
    if (entry_ctor.isException()) return false;
    if (!setModuleExportValue(ctx, module, default_export, "PerformanceEntry", entry_ctor)) return false;

    return finishModuleDefaultExport(ctx, module, default_export);
}

fn throwUnsupportedNodeApi(
    comptime module_name: [:0]const u8,
    comptime function_name: [:0]const u8,
    ctx: *quickjs.Context,
) quickjs.Value {
    _ = quickjs.c.JS_ThrowInternalError(
        ctx.cval(),
        "node:%s.%s is not implemented in this runner",
        module_name.ptr,
        function_name.ptr,
    );
    return quickjs.Value.exception;
}

fn callAsConstructor(ctx: *quickjs.Context, ctor: quickjs.Value, args: []const quickjs.Value) quickjs.Value {
    if (args.len == 0) {
        return quickjs.Value.fromCVal(quickjs.c.JS_CallConstructor(ctx.cval(), ctor.cval(), 0, null));
    }

    const allocator = std.heap.c_allocator;
    const argv = allocator.alloc(quickjs.c.JSValue, args.len) catch return quickjs.Value.exception;
    defer allocator.free(argv);
    for (args, 0..) |arg, index| {
        argv[index] = arg.cval();
    }

    return quickjs.Value.fromCVal(
        quickjs.c.JS_CallConstructor(
            ctx.cval(),
            ctor.cval(),
            @intCast(args.len),
            @ptrCast(argv.ptr),
        ),
    );
}

fn valueToOwnedString(allocator: Allocator, ctx: *quickjs.Context, value: quickjs.Value, nullish_empty: bool) ![]u8 {
    if (nullish_empty and (value.isUndefined() or value.isNull())) {
        return allocator.dupe(u8, "");
    }

    const text = value.toCStringLen(ctx) orelse return error.ValueConversionFailed;
    defer ctx.freeCString(text.ptr);
    return allocator.dupe(u8, text.ptr[0..text.len]);
}

fn normalizePathSeparatorsAlloc(allocator: Allocator, text: []const u8) ![]u8 {
    var normalized = try allocator.alloc(u8, text.len);
    for (text, 0..) |ch, index| {
        normalized[index] = if (ch == '\\') '/' else ch;
    }
    return normalized;
}

fn getProcessCwdAlloc(allocator: Allocator, ctx: *quickjs.Context) ![]u8 {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const process = global.getPropertyStr(ctx, "process");
    defer process.deinit(ctx);
    if (process.isException() or !process.isObject()) return allocator.dupe(u8, "");

    const cwd_fn = process.getPropertyStr(ctx, "cwd");
    defer cwd_fn.deinit(ctx);
    if (cwd_fn.isException() or !cwd_fn.isFunction(ctx)) return allocator.dupe(u8, "");

    const cwd_value = cwd_fn.call(ctx, process, &.{});
    defer cwd_value.deinit(ctx);
    if (cwd_value.isException()) {
        const exception = ctx.getException();
        exception.deinit(ctx);
        return allocator.dupe(u8, "");
    }

    return valueToOwnedString(allocator, ctx, cwd_value, true);
}

fn resolveNodeFsPathAlloc(allocator: Allocator, ctx: *quickjs.Context, path: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, path, "/")) {
        return allocator.dupe(u8, path);
    }

    const cwd = try getProcessCwdAlloc(allocator, ctx);
    defer allocator.free(cwd);
    var trimmed_len = cwd.len;
    while (trimmed_len > 0 and cwd[trimmed_len - 1] == '/') : (trimmed_len -= 1) {}
    if (trimmed_len == 0) return allocator.dupe(u8, path);

    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ cwd[0..trimmed_len], path });
}

fn jsNodeUrlPathToFileURL(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const raw = valueToOwnedString(allocator, ctx, input, true) catch return quickjs.Value.exception;
    defer allocator.free(raw);

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const url_ctor = global.getPropertyStr(ctx, "URL");
    defer url_ctor.deinit(ctx);
    if (url_ctor.isException() or !url_ctor.isFunction(ctx)) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "URL constructor is not available");
        return quickjs.Value.exception;
    }

    const url_text = blk: {
        if (std.mem.startsWith(u8, raw, "file:")) {
            break :blk allocator.dupe(u8, raw) catch return quickjs.Value.exception;
        }
        const normalized = normalizePathSeparatorsAlloc(allocator, raw) catch return quickjs.Value.exception;
        defer allocator.free(normalized);

        const prefixed = if (normalized.len > 0 and normalized[0] == '/')
            allocator.dupe(u8, normalized) catch return quickjs.Value.exception
        else
            std.fmt.allocPrint(allocator, "/{s}", .{normalized}) catch return quickjs.Value.exception;
        defer allocator.free(prefixed);

        break :blk std.fmt.allocPrint(allocator, "file://{s}", .{prefixed}) catch return quickjs.Value.exception;
    };
    defer allocator.free(url_text);

    const url_arg = quickjs.Value.initStringLen(ctx, url_text);
    defer url_arg.deinit(ctx);
    return callAsConstructor(ctx, url_ctor, &.{url_arg});
}

fn jsNodeUrlFileURLToPath(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const url_ctor = global.getPropertyStr(ctx, "URL");
    defer url_ctor.deinit(ctx);
    if (url_ctor.isException() or !url_ctor.isFunction(ctx)) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "URL constructor is not available");
        return quickjs.Value.exception;
    }

    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const parsed = blk: {
        if (input.isObject()) {
            const is_instance = input.isInstanceOf(ctx, url_ctor) catch false;
            if (is_instance) break :blk input.dup(ctx);
        }

        const raw = valueToOwnedString(allocator, ctx, input, true) catch return quickjs.Value.exception;
        defer allocator.free(raw);
        const arg = quickjs.Value.initStringLen(ctx, raw);
        defer arg.deinit(ctx);
        break :blk callAsConstructor(ctx, url_ctor, &.{arg});
    };
    defer parsed.deinit(ctx);
    if (parsed.isException()) return quickjs.Value.exception;

    const protocol = parsed.getPropertyStr(ctx, "protocol");
    defer protocol.deinit(ctx);
    const protocol_text = protocol.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(protocol_text.ptr);
    if (!std.mem.eql(u8, protocol_text.ptr[0..protocol_text.len], "file:")) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "fileURLToPath expects a file URL");
        return quickjs.Value.exception;
    }

    const pathname = parsed.getPropertyStr(ctx, "pathname");
    defer pathname.deinit(ctx);
    if (pathname.isException()) return quickjs.Value.exception;

    const decode = global.getPropertyStr(ctx, "decodeURIComponent");
    defer decode.deinit(ctx);
    if (!decode.isException() and decode.isFunction(ctx)) {
        return decode.call(ctx, quickjs.Value.undefined, &.{pathname.dup(ctx)});
    }

    return pathname.dup(ctx);
}

fn jsNodeFsReadFileSync(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;

    const path_arg = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const raw_path = valueToOwnedString(allocator, ctx, path_arg, false) catch return quickjs.Value.exception;
    defer allocator.free(raw_path);

    const encoding = if (args.len > 1)
        valueToOwnedString(allocator, ctx, quickjs.Value.fromCVal(args[1]), false) catch return quickjs.Value.exception
    else
        allocator.dupe(u8, "utf8") catch return quickjs.Value.exception;
    defer allocator.free(encoding);

    if (!std.mem.eql(u8, encoding, "utf8") and !std.mem.eql(u8, encoding, "utf-8")) {
        return throwUnsupportedNodeApi("fs", "readFileSync", ctx);
    }

    const resolved = resolveNodeFsPathAlloc(allocator, ctx, raw_path) catch return quickjs.Value.exception;
    defer allocator.free(resolved);

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const read_fn = global.getPropertyStr(ctx, "__zigReadFileSync");
    defer read_fn.deinit(ctx);
    if (read_fn.isException() or !read_fn.isFunction(ctx)) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "__zigReadFileSync is not available");
        return quickjs.Value.exception;
    }

    const path_value = quickjs.Value.initStringLen(ctx, resolved);
    defer path_value.deinit(ctx);
    const encoding_value = quickjs.Value.initStringLen(ctx, encoding);
    defer encoding_value.deinit(ctx);
    return read_fn.call(ctx, quickjs.Value.undefined, &.{ path_value, encoding_value });
}

fn jsNodeFsWriteFileSync(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    const path_arg = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const data_arg = if (args.len > 1) quickjs.Value.fromCVal(args[1]) else quickjs.Value.undefined;
    const raw_path = valueToOwnedString(allocator, ctx, path_arg, false) catch return quickjs.Value.exception;
    defer allocator.free(raw_path);
    const data = valueToOwnedString(allocator, ctx, data_arg, true) catch return quickjs.Value.exception;
    defer allocator.free(data);
    const resolved = resolveNodeFsPathAlloc(allocator, ctx, raw_path) catch return quickjs.Value.exception;
    defer allocator.free(resolved);
    const path_z = allocator.dupeZ(u8, resolved) catch return quickjs.Value.exception;
    defer allocator.free(path_z);
    const file = std.c.fopen(path_z.ptr, "wb") orelse return quickjs.Value.exception;
    defer _ = std.c.fclose(file);
    if (data.len > 0 and std.c.fwrite(data.ptr, 1, data.len, file) != data.len) return quickjs.Value.exception;
    return quickjs.Value.undefined;
}

fn jsNodeFsMkdirSync(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    const path_arg = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const raw_path = valueToOwnedString(allocator, ctx, path_arg, false) catch return quickjs.Value.exception;
    defer allocator.free(raw_path);
    const resolved = resolveNodeFsPathAlloc(allocator, ctx, raw_path) catch return quickjs.Value.exception;
    defer allocator.free(resolved);
    const path_z = allocator.dupeZ(u8, resolved) catch return quickjs.Value.exception;
    defer allocator.free(path_z);
    _ = std.c.mkdir(path_z.ptr, 0o755);
    return quickjs.Value.undefined;
}

fn jsNodeFsReaddirSync(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    const path_arg = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const raw_path = valueToOwnedString(allocator, ctx, path_arg, false) catch return quickjs.Value.exception;
    defer allocator.free(raw_path);
    const resolved = resolveNodeFsPathAlloc(allocator, ctx, raw_path) catch return quickjs.Value.exception;
    defer allocator.free(resolved);
    const path_z = allocator.dupeZ(u8, resolved) catch return quickjs.Value.exception;
    defer allocator.free(path_z);

    const dir = std.c.opendir(path_z.ptr) orelse return quickjs.Value.exception;
    defer _ = std.c.closedir(dir);

    const out = quickjs.Value.initArray(ctx);
    if (out.isException()) return out;
    var index: u32 = 0;
    while (std.c.readdir(dir)) |entry| {
        const name = std.mem.sliceTo(&entry.name, 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        out.setPropertyUint32(ctx, index, quickjs.Value.initStringLen(ctx, name)) catch return quickjs.Value.exception;
        index += 1;
    }
    return out;
}

fn jsNodeFsExistsSync(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    const path_arg = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const raw_path = valueToOwnedString(allocator, ctx, path_arg, false) catch return quickjs.Value.exception;
    defer allocator.free(raw_path);
    const resolved = resolveNodeFsPathAlloc(allocator, ctx, raw_path) catch return quickjs.Value.exception;
    defer allocator.free(resolved);
    const path_z = allocator.dupeZ(u8, resolved) catch return quickjs.Value.exception;
    defer allocator.free(path_z);
    return quickjs.Value.initBool(std.c.access(path_z.ptr, 0) == 0);
}

fn nodePathJoinLike(ctx: *quickjs.Context, args: []const quickjs.c.JSValue) quickjs.Value {
    const allocator = std.heap.c_allocator;
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(allocator);

    for (args) |arg| {
        const raw = valueToOwnedString(allocator, ctx, quickjs.Value.fromCVal(arg), true) catch return quickjs.Value.exception;
        defer allocator.free(raw);
        const normalized = normalizePathSeparatorsAlloc(allocator, raw) catch return quickjs.Value.exception;
        defer allocator.free(normalized);
        if (normalized.len == 0) continue;
        if (joined.items.len > 0 and joined.items[joined.items.len - 1] != '/') {
            joined.append(allocator, '/') catch return quickjs.Value.exception;
        }
        joined.appendSlice(allocator, normalized) catch return quickjs.Value.exception;
    }

    var compact: std.ArrayList(u8) = .empty;
    defer compact.deinit(allocator);
    var previous_was_slash = false;
    for (joined.items) |ch| {
        if (ch == '/') {
            if (previous_was_slash) continue;
            previous_was_slash = true;
        } else {
            previous_was_slash = false;
        }
        compact.append(allocator, ch) catch return quickjs.Value.exception;
    }

    return quickjs.Value.initStringLen(ctx, compact.items);
}

fn jsNodePathJoin(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return nodePathJoinLike(ctx, args);
}

fn jsNodePathResolve(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return nodePathJoinLike(ctx, args);
}

fn jsNodePathDirname(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const raw = valueToOwnedString(allocator, ctx, input, true) catch return quickjs.Value.exception;
    defer allocator.free(raw);
    const normalized = normalizePathSeparatorsAlloc(allocator, raw) catch return quickjs.Value.exception;
    defer allocator.free(normalized);
    const index = std.mem.lastIndexOfScalar(u8, normalized, '/') orelse return quickjs.Value.initStringLen(ctx, ".");
    if (index <= 0) return quickjs.Value.initStringLen(ctx, ".");
    return quickjs.Value.initStringLen(ctx, normalized[0..index]);
}

fn jsNodePathBasename(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    const raw = valueToOwnedString(allocator, ctx, input, true) catch return quickjs.Value.exception;
    defer allocator.free(raw);
    const normalized = normalizePathSeparatorsAlloc(allocator, raw) catch return quickjs.Value.exception;
    defer allocator.free(normalized);
    const index = std.mem.lastIndexOfScalar(u8, normalized, '/') orelse return quickjs.Value.initStringLen(ctx, normalized);
    return quickjs.Value.initStringLen(ctx, normalized[index + 1 ..]);
}

fn jsNodePathExtname(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const base = jsNodePathBasename(ctx_opt, quickjs.Value.undefined, args);
    defer base.deinit(ctx);
    if (base.isException()) return quickjs.Value.exception;

    const base_text = base.toCStringLen(ctx) orelse return quickjs.Value.exception;
    defer ctx.freeCString(base_text.ptr);
    const base_slice = base_text.ptr[0..base_text.len];
    const index = std.mem.lastIndexOfScalar(u8, base_slice, '.') orelse return quickjs.Value.initStringLen(ctx, "");
    if (index <= 0) return quickjs.Value.initStringLen(ctx, "");
    return quickjs.Value.initStringLen(ctx, base_slice[index..]);
}

fn jsNodeUtilInspect(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);

    const json = global.getPropertyStr(ctx, "JSON");
    defer json.deinit(ctx);
    if (!json.isException() and json.isObject()) {
        const stringify = json.getPropertyStr(ctx, "stringify");
        defer stringify.deinit(ctx);
        if (!stringify.isException() and stringify.isFunction(ctx)) {
            const input = if (args.len > 0) quickjs.Value.fromCVal(args[0]).dup(ctx) else quickjs.Value.undefined;
            defer input.deinit(ctx);
            const result = stringify.call(ctx, json, &.{input});
            if (!result.isException() and !result.isUndefined()) {
                return result;
            }
            if (result.isException()) {
                const exception = ctx.getException();
                exception.deinit(ctx);
            }
            result.deinit(ctx);
        }
    }

    const value = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;
    return value.toStringValue(ctx);
}

fn jsNodeUtilFormat(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const allocator = std.heap.c_allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    for (args, 0..) |arg, index| {
        if (index > 0) out.append(allocator, ' ') catch return quickjs.Value.exception;
        const text = quickjs.Value.fromCVal(arg).toCStringLen(ctx) orelse return quickjs.Value.exception;
        defer ctx.freeCString(text.ptr);
        out.appendSlice(allocator, text.ptr[0..text.len]) catch return quickjs.Value.exception;
    }

    return quickjs.Value.initStringLen(ctx, out.items);
}

fn jsNodeUtilPromisify(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "promisify expects a function");
        return quickjs.Value.exception;
    }

    const fn_value = quickjs.Value.fromCVal(args[0]);
    if (!fn_value.isFunction(ctx)) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "promisify expects a function");
        return quickjs.Value.exception;
    }

    var data = [_]quickjs.Value{fn_value.dup(ctx)};
    defer data[0].deinit(ctx);
    return quickjs.Value.initCFunctionData(ctx, jsNodeUtilPromisifiedCall, 0, 0, &data);
}

fn jsNodeUtilPromisifiedCall(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    _: c_int,
    func_data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const original = quickjs.Value.fromCVal(func_data[0]);
    if (!original.isFunction(ctx)) {
        _ = quickjs.c.JS_ThrowTypeError(ctx.cval(), "promisified target is not callable");
        return quickjs.Value.exception;
    }

    var promise = quickjs.Value.initPromiseCapability(ctx);
    if (promise.value.isException()) {
        promise.resolve.deinit(ctx);
        promise.reject.deinit(ctx);
        return quickjs.Value.exception;
    }
    defer promise.resolve.deinit(ctx);
    defer promise.reject.deinit(ctx);

    var callback_data = [_]quickjs.Value{ promise.resolve.dup(ctx), promise.reject.dup(ctx) };
    defer callback_data[0].deinit(ctx);
    defer callback_data[1].deinit(ctx);

    const callback = quickjs.Value.initCFunctionData(ctx, jsNodeUtilPromisifyCallback, 2, 0, &callback_data);
    defer callback.deinit(ctx);
    if (callback.isException()) {
        promise.value.deinit(ctx);
        return quickjs.Value.exception;
    }

    const allocator = std.heap.c_allocator;
    const call_args = allocator.alloc(quickjs.Value, args.len + 1) catch {
        promise.value.deinit(ctx);
        return quickjs.Value.exception;
    };
    defer allocator.free(call_args);
    defer for (call_args) |value| value.deinit(ctx);

    for (args, 0..) |arg, index| {
        call_args[index] = quickjs.Value.fromCVal(arg).dup(ctx);
    }
    call_args[args.len] = callback.dup(ctx);

    const call_result = original.call(ctx, quickjs.Value.undefined, call_args);
    if (call_result.isException()) {
        call_result.deinit(ctx);
        const exception = ctx.getException();
        defer exception.deinit(ctx);
        const rejected_value = exception.dup(ctx);
        defer rejected_value.deinit(ctx);
        const reject_result = promise.reject.call(ctx, quickjs.Value.undefined, &.{rejected_value});
        reject_result.deinit(ctx);
    } else {
        call_result.deinit(ctx);
    }

    return promise.value;
}

fn jsNodeUtilPromisifyCallback(
    ctx_opt: ?*quickjs.Context,
    _: quickjs.Value,
    args: []const quickjs.c.JSValue,
    _: c_int,
    func_data: [*c]quickjs.c.JSValue,
) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const resolve = quickjs.Value.fromCVal(func_data[0]);
    const reject = quickjs.Value.fromCVal(func_data[1]);
    const error_value = if (args.len > 0) quickjs.Value.fromCVal(args[0]) else quickjs.Value.undefined;

    if (!error_value.isUndefined() and !error_value.isNull()) {
        const rejected_value = error_value.dup(ctx);
        defer rejected_value.deinit(ctx);
        const result = reject.call(ctx, quickjs.Value.undefined, &.{rejected_value});
        result.deinit(ctx);
        return quickjs.Value.undefined;
    }

    const success_value = if (args.len > 1) quickjs.Value.fromCVal(args[1]).dup(ctx) else quickjs.Value.undefined.dup(ctx);
    defer success_value.deinit(ctx);
    const result = resolve.call(ctx, quickjs.Value.undefined, &.{success_value});
    result.deinit(ctx);
    return quickjs.Value.undefined;
}

fn makeUint8Array(ctx: *quickjs.Context, input: ?quickjs.Value) quickjs.Value {
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const ctor = global.getPropertyStr(ctx, "Uint8Array");
    defer ctor.deinit(ctx);
    if (ctor.isException() or !ctor.isFunction(ctx)) return quickjs.Value.exception;
    if (input) |value| return callAsConstructor(ctx, ctor, &.{value});
    const zero = quickjs.Value.initInt32(0);
    defer zero.deinit(ctx);
    return callAsConstructor(ctx, ctor, &.{zero});
}

fn jsNodeBufferCtor(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return makeUint8Array(ctx, null);
    return makeUint8Array(ctx, quickjs.Value.fromCVal(args[0]));
}

fn jsNodeBufferFrom(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return makeUint8Array(ctx, null);

    const input = quickjs.Value.fromCVal(args[0]);
    if (input.isString()) {
        const global = ctx.getGlobalObject();
        defer global.deinit(ctx);
        const text_encoder_ctor = global.getPropertyStr(ctx, "TextEncoder");
        defer text_encoder_ctor.deinit(ctx);
        if (!text_encoder_ctor.isException() and text_encoder_ctor.isFunction(ctx)) {
            const encoder = callAsConstructor(ctx, text_encoder_ctor, &.{});
            defer encoder.deinit(ctx);
            if (!encoder.isException()) {
                const encode = encoder.getPropertyStr(ctx, "encode");
                defer encode.deinit(ctx);
                if (!encode.isException() and encode.isFunction(ctx)) {
                    return encode.call(ctx, encoder, &.{input.dup(ctx)});
                }
            }
        }
    }

    var result = makeUint8Array(ctx, input);
    if (!result.isException()) return result;
    const exception = ctx.getException();
    exception.deinit(ctx);
    result.deinit(ctx);
    return makeUint8Array(ctx, null);
}

fn jsNodeBufferIsBuffer(ctx_opt: ?*quickjs.Context, _: quickjs.Value, args: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (args.len == 0) return quickjs.Value.initBool(false);

    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const uint8_ctor = global.getPropertyStr(ctx, "Uint8Array");
    defer uint8_ctor.deinit(ctx);
    if (uint8_ctor.isException() or !uint8_ctor.isFunction(ctx)) return quickjs.Value.initBool(false);

    const input = quickjs.Value.fromCVal(args[0]);
    const is_buffer = if (input.isObject()) input.isInstanceOf(ctx, uint8_ctor) catch false else false;
    return quickjs.Value.initBool(is_buffer);
}

fn jsNodeCryptoRandomUUID(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    const global = ctx.getGlobalObject();
    defer global.deinit(ctx);
    const crypto_value = global.getPropertyStr(ctx, "crypto");
    defer crypto_value.deinit(ctx);
    if (!crypto_value.isException() and crypto_value.isObject()) {
        const random_uuid = crypto_value.getPropertyStr(ctx, "randomUUID");
        defer random_uuid.deinit(ctx);
        if (!random_uuid.isException() and random_uuid.isFunction(ctx)) {
            return random_uuid.call(ctx, crypto_value, &.{});
        }
    }
    return quickjs.Value.initStringLen(ctx, "00000000-0000-4000-8000-000000000000");
}

fn jsNodeHttpRequest(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("http", "request", ctx);
}

fn jsNodeHttpGet(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("http", "get", ctx);
}

fn jsNodeHttpCreateServer(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("http", "createServer", ctx);
}

fn jsNodeHttpsRequest(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("http", "request", ctx);
}

fn jsNodeHttpsGet(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("http", "get", ctx);
}

fn jsNodeNetCreateConnection(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("net", "createConnection", ctx);
}

fn jsNodeNetCreateServer(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("net", "createServer", ctx);
}

fn jsNodeNetIsIp(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.initInt32(0);
}

fn jsNodeZlibGzipSync(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("zlib", "gzipSync", ctx);
}

fn jsNodeZlibGunzipSync(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("zlib", "gunzipSync", ctx);
}

fn jsNodeChildProcessSpawn(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("child_process", "spawn", ctx);
}

fn jsNodeChildProcessExec(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("child_process", "exec", ctx);
}

fn jsNodeStreamCtor(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (this_value.isObject()) return this_value.dup(ctx);
    return quickjs.Value.initObject(ctx);
}

fn jsNodeVmRunInNewContext(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("vm", "runInNewContext", ctx);
}

fn jsNodeVmRunInContext(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("vm", "runInContext", ctx);
}

fn jsNodeVmRunInThisContext(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("vm", "runInThisContext", ctx);
}

fn jsNodeVmScriptCtor(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (this_value.isObject()) return this_value.dup(ctx);
    return quickjs.Value.initObject(ctx);
}

fn jsNodeVmScriptRunInThisContext(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return throwUnsupportedNodeApi("vm", "Script.runInThisContext", ctx);
}

fn jsNodePerfObserverCtor(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (this_value.isObject()) return this_value.dup(ctx);
    return quickjs.Value.initObject(ctx);
}

fn jsNodePerfObserverObserve(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsNodePerfObserverDisconnect(_: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    return quickjs.Value.undefined;
}

fn jsNodePerfObserverTakeRecords(ctx_opt: ?*quickjs.Context, _: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    return quickjs.Value.initArray(ctx);
}

fn jsNodePerfEntryCtor(ctx_opt: ?*quickjs.Context, this_value: quickjs.Value, _: []const quickjs.c.JSValue) quickjs.Value {
    const ctx = ctx_opt orelse return quickjs.Value.exception;
    if (this_value.isObject()) return this_value.dup(ctx);
    return quickjs.Value.initObject(ctx);
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
    if (std.mem.eql(u8, module_name, bun_specifier) or
        std.mem.eql(u8, module_name, bun_test_specifier) or
        std.mem.eql(u8, module_name, happy_dom_global_registrator_specifier) or
        std.mem.eql(u8, module_name, testing_library_dom_specifier) or
        std.mem.eql(u8, module_name, testing_library_react_specifier))
    {
        return native_builtin_stub_source;
    }

    const bare_name = if (std.mem.startsWith(u8, module_name, node_specifier_prefix))
        module_name[node_specifier_prefix.len..]
    else
        module_name;

    inline for (native_node_builtin_specifiers) |specifier| {
        if (std.mem.eql(u8, bare_name, specifier)) return native_builtin_stub_source;
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

    if (sourceHasCodePattern(source, "module.exports") or
        sourceHasCodePattern(source, "exports.") or
        sourceHasCodePattern(source, "Object.defineProperty(exports") or
        sourceHasCodePattern(source, "Object.defineProperty(module"))
    {
        return true;
    }

    if (sourceHasCodePattern(source, "typeof exports") and
        sourceHasCodePattern(source, "typeof module"))
    {
        return true;
    }

    if (!sourceHasCodePattern(source, "require(")) {
        return false;
    }

    return !sourceHasCodePattern(source, "import ") and !sourceHasCodePattern(source, "export ");
}

fn sourceHasCodePattern(source: []const u8, pattern: []const u8) bool {
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

        if (std.mem.startsWith(u8, source[cursor..], pattern)) return true;
        cursor += 1;
    }

    return false;
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
) anyerror!?CommonJsBarrelPropertyRewrite {
    if (findDefinePropertyExport(root_source, name)) |export_index| {
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

    if (parseModuleExportsRequireSpecifier(root_source)) |required| {
        const resolved = try state.normalizeRequireSpecifier(root_module_id, required);
        defer state.allocator.free(resolved);
        if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) return null;
        const child_source = state.readFileCached(resolved, max_module_source_bytes) catch return null;
        if (!isCommonJsSource(resolved, child_source)) return null;

        if (try commonJsBarrelRewriteForExport(state, resolved, child_source, name)) |nested| {
            return nested;
        }
        if (commonJsModuleExportsObjectContainsKey(child_source, name)) {
            return .{
                .export_name = try state.allocator.dupe(u8, name),
                .resolved_specifier = try state.allocator.dupe(u8, resolved),
                .member_name = try state.allocator.dupe(u8, name),
            };
        }
    }

    if (parseModuleExportsIdentifier(root_source)) |target_ident| {
        if (try commonJsObjectAssignRewriteForExport(state, root_module_id, root_source, target_ident, name)) |rewrite| {
            return rewrite;
        }
    }

    return null;
}

fn commonJsObjectAssignRewriteForExport(
    state: *ModuleLoaderState,
    root_module_id: []const u8,
    root_source: []const u8,
    target_ident: []const u8,
    name: []const u8,
) anyerror!?CommonJsBarrelPropertyRewrite {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, root_source, cursor, "Object.assign(")) |assign_index| {
        var parse_cursor = assign_index + "Object.assign(".len;
        skipTrivia(root_source, &parse_cursor);
        const local_end = readIdentifierEnd(root_source, parse_cursor);
        if (local_end == parse_cursor) {
            cursor = assign_index + "Object.assign(".len;
            continue;
        }
        const local = root_source[parse_cursor..local_end];
        if (!std.mem.eql(u8, local, target_ident)) {
            cursor = local_end;
            continue;
        }
        parse_cursor = local_end;
        skipTrivia(root_source, &parse_cursor);
        if (parse_cursor >= root_source.len or root_source[parse_cursor] != ',') {
            cursor = local_end;
            continue;
        }
        parse_cursor += 1;
        skipTrivia(root_source, &parse_cursor);
        if (!std.mem.startsWith(u8, root_source[parse_cursor..], "require(")) {
            cursor = parse_cursor;
            continue;
        }
        const required = parseRequireSpecifierAt(root_source, parse_cursor) orelse {
            cursor = parse_cursor + "require(".len;
            continue;
        };
        const resolved = state.normalizeRequireSpecifier(root_module_id, required) catch {
            cursor = parse_cursor + "require(".len;
            continue;
        };
        defer state.allocator.free(resolved);
        if (builtInModuleSource(resolved) != null or isMockModuleId(resolved)) {
            cursor = parse_cursor + "require(".len;
            continue;
        }

        const child_source = state.readFileCached(resolved, max_module_source_bytes) catch {
            cursor = parse_cursor + "require(".len;
            continue;
        };
        if (!isCommonJsSource(resolved, child_source)) {
            cursor = parse_cursor + "require(".len;
            continue;
        }
        if (try commonJsBarrelRewriteForExport(state, resolved, child_source, name)) |nested| {
            return nested;
        }
        if (commonJsModuleExportsObjectContainsKey(child_source, name)) {
            return .{
                .export_name = try state.allocator.dupe(u8, name),
                .resolved_specifier = try state.allocator.dupe(u8, resolved),
                .member_name = try state.allocator.dupe(u8, name),
            };
        }
        cursor = parse_cursor + "require(".len;
    }
    return null;
}

fn parseModuleExportsIdentifier(source: []const u8) ?[]const u8 {
    const assignment = findModuleExportsAssignment(source) orelse return null;
    var cursor = assignment;
    skipTrivia(source, &cursor);
    if (cursor >= source.len or std.mem.startsWith(u8, source[cursor..], "require(")) return null;
    if (!isIdentifierStart(source[cursor])) return null;
    const ident_end = readIdentifierEnd(source, cursor);
    if (ident_end == cursor) return null;
    return source[cursor..ident_end];
}

fn parseModuleExportsRequireSpecifier(source: []const u8) ?[]const u8 {
    const assignment = findModuleExportsAssignment(source) orelse return null;
    var cursor = assignment;
    skipTrivia(source, &cursor);
    if (!std.mem.startsWith(u8, source[cursor..], "require(")) return null;
    return parseRequireSpecifierAt(source, cursor);
}

fn findModuleExportsAssignment(source: []const u8) ?usize {
    const exports_index = std.mem.indexOf(u8, source, "module.exports") orelse return null;
    var cursor = exports_index + "module.exports".len;
    skipTrivia(source, &cursor);
    if (cursor >= source.len or source[cursor] != '=') return null;
    return cursor + 1;
}

fn commonJsModuleExportsObjectContainsKey(source: []const u8, key: []const u8) bool {
    const assignment = findModuleExportsAssignment(source) orelse return false;
    var cursor = assignment;
    skipTrivia(source, &cursor);
    if (cursor >= source.len or source[cursor] != '{') return false;
    var depth: usize = 0;

    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '/' and cursor + 1 < source.len and source[cursor + 1] == '/') {
            cursor = skipLineComment(source, cursor);
            continue;
        }
        if (ch == '/' and cursor + 1 < source.len and source[cursor + 1] == '*') {
            cursor = skipBlockComment(source, cursor);
            continue;
        }
        if (ch == '\'' or ch == '"' or ch == '`') {
            const quoted_end = skipQuotedLiteral(source, cursor);
            if (depth == 1 and ch != '`') {
                if (parseQuotedSpecifier(source, cursor)) |literal| {
                    var after_key = literal.next_index;
                    skipTrivia(source, &after_key);
                    if (after_key < source.len and source[after_key] == ':' and std.mem.eql(u8, literal.specifier, key)) {
                        return true;
                    }
                }
            }
            cursor = quoted_end - 1;
            continue;
        }
        if (ch == '{') {
            depth += 1;
            continue;
        }
        if (ch == '}') {
            if (depth == 0) return false;
            depth -= 1;
            if (depth == 0) return false;
            continue;
        }
        if (depth == 1 and isIdentifierStart(ch)) {
            const key_start = cursor;
            const key_end = readIdentifierEnd(source, key_start);
            if (key_end > key_start) {
                var after_key = key_end;
                skipTrivia(source, &after_key);
                if (after_key < source.len and source[after_key] == ':' and std.mem.eql(u8, source[key_start..key_end], key)) {
                    return true;
                }
                cursor = key_end - 1;
            }
        }
    }

    return false;
}

fn isIdentifierStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$';
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
    return traversal.findMatchingDelimiter(source, open_index, '{', '}');
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

const TestingLibraryNamedBinding = struct {
    imported: []u8,
    local: []u8,

    fn deinit(self: *TestingLibraryNamedBinding, allocator: Allocator) void {
        allocator.free(self.imported);
        allocator.free(self.local);
    }
};

fn buildTestingLibraryNamedImportReplacement(
    allocator: Allocator,
    parsed: ParsedImportStatement,
) !?[]u8 {
    const global_name = if (std.mem.eql(u8, parsed.specifier, testing_library_dom_specifier))
        "__zigTestingLibraryDom"
    else if (std.mem.eql(u8, parsed.specifier, testing_library_react_specifier))
        "__zigTestingLibraryReact"
    else
        return null;

    if (parsed.all) return null;
    const bindings = std.mem.trim(u8, parsed.bindings, " \t\r\n");
    if (!std.mem.startsWith(u8, bindings, "{") or !std.mem.endsWith(u8, bindings, "}")) return null;

    var runtime_bindings: std.ArrayList(TestingLibraryNamedBinding) = .empty;
    defer {
        for (runtime_bindings.items) |*binding| binding.deinit(allocator);
        runtime_bindings.deinit(allocator);
    }

    var type_bindings: std.ArrayList([]u8) = .empty;
    defer {
        for (type_bindings.items) |item| allocator.free(item);
        type_bindings.deinit(allocator);
    }

    var saw_part = false;
    var parts = std.mem.tokenizeScalar(u8, bindings[1 .. bindings.len - 1], ',');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) continue;
        saw_part = true;

        if (std.mem.startsWith(u8, part, "type ")) {
            try type_bindings.append(allocator, try allocator.dupe(u8, part));
            continue;
        }

        const as_index = std.mem.indexOf(u8, part, " as ");
        const imported = std.mem.trim(u8, if (as_index) |idx| part[0..idx] else part, " \t\r\n");
        const local = std.mem.trim(u8, if (as_index) |idx| part[idx + " as ".len ..] else part, " \t\r\n");
        if (!isValidIdentifier(imported) or !isValidIdentifier(local)) return null;

        try runtime_bindings.append(allocator, .{
            .imported = try allocator.dupe(u8, imported),
            .local = try allocator.dupe(u8, local),
        });
    }

    if (!saw_part) return null;
    if (runtime_bindings.items.len == 0) return null;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    if (type_bindings.items.len > 0) {
        try out.appendSlice(allocator, "import { ");
        for (type_bindings.items, 0..) |binding, index| {
            if (index > 0) try out.appendSlice(allocator, ", ");
            try out.appendSlice(allocator, binding);
        }
        try out.appendSlice(allocator, " } from \"");
        try out.appendSlice(allocator, parsed.specifier);
        try out.appendSlice(allocator, "\";\n");
    }

    try out.appendSlice(allocator, "const { ");
    for (runtime_bindings.items, 0..) |binding, index| {
        if (index > 0) try out.appendSlice(allocator, ", ");
        if (std.mem.eql(u8, binding.imported, binding.local)) {
            try out.appendSlice(allocator, binding.local);
        } else {
            try appendFmt(allocator, &out, "{s}: {s}", .{ binding.imported, binding.local });
        }
    }
    try out.appendSlice(allocator, " } = globalThis.");
    try out.appendSlice(allocator, global_name);
    try out.appendSlice(allocator, ";\n");
    return @as(?[]u8, try out.toOwnedSlice(allocator));
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

test "testing library import rewrite handles named imports" {
    const statement = "import { cleanup, render } from \"@testing-library/react\";";
    const parsed = parseImportStatement(statement).?;
    const rewritten = (try buildTestingLibraryNamedImportReplacement(std.testing.allocator, parsed)).?;
    defer std.testing.allocator.free(rewritten);

    try std.testing.expect(std.mem.indexOf(u8, rewritten, "cleanup") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "render") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "globalThis.__zigTestingLibraryReact") != null);
}

test "testing library import rewrite preserves aliases" {
    const statement = "import { render as rtlRender } from \"@testing-library/react\";";
    const parsed = parseImportStatement(statement).?;
    const rewritten = (try buildTestingLibraryNamedImportReplacement(std.testing.allocator, parsed)).?;
    defer std.testing.allocator.free(rewritten);

    try std.testing.expect(std.mem.indexOf(u8, rewritten, "render: rtlRender") != null);
}

test "testing library import rewrite keeps type-only bindings" {
    const statement = "import { type RenderResult, render } from \"@testing-library/react\";";
    const parsed = parseImportStatement(statement).?;
    const rewritten = (try buildTestingLibraryNamedImportReplacement(std.testing.allocator, parsed)).?;
    defer std.testing.allocator.free(rewritten);

    try std.testing.expect(std.mem.indexOf(u8, rewritten, "import { type RenderResult } from \"@testing-library/react\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "const { render } = globalThis.__zigTestingLibraryReact;") != null);
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
    try std.testing.expect(builtInModuleSource("@happy-dom/global-registrator") != null);
    try std.testing.expect(builtInModuleSource("@testing-library/dom") != null);
    try std.testing.expect(builtInModuleSource("@testing-library/react") != null);
    try std.testing.expect(builtInModuleSource("fs") != null);
    try std.testing.expect(builtInModuleSource("node:fs") != null);
    try std.testing.expect(builtInModuleSource("stream/web") != null);
    try std.testing.expect(builtInModuleSource("node:stream/web") != null);
    try std.testing.expect(builtInModuleSource("node:react") == null);
    try std.testing.expect(builtInModuleSource("zig-dom") == null);
    try std.testing.expect(builtInModuleSource("react") == null);
}

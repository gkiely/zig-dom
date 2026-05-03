const std = @import("std");
const api = @import("ffi/api.zig");

const Allocator = std.mem.Allocator;
const c_allocator = std.heap.c_allocator;

const Attribute = struct {
    name: []u8,
    value: []u8,
};

const Node = struct {
    kind: api.NodeKind,
    name: []u8,
    data: []u8,
    owner_document: u64,
    parent: u64,
    first_child: u64,
    last_child: u64,
    prev_sibling: u64,
    next_sibling: u64,
    attributes: std.ArrayListUnmanaged(Attribute),

    fn deinit(self: *Node) void {
        c_allocator.free(self.name);
        c_allocator.free(self.data);
        for (self.attributes.items) |attr| {
            c_allocator.free(attr.name);
            c_allocator.free(attr.value);
        }
        self.attributes.deinit(c_allocator);
    }
};

const Window = struct {
    handle: u64,
    nodes: std.AutoHashMapUnmanaged(u64, Node),
    document_handle: u64,
    html_handle: u64,
    head_handle: u64,
    body_handle: u64,
};

var global_windows = std.AutoHashMapUnmanaged(u64, *Window){};
var global_node_to_window = std.AutoHashMapUnmanaged(u64, u64){};
var next_window_handle: u64 = 1;
var next_node_handle: u64 = 1024;

const STATUS_OK: u32 = @intFromEnum(api.Status.ok);
const STATUS_INVALID_HANDLE: u32 = @intFromEnum(api.Status.invalid_handle);
const STATUS_HIERARCHY: u32 = @intFromEnum(api.Status.hierarchy_request);
const STATUS_NOT_FOUND: u32 = @intFromEnum(api.Status.not_found);
const STATUS_OOM: u32 = @intFromEnum(api.Status.out_of_memory);
const STATUS_INVALID_ARGUMENT: u32 = @intFromEnum(api.Status.invalid_argument);
const STATUS_INTERNAL: u32 = @intFromEnum(api.Status.internal_error);

const VERSION = "0.1.0\x00";

fn makeOwned(bytes: []const u8) ![]u8 {
    return try c_allocator.dupe(u8, bytes);
}

fn makeOwnedLower(bytes: []const u8) ![]u8 {
    const copy = try c_allocator.dupe(u8, bytes);
    for (copy) |*item| {
        item.* = std.ascii.toLower(item.*);
    }
    return copy;
}

fn resolveWindow(window_handle: u64) ?*Window {
    return global_windows.get(window_handle);
}

fn resolveNodeWindow(node_handle: u64) ?*Window {
    const window_handle = global_node_to_window.get(node_handle) orelse return null;
    return global_windows.get(window_handle);
}

fn resolveNode(window: *Window, node_handle: u64) ?*Node {
    return window.nodes.getPtr(node_handle);
}

fn createNode(window: *Window, kind: api.NodeKind, name: []const u8, data: []const u8, owner_document: u64) !u64 {
    const handle = next_node_handle;
    next_node_handle += 1;

    const node = Node{
        .kind = kind,
        .name = try makeOwned(name),
        .data = try makeOwned(data),
        .owner_document = owner_document,
        .parent = 0,
        .first_child = 0,
        .last_child = 0,
        .prev_sibling = 0,
        .next_sibling = 0,
        .attributes = .empty,
    };

    try window.nodes.put(c_allocator, handle, node);
    try global_node_to_window.put(c_allocator, handle, window.handle);
    return handle;
}

fn isAncestor(window: *Window, candidate_ancestor: u64, node_handle: u64) bool {
    var cursor = node_handle;
    while (cursor != 0) {
        if (cursor == candidate_ancestor) return true;
        const node = resolveNode(window, cursor) orelse return false;
        cursor = node.parent;
    }
    return false;
}

fn detachFromParent(window: *Window, child_handle: u64) api.Status {
    const child = resolveNode(window, child_handle) orelse return .invalid_handle;
    const parent_handle = child.parent;
    if (parent_handle == 0) {
        return .ok;
    }

    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;

    if (parent.first_child == child_handle) {
        parent.first_child = child.next_sibling;
    }
    if (parent.last_child == child_handle) {
        parent.last_child = child.prev_sibling;
    }

    if (child.prev_sibling != 0) {
        const prev = resolveNode(window, child.prev_sibling) orelse return .invalid_handle;
        prev.next_sibling = child.next_sibling;
    }
    if (child.next_sibling != 0) {
        const next = resolveNode(window, child.next_sibling) orelse return .invalid_handle;
        next.prev_sibling = child.prev_sibling;
    }

    child.parent = 0;
    child.prev_sibling = 0;
    child.next_sibling = 0;
    return .ok;
}

fn appendChild(window: *Window, parent_handle: u64, child_handle: u64) api.Status {
    if (parent_handle == child_handle) return .hierarchy_request;

    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    const child = resolveNode(window, child_handle) orelse return .invalid_handle;

    if (isAncestor(window, child_handle, parent_handle)) {
        return .hierarchy_request;
    }

    const detach_status = detachFromParent(window, child_handle);
    if (detach_status != .ok) return detach_status;

    child.parent = parent_handle;
    child.prev_sibling = parent.last_child;
    child.next_sibling = 0;

    if (parent.last_child == 0) {
        parent.first_child = child_handle;
        parent.last_child = child_handle;
    } else {
        const last = resolveNode(window, parent.last_child) orelse return .invalid_handle;
        last.next_sibling = child_handle;
        parent.last_child = child_handle;
    }

    return .ok;
}

fn insertBefore(window: *Window, parent_handle: u64, child_handle: u64, reference_handle: u64) api.Status {
    if (reference_handle == 0) {
        return appendChild(window, parent_handle, child_handle);
    }
    if (parent_handle == child_handle) return .hierarchy_request;

    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    const child = resolveNode(window, child_handle) orelse return .invalid_handle;
    const reference = resolveNode(window, reference_handle) orelse return .invalid_handle;

    if (reference.parent != parent_handle) {
        return .not_found;
    }

    if (isAncestor(window, child_handle, parent_handle)) {
        return .hierarchy_request;
    }

    const detach_status = detachFromParent(window, child_handle);
    if (detach_status != .ok) return detach_status;

    child.parent = parent_handle;
    child.next_sibling = reference_handle;
    child.prev_sibling = reference.prev_sibling;

    if (reference.prev_sibling != 0) {
        const prev = resolveNode(window, reference.prev_sibling) orelse return .invalid_handle;
        prev.next_sibling = child_handle;
    } else {
        parent.first_child = child_handle;
    }

    reference.prev_sibling = child_handle;

    if (parent.last_child == 0) {
        parent.last_child = child_handle;
    }

    return .ok;
}

fn removeChild(window: *Window, parent_handle: u64, child_handle: u64) api.Status {
    _ = resolveNode(window, parent_handle) orelse return .invalid_handle;
    const child = resolveNode(window, child_handle) orelse return .invalid_handle;
    if (child.parent != parent_handle) {
        return .not_found;
    }
    return detachFromParent(window, child_handle);
}

fn replaceChild(window: *Window, parent_handle: u64, new_child_handle: u64, old_child_handle: u64) api.Status {
    if (new_child_handle == old_child_handle) {
        return .ok;
    }

    const old_child = resolveNode(window, old_child_handle) orelse return .invalid_handle;
    if (old_child.parent != parent_handle) {
        return .not_found;
    }

    const insert_status = insertBefore(window, parent_handle, new_child_handle, old_child_handle);
    if (insert_status != .ok) {
        return insert_status;
    }

    return removeChild(window, parent_handle, old_child_handle);
}

fn setNodeData(node: *Node, data: []const u8) !void {
    c_allocator.free(node.data);
    node.data = try makeOwned(data);
}

fn attributeIndex(node: *Node, name: []const u8) ?usize {
    for (node.attributes.items, 0..) |attr, idx| {
        if (std.ascii.eqlIgnoreCase(attr.name, name)) {
            return idx;
        }
    }
    return null;
}

fn setAttribute(node: *Node, name: []const u8, value: []const u8) !void {
    if (attributeIndex(node, name)) |idx| {
        c_allocator.free(node.attributes.items[idx].value);
        node.attributes.items[idx].value = try makeOwned(value);
        return;
    }

    try node.attributes.append(c_allocator, .{
        .name = try makeOwnedLower(name),
        .value = try makeOwned(value),
    });
}

fn removeAttribute(node: *Node, name: []const u8) bool {
    const idx = attributeIndex(node, name) orelse return false;
    const attr = node.attributes.items[idx];
    c_allocator.free(attr.name);
    c_allocator.free(attr.value);
    _ = node.attributes.swapRemove(idx);
    return true;
}

fn getAttribute(node: *Node, name: []const u8) ?[]const u8 {
    const idx = attributeIndex(node, name) orelse return null;
    return node.attributes.items[idx].value;
}

fn appendTextContent(window: *Window, node_handle: u64, output: *std.ArrayListUnmanaged(u8)) !void {
    const node = resolveNode(window, node_handle) orelse return;

    switch (node.kind) {
        .text => try output.appendSlice(c_allocator, node.data),
        .comment => {
            if (node_handle == node.owner_document) {
                try output.appendSlice(c_allocator, node.data);
            }
        },
        else => {
            var cursor = node.first_child;
            while (cursor != 0) {
                try appendTextContent(window, cursor, output);
                const child = resolveNode(window, cursor) orelse break;
                cursor = child.next_sibling;
            }
        },
    }
}

fn clearChildren(window: *Window, node_handle: u64) api.Status {
    const node = resolveNode(window, node_handle) orelse return .invalid_handle;
    var cursor = node.first_child;
    while (cursor != 0) {
        const child = resolveNode(window, cursor) orelse return .invalid_handle;
        const next = child.next_sibling;
        child.parent = 0;
        child.prev_sibling = 0;
        child.next_sibling = 0;
        cursor = next;
    }
    node.first_child = 0;
    node.last_child = 0;
    return .ok;
}

fn escapeHtml(output: *std.ArrayListUnmanaged(u8), input: []const u8) !void {
    for (input) |ch| {
        switch (ch) {
            '&' => try output.appendSlice(c_allocator, "&amp;"),
            '<' => try output.appendSlice(c_allocator, "&lt;"),
            '>' => try output.appendSlice(c_allocator, "&gt;"),
            '"' => try output.appendSlice(c_allocator, "&quot;"),
            else => try output.append(c_allocator, ch),
        }
    }
}

fn isVoidElement(tag: []const u8) bool {
    return std.mem.eql(u8, tag, "area") or
        std.mem.eql(u8, tag, "base") or
        std.mem.eql(u8, tag, "br") or
        std.mem.eql(u8, tag, "col") or
        std.mem.eql(u8, tag, "embed") or
        std.mem.eql(u8, tag, "hr") or
        std.mem.eql(u8, tag, "img") or
        std.mem.eql(u8, tag, "input") or
        std.mem.eql(u8, tag, "link") or
        std.mem.eql(u8, tag, "meta") or
        std.mem.eql(u8, tag, "param") or
        std.mem.eql(u8, tag, "source") or
        std.mem.eql(u8, tag, "track") or
        std.mem.eql(u8, tag, "wbr");
}

fn serializeNode(window: *Window, node_handle: u64, output: *std.ArrayListUnmanaged(u8)) !void {
    const node = resolveNode(window, node_handle) orelse return;

    switch (node.kind) {
        .document, .document_fragment => {
            var cursor = node.first_child;
            while (cursor != 0) {
                try serializeNode(window, cursor, output);
                const child = resolveNode(window, cursor) orelse break;
                cursor = child.next_sibling;
            }
        },
        .text => try escapeHtml(output, node.data),
        .comment => {
            try output.appendSlice(c_allocator, "<!--");
            try output.appendSlice(c_allocator, node.data);
            try output.appendSlice(c_allocator, "-->");
        },
        .element => {
            try output.append(c_allocator, '<');
            try output.appendSlice(c_allocator, node.name);
            for (node.attributes.items) |attr| {
                try output.append(c_allocator, ' ');
                try output.appendSlice(c_allocator, attr.name);
                try output.appendSlice(c_allocator, "=\"");
                try escapeHtml(output, attr.value);
                try output.appendSlice(c_allocator, "\"");
            }
            try output.append(c_allocator, '>');

            if (!isVoidElement(node.name)) {
                var cursor = node.first_child;
                while (cursor != 0) {
                    try serializeNode(window, cursor, output);
                    const child = resolveNode(window, cursor) orelse break;
                    cursor = child.next_sibling;
                }
                try output.appendSlice(c_allocator, "</");
                try output.appendSlice(c_allocator, node.name);
                try output.append(c_allocator, '>');
            }
        },
        else => {},
    }
}

const SimpleSelector = struct {
    tag: ?[]const u8 = null,
    id: ?[]const u8 = null,
    class_name: ?[]const u8 = null,
    attr_name: ?[]const u8 = null,
    attr_value: ?[]const u8 = null,
    any: bool = false,
};

fn parseSimpleSelector(input: []const u8) SimpleSelector {
    var selector = SimpleSelector{};
    const trimmed = std.mem.trim(u8, input, " \t\n\r");
    if (trimmed.len == 0) return selector;
    if (std.mem.eql(u8, trimmed, "*")) {
        selector.any = true;
        return selector;
    }

    var i: usize = 0;
    while (i < trimmed.len and trimmed[i] != '#' and trimmed[i] != '.' and trimmed[i] != '[') {
        i += 1;
    }
    if (i > 0) selector.tag = trimmed[0..i];

    while (i < trimmed.len) {
        switch (trimmed[i]) {
            '#' => {
                i += 1;
                const start = i;
                while (i < trimmed.len and trimmed[i] != '.' and trimmed[i] != '[' and trimmed[i] != '#') {
                    i += 1;
                }
                selector.id = trimmed[start..i];
            },
            '.' => {
                i += 1;
                const start = i;
                while (i < trimmed.len and trimmed[i] != '.' and trimmed[i] != '[' and trimmed[i] != '#') {
                    i += 1;
                }
                selector.class_name = trimmed[start..i];
            },
            '[' => {
                i += 1;
                const name_start = i;
                while (i < trimmed.len and trimmed[i] != '=' and trimmed[i] != ']') {
                    i += 1;
                }
                selector.attr_name = std.mem.trim(u8, trimmed[name_start..i], " \t\n\r");
                if (i < trimmed.len and trimmed[i] == '=') {
                    i += 1;
                    const value_start = i;
                    while (i < trimmed.len and trimmed[i] != ']') {
                        i += 1;
                    }
                    const value = std.mem.trim(u8, trimmed[value_start..i], " \t\n\r\"");
                    selector.attr_value = value;
                }
                while (i < trimmed.len and trimmed[i] != ']') {
                    i += 1;
                }
                if (i < trimmed.len and trimmed[i] == ']') i += 1;
            },
            else => i += 1,
        }
    }

    return selector;
}

fn classContains(class_attr: []const u8, expected: []const u8) bool {
    var iter = std.mem.tokenizeScalar(u8, class_attr, ' ');
    while (iter.next()) |token| {
        if (std.mem.eql(u8, token, expected)) return true;
    }
    return false;
}

fn matchesSimpleSelector(window: *Window, node_handle: u64, selector: SimpleSelector) bool {
    const node = resolveNode(window, node_handle) orelse return false;
    if (node.kind != .element) return false;

    if (!selector.any) {
        if (selector.tag) |tag| {
            if (!std.ascii.eqlIgnoreCase(node.name, tag)) {
                return false;
            }
        }
    }

    if (selector.id) |expected_id| {
        const actual = getAttribute(node, "id") orelse return false;
        if (!std.mem.eql(u8, actual, expected_id)) return false;
    }

    if (selector.class_name) |expected_class| {
        const class_attr = getAttribute(node, "class") orelse return false;
        if (!classContains(class_attr, expected_class)) return false;
    }

    if (selector.attr_name) |attr_name| {
        const actual = getAttribute(node, attr_name) orelse return false;
        if (selector.attr_value) |expected_value| {
            if (!std.mem.eql(u8, actual, expected_value)) return false;
        }
    }

    return true;
}

fn matchesSelectorChain(window: *Window, node_handle: u64, selectors: []const SimpleSelector) bool {
    if (selectors.len == 0) return false;
    if (!matchesSimpleSelector(window, node_handle, selectors[selectors.len - 1])) {
        return false;
    }

    if (selectors.len == 1) return true;

    var cursor = node_handle;
    var index: usize = selectors.len - 1;

    while (index > 0) {
        index -= 1;
        const current = resolveNode(window, cursor) orelse return false;
        var parent_handle = current.parent;
        var matched = false;
        while (parent_handle != 0) {
            if (matchesSimpleSelector(window, parent_handle, selectors[index])) {
                cursor = parent_handle;
                matched = true;
                break;
            }
            const parent = resolveNode(window, parent_handle) orelse return false;
            parent_handle = parent.parent;
        }
        if (!matched) return false;
    }

    return true;
}

fn collectElements(window: *Window, root_handle: u64, selectors: []const SimpleSelector, output: *std.ArrayListUnmanaged(u64)) !void {
    const node = resolveNode(window, root_handle) orelse return;

    if (node.kind == .element and matchesSelectorChain(window, root_handle, selectors)) {
        try output.append(c_allocator, root_handle);
    }

    var cursor = node.first_child;
    while (cursor != 0) {
        try collectElements(window, cursor, selectors, output);
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.next_sibling;
    }
}

fn parseSelectorList(query: []const u8, output: *std.ArrayListUnmanaged(SimpleSelector)) !void {
    var token_iter = std.mem.tokenizeAny(u8, query, " \t\n\r");
    while (token_iter.next()) |token| {
        try output.append(c_allocator, parseSimpleSelector(token));
    }
}

fn outputString(bytes: []const u8, out_ptr: *[*c]u8, out_len: *usize) u32 {
    if (bytes.len == 0) {
        out_ptr.* = null;
        out_len.* = 0;
        return STATUS_OK;
    }

    const copy = c_allocator.alloc(u8, bytes.len) catch return STATUS_OOM;
    @memcpy(copy, bytes);
    out_ptr.* = @ptrCast(copy.ptr);
    out_len.* = bytes.len;
    return STATUS_OK;
}

fn outputHandleArray(handles: []const u64, out_ptr: *[*c]u64, out_len: *usize) u32 {
    if (handles.len == 0) {
        out_ptr.* = null;
        out_len.* = 0;
        return STATUS_OK;
    }

    const copy = c_allocator.alloc(u64, handles.len) catch return STATUS_OOM;
    @memcpy(copy, handles);
    out_ptr.* = @ptrCast(copy.ptr);
    out_len.* = handles.len;
    return STATUS_OK;
}

fn createWindowInternal(out_window: *u64) u32 {
    const window = c_allocator.create(Window) catch return STATUS_OOM;
    window.* = .{
        .handle = next_window_handle,
        .nodes = .{},
        .document_handle = 0,
        .html_handle = 0,
        .head_handle = 0,
        .body_handle = 0,
    };
    next_window_handle += 1;

    global_windows.put(c_allocator, window.handle, window) catch {
        c_allocator.destroy(window);
        return STATUS_OOM;
    };

    const document_handle = createNode(window, .document, "#document", "", 0) catch {
        _ = global_windows.remove(window.handle);
        c_allocator.destroy(window);
        return STATUS_OOM;
    };
    const html_handle = createNode(window, .element, "html", "", document_handle) catch return STATUS_OOM;
    const head_handle = createNode(window, .element, "head", "", document_handle) catch return STATUS_OOM;
    const body_handle = createNode(window, .element, "body", "", document_handle) catch return STATUS_OOM;

    window.document_handle = document_handle;
    window.html_handle = html_handle;
    window.head_handle = head_handle;
    window.body_handle = body_handle;

    const doc_node = resolveNode(window, document_handle) orelse return STATUS_INTERNAL;
    doc_node.owner_document = document_handle;

    _ = appendChild(window, document_handle, html_handle);
    _ = appendChild(window, html_handle, head_handle);
    _ = appendChild(window, html_handle, body_handle);

    out_window.* = window.handle;
    return STATUS_OK;
}

fn destroyWindowInternal(window_handle: u64) void {
    const window = resolveWindow(window_handle) orelse return;

    var iter = window.nodes.iterator();
    while (iter.next()) |entry| {
        const node_handle = entry.key_ptr.*;
        const node = entry.value_ptr;
        node.deinit();
        _ = global_node_to_window.remove(node_handle);
    }

    window.nodes.deinit(c_allocator);
    _ = global_windows.remove(window_handle);
    c_allocator.destroy(window);
}

fn toNodeType(kind: api.NodeKind) u32 {
    return switch (kind) {
        .element => 1,
        .text => 3,
        .comment => 8,
        .document => 9,
        .document_fragment => 11,
        else => 0,
    };
}

pub export fn zig_dom_version() [*:0]const u8 {
    return VERSION;
}

pub export fn zig_dom_can_return_structs() u32 {
    return 0;
}

pub export fn zig_dom_echo_utf8(data_ptr: [*]const u8, data_len: usize, out_ptr: *[*c]u8, out_len: *usize) u32 {

    const input = data_ptr[0..data_len];
    return outputString(input, out_ptr, out_len);
}

pub export fn zig_dom_create_window(out_window: *u64) u32 {
    return createWindowInternal(out_window);
}

pub export fn zig_dom_destroy_window(window: u64) void {
    destroyWindowInternal(window);
}

pub export fn zig_dom_window_document(window: u64, out_document: *u64) u32 {

    const win = resolveWindow(window) orelse return STATUS_INVALID_HANDLE;
    out_document.* = win.document_handle;
    return STATUS_OK;
}

pub export fn zig_dom_window_document_element(window: u64, out_element: *u64) u32 {

    const win = resolveWindow(window) orelse return STATUS_INVALID_HANDLE;
    out_element.* = win.html_handle;
    return STATUS_OK;
}

pub export fn zig_dom_window_head(window: u64, out_head: *u64) u32 {

    const win = resolveWindow(window) orelse return STATUS_INVALID_HANDLE;
    out_head.* = win.head_handle;
    return STATUS_OK;
}

pub export fn zig_dom_window_body(window: u64, out_body: *u64) u32 {

    const win = resolveWindow(window) orelse return STATUS_INVALID_HANDLE;
    out_body.* = win.body_handle;
    return STATUS_OK;
}

pub export fn zig_dom_node_kind(node: u64) u32 {

    const window = resolveNodeWindow(node) orelse return 0;
    const record = resolveNode(window, node) orelse return 0;
    return @intFromEnum(record.kind);
}

pub export fn zig_dom_node_type(node: u64) u32 {

    const window = resolveNodeWindow(node) orelse return 0;
    const record = resolveNode(window, node) orelse return 0;
    return toNodeType(record.kind);
}

pub export fn zig_dom_node_owner_document(node: u64, out_document: *u64) u32 {

    const window = resolveNodeWindow(node) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, node) orelse return STATUS_INVALID_HANDLE;
    out_document.* = record.owner_document;
    return STATUS_OK;
}

pub export fn zig_dom_node_parent(node: u64) u64 {

    const window = resolveNodeWindow(node) orelse return 0;
    const record = resolveNode(window, node) orelse return 0;
    return record.parent;
}

pub export fn zig_dom_node_first_child(node: u64) u64 {

    const window = resolveNodeWindow(node) orelse return 0;
    const record = resolveNode(window, node) orelse return 0;
    return record.first_child;
}

pub export fn zig_dom_node_last_child(node: u64) u64 {

    const window = resolveNodeWindow(node) orelse return 0;
    const record = resolveNode(window, node) orelse return 0;
    return record.last_child;
}

pub export fn zig_dom_node_next_sibling(node: u64) u64 {

    const window = resolveNodeWindow(node) orelse return 0;
    const record = resolveNode(window, node) orelse return 0;
    return record.next_sibling;
}

pub export fn zig_dom_node_previous_sibling(node: u64) u64 {

    const window = resolveNodeWindow(node) orelse return 0;
    const record = resolveNode(window, node) orelse return 0;
    return record.prev_sibling;
}

pub export fn zig_dom_node_name(node: u64, out_ptr: *[*c]u8, out_len: *usize) u32 {

    const window = resolveNodeWindow(node) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, node) orelse return STATUS_INVALID_HANDLE;

    return outputString(record.name, out_ptr, out_len);
}

pub export fn zig_dom_node_append_child(parent: u64, child: u64) u32 {

    const window = resolveNodeWindow(parent) orelse return STATUS_INVALID_HANDLE;
    const window_for_child = resolveNodeWindow(child) orelse return STATUS_INVALID_HANDLE;
    if (window.handle != window_for_child.handle) return STATUS_HIERARCHY;

    return @intFromEnum(appendChild(window, parent, child));
}

pub export fn zig_dom_node_insert_before(parent: u64, child: u64, reference_child: u64) u32 {

    const window = resolveNodeWindow(parent) orelse return STATUS_INVALID_HANDLE;
    const child_window = resolveNodeWindow(child) orelse return STATUS_INVALID_HANDLE;
    if (window.handle != child_window.handle) return STATUS_HIERARCHY;
    if (reference_child != 0) {
        const reference_window = resolveNodeWindow(reference_child) orelse return STATUS_INVALID_HANDLE;
        if (window.handle != reference_window.handle) return STATUS_HIERARCHY;
    }

    return @intFromEnum(insertBefore(window, parent, child, reference_child));
}

pub export fn zig_dom_node_remove_child(parent: u64, child: u64) u32 {

    const window = resolveNodeWindow(parent) orelse return STATUS_INVALID_HANDLE;
    return @intFromEnum(removeChild(window, parent, child));
}

pub export fn zig_dom_node_replace_child(parent: u64, new_child: u64, old_child: u64) u32 {

    const window = resolveNodeWindow(parent) orelse return STATUS_INVALID_HANDLE;
    const new_window = resolveNodeWindow(new_child) orelse return STATUS_INVALID_HANDLE;
    const old_window = resolveNodeWindow(old_child) orelse return STATUS_INVALID_HANDLE;
    if (window.handle != new_window.handle or window.handle != old_window.handle) return STATUS_HIERARCHY;

    return @intFromEnum(replaceChild(window, parent, new_child, old_child));
}

pub export fn zig_dom_document_create_element(document: u64, name_ptr: [*]const u8, name_len: usize, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (record.kind != .document) return STATUS_INVALID_ARGUMENT;

    const tag = name_ptr[0..name_len];
    const lower_tag = makeOwnedLower(tag) catch return STATUS_OOM;
    defer c_allocator.free(lower_tag);

    out_handle.* = createNode(window, .element, lower_tag, "", document) catch return STATUS_OOM;
    return STATUS_OK;
}

pub export fn zig_dom_document_create_text_node(document: u64, data_ptr: [*]const u8, data_len: usize, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (record.kind != .document) return STATUS_INVALID_ARGUMENT;

    out_handle.* = createNode(window, .text, "#text", data_ptr[0..data_len], document) catch return STATUS_OOM;
    return STATUS_OK;
}

pub export fn zig_dom_document_create_comment(document: u64, data_ptr: [*]const u8, data_len: usize, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (record.kind != .document) return STATUS_INVALID_ARGUMENT;

    out_handle.* = createNode(window, .comment, "#comment", data_ptr[0..data_len], document) catch return STATUS_OOM;
    return STATUS_OK;
}

pub export fn zig_dom_document_create_document_fragment(document: u64, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (record.kind != .document) return STATUS_INVALID_ARGUMENT;

    out_handle.* = createNode(window, .document_fragment, "#document-fragment", "", document) catch return STATUS_OOM;
    return STATUS_OK;
}

pub export fn zig_dom_element_get_attribute(element: u64, name_ptr: [*]const u8, name_len: usize, out_ptr: *[*c]u8, out_len: *usize, out_exists: *u8) u32 {

    const window = resolveNodeWindow(element) orelse return STATUS_INVALID_HANDLE;
    const node = resolveNode(window, element) orelse return STATUS_INVALID_HANDLE;
    if (node.kind != .element) return STATUS_INVALID_ARGUMENT;

    const name = name_ptr[0..name_len];
    const value = getAttribute(node, name);
    if (value) |existing| {
        out_exists.* = 1;
        return outputString(existing, out_ptr, out_len);
    }

    out_exists.* = 0;
    out_ptr.* = null;
    out_len.* = 0;
    return STATUS_OK;
}

pub export fn zig_dom_element_set_attribute(element: u64, name_ptr: [*]const u8, name_len: usize, value_ptr: [*]const u8, value_len: usize) u32 {

    const window = resolveNodeWindow(element) orelse return STATUS_INVALID_HANDLE;
    const node = resolveNode(window, element) orelse return STATUS_INVALID_HANDLE;
    if (node.kind != .element) return STATUS_INVALID_ARGUMENT;

    setAttribute(node, name_ptr[0..name_len], value_ptr[0..value_len]) catch return STATUS_OOM;
    return STATUS_OK;
}

pub export fn zig_dom_element_remove_attribute(element: u64, name_ptr: [*]const u8, name_len: usize) u32 {

    const window = resolveNodeWindow(element) orelse return STATUS_INVALID_HANDLE;
    const node = resolveNode(window, element) orelse return STATUS_INVALID_HANDLE;
    if (node.kind != .element) return STATUS_INVALID_ARGUMENT;

    _ = removeAttribute(node, name_ptr[0..name_len]);
    return STATUS_OK;
}

pub export fn zig_dom_element_has_attribute(element: u64, name_ptr: [*]const u8, name_len: usize) u32 {

    const window = resolveNodeWindow(element) orelse return 0;
    const node = resolveNode(window, element) orelse return 0;
    if (node.kind != .element) return 0;

    return if (getAttribute(node, name_ptr[0..name_len]) != null) 1 else 0;
}

pub export fn zig_dom_node_text_content(node: u64, out_ptr: *[*c]u8, out_len: *usize) u32 {

    const window = resolveNodeWindow(node) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, node) orelse return STATUS_INVALID_HANDLE;

    if (record.kind == .text or record.kind == .comment) {
        return outputString(record.data, out_ptr, out_len);
    }

    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(c_allocator);

    var cursor = record.first_child;
    while (cursor != 0) {
        appendTextContent(window, cursor, &buffer) catch return STATUS_OOM;
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.next_sibling;
    }

    return outputString(buffer.items, out_ptr, out_len);
}

pub export fn zig_dom_node_set_text_content(node: u64, data_ptr: [*]const u8, data_len: usize) u32 {

    const window = resolveNodeWindow(node) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, node) orelse return STATUS_INVALID_HANDLE;
    const data = data_ptr[0..data_len];

    if (record.kind == .text or record.kind == .comment) {
        setNodeData(record, data) catch return STATUS_OOM;
        return STATUS_OK;
    }

    const clear_status = clearChildren(window, node);
    if (clear_status != .ok) {
        return @intFromEnum(clear_status);
    }

    if (data.len > 0) {
        const text_handle = createNode(window, .text, "#text", data, record.owner_document) catch return STATUS_OOM;
        const append_status = appendChild(window, node, text_handle);
        if (append_status != .ok) {
            return @intFromEnum(append_status);
        }
    }

    return STATUS_OK;
}

pub export fn zig_dom_node_outer_html(node: u64, out_ptr: *[*c]u8, out_len: *usize) u32 {

    const window = resolveNodeWindow(node) orelse return STATUS_INVALID_HANDLE;
    _ = resolveNode(window, node) orelse return STATUS_INVALID_HANDLE;

    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(c_allocator);

    serializeNode(window, node, &buffer) catch return STATUS_OOM;
    return outputString(buffer.items, out_ptr, out_len);
}

pub export fn zig_dom_document_get_element_by_id(document: u64, id_ptr: [*]const u8, id_len: usize, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const doc_node = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (doc_node.kind != .document) return STATUS_INVALID_ARGUMENT;

    const expected = id_ptr[0..id_len];
    var stack: std.ArrayListUnmanaged(u64) = .empty;
    defer stack.deinit(c_allocator);

    var cursor = doc_node.first_child;
    while (cursor != 0) {
        stack.append(c_allocator, cursor) catch return STATUS_OOM;
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.next_sibling;
    }

    while (stack.items.len > 0) {
        const handle = stack.pop().?;
        const node = resolveNode(window, handle) orelse continue;
        if (node.kind == .element) {
            if (getAttribute(node, "id")) |actual| {
                if (std.mem.eql(u8, actual, expected)) {
                    out_handle.* = handle;
                    return STATUS_OK;
                }
            }
        }

        var child_cursor = node.first_child;
        while (child_cursor != 0) {
            stack.append(c_allocator, child_cursor) catch return STATUS_OOM;
            const child = resolveNode(window, child_cursor) orelse break;
            child_cursor = child.next_sibling;
        }
    }

    out_handle.* = 0;
    return STATUS_OK;
}

pub export fn zig_dom_document_query_selector(document: u64, selector_ptr: [*]const u8, selector_len: usize, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const doc_node = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (doc_node.kind != .document) return STATUS_INVALID_ARGUMENT;

    var selectors: std.ArrayListUnmanaged(SimpleSelector) = .empty;
    defer selectors.deinit(c_allocator);

    parseSelectorList(selector_ptr[0..selector_len], &selectors) catch return STATUS_OOM;
    if (selectors.items.len == 0) {
        out_handle.* = 0;
        return STATUS_OK;
    }

    var matches: std.ArrayListUnmanaged(u64) = .empty;
    defer matches.deinit(c_allocator);

    var cursor = doc_node.first_child;
    while (cursor != 0) {
        collectElements(window, cursor, selectors.items, &matches) catch return STATUS_OOM;
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.next_sibling;
    }

    out_handle.* = if (matches.items.len > 0) matches.items[0] else 0;
    return STATUS_OK;
}

pub export fn zig_dom_document_query_selector_all(document: u64, selector_ptr: [*]const u8, selector_len: usize, out_ptr: *[*c]u64, out_len: *usize) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const doc_node = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (doc_node.kind != .document) return STATUS_INVALID_ARGUMENT;

    var selectors: std.ArrayListUnmanaged(SimpleSelector) = .empty;
    defer selectors.deinit(c_allocator);

    parseSelectorList(selector_ptr[0..selector_len], &selectors) catch return STATUS_OOM;
    if (selectors.items.len == 0) {
        out_ptr.* = null;
        out_len.* = 0;
        return STATUS_OK;
    }

    var matches: std.ArrayListUnmanaged(u64) = .empty;
    defer matches.deinit(c_allocator);

    var cursor = doc_node.first_child;
    while (cursor != 0) {
        collectElements(window, cursor, selectors.items, &matches) catch return STATUS_OOM;
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.next_sibling;
    }

    return outputHandleArray(matches.items, out_ptr, out_len);
}

pub export fn zig_dom_document_reset(document: u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    if (window.document_handle != document) return STATUS_INVALID_ARGUMENT;

    _ = clearChildren(window, window.head_handle);
    _ = clearChildren(window, window.body_handle);
    return STATUS_OK;
}

pub export fn zig_dom_free_string(ptr: [*c]u8, len: usize) void {
    if (ptr == null or len == 0) return;
    const slice = @as([*]u8, @ptrCast(ptr))[0..len];
    c_allocator.free(slice);
}

pub export fn zig_dom_free_handle_array(ptr: [*c]u64, len: usize) void {
    if (ptr == null or len == 0) return;
    const slice = @as([*]u64, @ptrCast(ptr))[0..len];
    c_allocator.free(slice);
}

pub export fn zig_dom_retain_handle(handle: u64) void {
    _ = handle;
}

pub export fn zig_dom_release_handle(handle: u64) void {
    _ = handle;
}

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
        freeOwned(self.name);
        freeOwned(self.data);
        for (self.attributes.items) |attr| {
            freeOwned(attr.name);
            freeOwned(attr.value);
        }
        self.attributes.deinit(c_allocator);
    }
};

const Window = struct {
    handle: u64,
    next_node_id: u32,
    nodes: std.ArrayListUnmanaged(Node),
    document_handle: u64,
    html_handle: u64,
    head_handle: u64,
    body_handle: u64,
};

var global_windows: std.ArrayListUnmanaged(?*Window) = .empty;
var next_window_handle: u64 = 1;
var debug_windows_created: u64 = 0;
var debug_windows_destroyed: u64 = 0;
var debug_nodes_created: u64 = 0;
var debug_nodes_destroyed: u64 = 0;

fn resolveWindow(window_handle: u64) ?*Window {
    if (window_handle == 0) return null;
    const index: usize = @intCast(window_handle - 1);
    if (index >= global_windows.items.len) return null;
    return global_windows.items[index];
}

fn registerWindow(window: *Window) !void {
    const index: usize = @intCast(window.handle - 1);
    if (global_windows.items.len <= index) {
        const old_len = global_windows.items.len;
        try global_windows.resize(c_allocator, index + 1);
        var fill_index = old_len;
        while (fill_index <= index) : (fill_index += 1) {
            global_windows.items[fill_index] = null;
        }
    }
    global_windows.items[index] = window;
}

fn unregisterWindow(window_handle: u64) void {
    if (window_handle == 0) return;
    const index: usize = @intCast(window_handle - 1);
    if (index >= global_windows.items.len) return;
    global_windows.items[index] = null;
}

const STATUS_OK: u32 = @intFromEnum(api.Status.ok);
const STATUS_INVALID_HANDLE: u32 = @intFromEnum(api.Status.invalid_handle);
const STATUS_HIERARCHY: u32 = @intFromEnum(api.Status.hierarchy_request);
const STATUS_NOT_FOUND: u32 = @intFromEnum(api.Status.not_found);
const STATUS_OOM: u32 = @intFromEnum(api.Status.out_of_memory);
const STATUS_INVALID_ARGUMENT: u32 = @intFromEnum(api.Status.invalid_argument);
const STATUS_INTERNAL: u32 = @intFromEnum(api.Status.internal_error);

const DOC_POS_DISCONNECTED: u32 = 0x01;
const DOC_POS_PRECEDING: u32 = 0x02;
const DOC_POS_FOLLOWING: u32 = 0x04;
const DOC_POS_CONTAINS: u32 = 0x08;
const DOC_POS_CONTAINED_BY: u32 = 0x10;
const DOC_POS_IMPLEMENTATION_SPECIFIC: u32 = 0x20;

const VERSION = "0.1.0\x00";
const EMPTY_U8_STORAGE = [_]u8{};
const EMPTY_U8_SLICE: []u8 = @constCast(EMPTY_U8_STORAGE[0..]);

fn freeOwned(bytes: []u8) void {
    if (bytes.len == 0 and bytes.ptr == EMPTY_U8_SLICE.ptr) {
        return;
    }
    c_allocator.free(bytes);
}

fn makeOwned(bytes: []const u8) ![]u8 {
    if (bytes.len == 0) {
        return EMPTY_U8_SLICE;
    }
    return try c_allocator.dupe(u8, bytes);
}

fn makeOwnedLower(bytes: []const u8) ![]u8 {
    if (bytes.len == 0) {
        return EMPTY_U8_SLICE;
    }
    const copy = try c_allocator.dupe(u8, bytes);
    var needs_lower = false;
    for (copy) |item| {
        if (std.ascii.isUpper(item)) {
            needs_lower = true;
            break;
        }
    }
    if (needs_lower) {
        for (copy) |*item| {
            item.* = std.ascii.toLower(item.*);
        }
    }
    return copy;
}

fn encodeNodeHandle(window_handle: u64, node_id: u32) u64 {
    return (window_handle << 32) | @as(u64, node_id);
}

fn decodeNodeWindowHandle(node_handle: u64) u64 {
    return node_handle >> 32;
}

fn decodeNodeId(node_handle: u64) u32 {
    return @intCast(node_handle & 0xFFFF_FFFF);
}

fn resolveNodeWindow(node_handle: u64) ?*Window {
    const window_handle = decodeNodeWindowHandle(node_handle);
    if (window_handle == 0) return null;
    return resolveWindow(window_handle);
}

fn resolveNode(window: *Window, node_handle: u64) ?*Node {
    if (decodeNodeWindowHandle(node_handle) != window.handle) {
        return null;
    }

    const node_id = decodeNodeId(node_handle);
    if (node_id == 0) {
        return null;
    }

    const index: usize = @intCast(node_id - 1);
    if (index >= window.nodes.items.len) {
        return null;
    }

    return &window.nodes.items[index];
}

fn createNode(window: *Window, kind: api.NodeKind, name: []const u8, data: []const u8, owner_document: u64, lowercase_name: bool) !u64 {
    window.next_node_id += 1;
    const handle = encodeNodeHandle(window.handle, window.next_node_id);

    const owned_name = if (lowercase_name)
        try makeOwnedLower(name)
    else
        try makeOwned(name);

    const node = Node{
        .kind = kind,
        .name = owned_name,
        .data = try makeOwned(data),
        .owner_document = owner_document,
        .parent = 0,
        .first_child = 0,
        .last_child = 0,
        .prev_sibling = 0,
        .next_sibling = 0,
        .attributes = .empty,
    };

    try window.nodes.append(c_allocator, node);
    debug_nodes_created += 1;
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

fn appendPathToRoot(window: *Window, start: u64, output: *std.ArrayListUnmanaged(u64)) !void {
    var cursor = start;
    while (cursor != 0) {
        try output.append(c_allocator, cursor);
        const node = resolveNode(window, cursor) orelse break;
        cursor = node.parent;
    }
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

fn appendChildResolved(window: *Window, parent_handle: u64, parent: *Node, child_handle: u64, child: *Node) api.Status {
    if (parent_handle == child_handle) return .hierarchy_request;

    // Fast path: detached children cannot form cycles and do not require detach bookkeeping.
    if (child.parent == 0) {
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

fn appendChild(window: *Window, parent_handle: u64, child_handle: u64) api.Status {
    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    const child = resolveNode(window, child_handle) orelse return .invalid_handle;
    return appendChildResolved(window, parent_handle, parent, child_handle, child);
}

fn appendFragmentChildren(window: *Window, parent_handle: u64, fragment_handle: u64) api.Status {
    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    const fragment = resolveNode(window, fragment_handle) orelse return .invalid_handle;
    if (fragment.kind != .document_fragment) return .invalid_argument;

    const first_child = fragment.first_child;
    if (first_child == 0) return .ok;

    const last_child = fragment.last_child;
    var cursor = first_child;
    while (cursor != 0) {
        const child = resolveNode(window, cursor) orelse return .invalid_handle;
        child.parent = parent_handle;
        if (cursor == last_child) break;
        cursor = child.next_sibling;
    }

    if (parent.last_child == 0) {
        parent.first_child = first_child;
    } else {
        const previous_last = resolveNode(window, parent.last_child) orelse return .invalid_handle;
        previous_last.next_sibling = first_child;
        const first = resolveNode(window, first_child) orelse return .invalid_handle;
        first.prev_sibling = parent.last_child;
    }

    parent.last_child = last_child;
    fragment.first_child = 0;
    fragment.last_child = 0;
    return .ok;
}

fn clearChildrenResolved(window: *Window, parent: *Node) api.Status {
    var cursor = parent.first_child;
    while (cursor != 0) {
        const child = resolveNode(window, cursor) orelse return .invalid_handle;
        const next = child.next_sibling;
        child.parent = 0;
        child.prev_sibling = 0;
        child.next_sibling = 0;
        cursor = next;
    }
    parent.first_child = 0;
    parent.last_child = 0;
    return .ok;
}

fn replaceChildrenWithDetached(window: *Window, parent_handle: u64, handles: []const u64) api.Status {
    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    const clear_status = clearChildrenResolved(window, parent);
    if (clear_status != .ok) return clear_status;

    var previous_handle: u64 = 0;
    for (handles) |child_handle| {
        const child = resolveNode(window, child_handle) orelse return .invalid_handle;
        if (child.parent != 0) {
            const detach_status = detachFromParent(window, child_handle);
            if (detach_status != .ok) return detach_status;
        }

        child.parent = parent_handle;
        child.prev_sibling = previous_handle;
        child.next_sibling = 0;

        if (previous_handle == 0) {
            parent.first_child = child_handle;
        } else {
            const previous = resolveNode(window, previous_handle) orelse return .invalid_handle;
            previous.next_sibling = child_handle;
        }

        parent.last_child = child_handle;
        previous_handle = child_handle;
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
    freeOwned(node.data);
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
        freeOwned(node.attributes.items[idx].value);
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
    freeOwned(attr.name);
    freeOwned(attr.value);
    _ = node.attributes.swapRemove(idx);
    return true;
}

fn getAttribute(node: *Node, name: []const u8) ?[]const u8 {
    const idx = attributeIndex(node, name) orelse return null;
    return node.attributes.items[idx].value;
}

fn trimAsciiWhitespace(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, " \t\n\r\x0c");
}

fn asciiLowerSliceAlloc(input: []const u8) ![]u8 {
    const copy = try c_allocator.dupe(u8, input);
    for (copy) |*ch| {
        ch.* = std.ascii.toLower(ch.*);
    }
    return copy;
}

fn isAsciiWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0c;
}

fn decodeHtmlEntitiesAlloc(input: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, input, '&') == null) {
        return try makeOwned(input);
    }

    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(c_allocator);

    var index: usize = 0;
    while (index < input.len) {
        if (input[index] != '&') {
            try output.append(c_allocator, input[index]);
            index += 1;
            continue;
        }

        const entity_start = index + 1;
        const remaining = input[entity_start..];
        const semicolon_offset = std.mem.indexOfScalar(u8, remaining, ';') orelse {
            try output.append(c_allocator, input[index]);
            index += 1;
            continue;
        };
        const entity = remaining[0..semicolon_offset];
        const replacement: ?[]const u8 = if (std.mem.eql(u8, entity, "amp"))
            "&"
        else if (std.mem.eql(u8, entity, "lt"))
            "<"
        else if (std.mem.eql(u8, entity, "gt"))
            ">"
        else if (std.mem.eql(u8, entity, "quot"))
            "\""
        else if (std.mem.eql(u8, entity, "apos"))
            "'"
        else if (std.mem.eql(u8, entity, "nbsp"))
            "\xc2\xa0"
        else
            null;

        if (replacement) |value| {
            try output.appendSlice(c_allocator, value);
            index = entity_start + semicolon_offset + 1;
            continue;
        }

        if (entity.len > 1 and entity[0] == '#') {
            const base: u8 = if (entity.len > 2 and (entity[1] == 'x' or entity[1] == 'X')) 16 else 10;
            const digits = if (base == 16) entity[2..] else entity[1..];
            if (digits.len > 0) {
                const codepoint = std.fmt.parseInt(u21, digits, base) catch null;
                if (codepoint) |cp| {
                    var buffer: [4]u8 = undefined;
                    const encoded = std.unicode.utf8Encode(cp, &buffer) catch null;
                    if (encoded) |len| {
                        try output.appendSlice(c_allocator, buffer[0..len]);
                        index = entity_start + semicolon_offset + 1;
                        continue;
                    }
                }
            }
        }

        try output.append(c_allocator, input[index]);
        index += 1;
    }

    if (output.items.len == 0) {
        output.deinit(c_allocator);
        return EMPTY_U8_SLICE;
    }
    return try output.toOwnedSlice(c_allocator);
}

fn parseAttributesInto(node: *Node, source: []const u8) !void {
    var index: usize = 0;
    while (index < source.len) {
        while (index < source.len and isAsciiWhitespace(source[index])) : (index += 1) {}
        if (index >= source.len) break;

        const name_start = index;
        while (index < source.len and
            !isAsciiWhitespace(source[index]) and
            source[index] != '=' and
            source[index] != '/' and
            source[index] != '>') : (index += 1) {}
        if (index == name_start) {
            index += 1;
            continue;
        }
        const raw_name = source[name_start..index];

        while (index < source.len and isAsciiWhitespace(source[index])) : (index += 1) {}

        var raw_value: []const u8 = "";
        if (index < source.len and source[index] == '=') {
            index += 1;
            while (index < source.len and isAsciiWhitespace(source[index])) : (index += 1) {}

            if (index < source.len and (source[index] == '"' or source[index] == '\'')) {
                const quote = source[index];
                index += 1;
                const value_start = index;
                while (index < source.len and source[index] != quote) : (index += 1) {}
                raw_value = source[value_start..index];
                if (index < source.len) index += 1;
            } else {
                const value_start = index;
                while (index < source.len and
                    !isAsciiWhitespace(source[index]) and
                    source[index] != '"' and
                    source[index] != '\'' and
                    source[index] != '>') : (index += 1) {}
                raw_value = source[value_start..index];
            }
        }

        const decoded_value = try decodeHtmlEntitiesAlloc(raw_value);
        defer freeOwned(decoded_value);
        try setAttribute(node, raw_name, decoded_value);
    }
}

fn nativeParseHtmlInto(window: *Window, parent_handle: u64, html: []const u8) api.Status {
    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    if (parent.kind != .element and parent.kind != .document_fragment) return .invalid_argument;

    const clear_status = clearChildrenResolved(window, parent);
    if (clear_status != .ok) return clear_status;

    var stack: std.ArrayListUnmanaged(u64) = .empty;
    defer stack.deinit(c_allocator);
    stack.append(c_allocator, parent_handle) catch return .out_of_memory;

    var index: usize = 0;
    while (index < html.len) {
        if (html[index] != '<') {
            const text_start = index;
            while (index < html.len and html[index] != '<') : (index += 1) {}
            const decoded_text = decodeHtmlEntitiesAlloc(html[text_start..index]) catch return .out_of_memory;
            defer freeOwned(decoded_text);
            if (decoded_text.len > 0) {
                const text_handle = createNode(window, .text, "#text", decoded_text, parent.owner_document, false) catch return .out_of_memory;
                const current_parent = stack.items[stack.items.len - 1];
                const status = appendChild(window, current_parent, text_handle);
                if (status != .ok) return status;
            }
            continue;
        }

        if (std.mem.startsWith(u8, html[index..], "<!--")) {
            const comment_start = index + 4;
            const comment_end_offset = std.mem.indexOf(u8, html[comment_start..], "-->") orelse {
                index = html.len;
                break;
            };
            const comment = html[comment_start .. comment_start + comment_end_offset];
            const comment_handle = createNode(window, .comment, "#comment", comment, parent.owner_document, false) catch return .out_of_memory;
            const current_parent = stack.items[stack.items.len - 1];
            const status = appendChild(window, current_parent, comment_handle);
            if (status != .ok) return status;
            index = comment_start + comment_end_offset + 3;
            continue;
        }

        const tag_end_offset = std.mem.indexOfScalar(u8, html[index..], '>') orelse {
            const decoded_text = decodeHtmlEntitiesAlloc(html[index..]) catch return .out_of_memory;
            defer freeOwned(decoded_text);
            if (decoded_text.len > 0) {
                const text_handle = createNode(window, .text, "#text", decoded_text, parent.owner_document, false) catch return .out_of_memory;
                const current_parent = stack.items[stack.items.len - 1];
                const status = appendChild(window, current_parent, text_handle);
                if (status != .ok) return status;
            }
            break;
        };
        const token = html[index + 1 .. index + tag_end_offset];
        index += tag_end_offset + 1;

        const trimmed_token = trimAsciiWhitespace(token);
        if (trimmed_token.len == 0) continue;

        if (trimmed_token[0] == '/') {
            const close_name_raw = trimAsciiWhitespace(trimmed_token[1..]);
            const close_name = asciiLowerSliceAlloc(close_name_raw) catch return .out_of_memory;
            defer c_allocator.free(close_name);
            while (stack.items.len > 1) {
                const current_handle = stack.pop().?;
                const current = resolveNode(window, current_handle) orelse return .invalid_handle;
                if (std.mem.eql(u8, current.name, close_name)) break;
            }
            continue;
        }

        const self_closing = trimmed_token[trimmed_token.len - 1] == '/';
        const inner = if (self_closing) trimAsciiWhitespace(trimmed_token[0 .. trimmed_token.len - 1]) else trimmed_token;
        if (inner.len == 0) continue;

        var name_end: usize = 0;
        while (name_end < inner.len and !isAsciiWhitespace(inner[name_end])) : (name_end += 1) {}
        const raw_tag_name = inner[0..name_end];
        const tag_name = asciiLowerSliceAlloc(raw_tag_name) catch return .out_of_memory;
        defer c_allocator.free(tag_name);
        const attr_source = if (name_end < inner.len) inner[name_end + 1 ..] else "";

        const element_handle = createNode(window, .element, tag_name, "", parent.owner_document, false) catch return .out_of_memory;
        const element = resolveNode(window, element_handle) orelse return .invalid_handle;
        parseAttributesInto(element, attr_source) catch return .out_of_memory;

        const current_parent = stack.items[stack.items.len - 1];
        const append_status = appendChild(window, current_parent, element_handle);
        if (append_status != .ok) return append_status;

        if (!self_closing and !isVoidElement(tag_name)) {
            stack.append(c_allocator, element_handle) catch return .out_of_memory;
        }
    }

    return .ok;
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

fn appendJsonEscaped(output: *std.ArrayListUnmanaged(u8), input: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (input) |ch| {
        switch (ch) {
            '"' => try output.appendSlice(c_allocator, "\\\""),
            '\\' => try output.appendSlice(c_allocator, "\\\\"),
            '\n' => try output.appendSlice(c_allocator, "\\n"),
            '\r' => try output.appendSlice(c_allocator, "\\r"),
            '\t' => try output.appendSlice(c_allocator, "\\t"),
            else => {
                if (ch < 0x20) {
                    try output.appendSlice(c_allocator, "\\u00");
                    try output.append(c_allocator, hex[(ch >> 4) & 0x0F]);
                    try output.append(c_allocator, hex[ch & 0x0F]);
                } else {
                    try output.append(c_allocator, ch);
                }
            },
        }
    }
}

fn compareDocumentPositionInternal(left: u64, right: u64) u32 {
    if (left == right) return 0;

    const left_window = resolveNodeWindow(left) orelse return DOC_POS_DISCONNECTED | DOC_POS_IMPLEMENTATION_SPECIFIC | DOC_POS_PRECEDING;
    const right_window = resolveNodeWindow(right) orelse return DOC_POS_DISCONNECTED | DOC_POS_IMPLEMENTATION_SPECIFIC | DOC_POS_PRECEDING;
    if (left_window.handle != right_window.handle) {
        return DOC_POS_DISCONNECTED | DOC_POS_IMPLEMENTATION_SPECIFIC | DOC_POS_PRECEDING;
    }

    if (isAncestor(left_window, left, right)) {
        return DOC_POS_CONTAINS | DOC_POS_PRECEDING;
    }
    if (isAncestor(left_window, right, left)) {
        return DOC_POS_CONTAINED_BY | DOC_POS_FOLLOWING;
    }

    var left_path: std.ArrayListUnmanaged(u64) = .empty;
    defer left_path.deinit(c_allocator);
    appendPathToRoot(left_window, left, &left_path) catch return DOC_POS_IMPLEMENTATION_SPECIFIC;

    var right_path: std.ArrayListUnmanaged(u64) = .empty;
    defer right_path.deinit(c_allocator);
    appendPathToRoot(left_window, right, &right_path) catch return DOC_POS_IMPLEMENTATION_SPECIFIC;

    var left_index = left_path.items.len;
    var right_index = right_path.items.len;
    while (
        left_index > 0 and
        right_index > 0 and
        left_path.items[left_index - 1] == right_path.items[right_index - 1]
    ) {
        left_index -= 1;
        right_index -= 1;
    }

    if (left_index == 0 or right_index == 0 or left_index >= left_path.items.len) {
        return DOC_POS_IMPLEMENTATION_SPECIFIC;
    }

    const common_parent_handle = left_path.items[left_index];
    const left_branch = left_path.items[left_index - 1];
    const right_branch = right_path.items[right_index - 1];

    const common_parent = resolveNode(left_window, common_parent_handle) orelse return DOC_POS_IMPLEMENTATION_SPECIFIC;
    var cursor = common_parent.first_child;
    while (cursor != 0) {
        if (cursor == left_branch) {
            return DOC_POS_FOLLOWING;
        }
        if (cursor == right_branch) {
            return DOC_POS_PRECEDING;
        }

        const child = resolveNode(left_window, cursor) orelse break;
        cursor = child.next_sibling;
    }

    return DOC_POS_IMPLEMENTATION_SPECIFIC;
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
    const trimmed = std.mem.trim(u8, input, " \t\n\r\x0c");
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
                selector.attr_name = std.mem.trim(u8, trimmed[name_start..i], " \t\n\r\x0c");
                if (i < trimmed.len and trimmed[i] == '=') {
                    i += 1;
                    const value_start = i;
                    while (i < trimmed.len and trimmed[i] != ']') {
                        i += 1;
                    }
                    const value = std.mem.trim(u8, trimmed[value_start..i], " \t\n\r\x0c\"");
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
    var iter = std.mem.tokenizeAny(u8, class_attr, " \t\n\r\x0c");
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

fn collectDescendantElements(window: *Window, root_handle: u64, selectors: []const SimpleSelector, output: *std.ArrayListUnmanaged(u64)) !void {
    const root = resolveNode(window, root_handle) orelse return;
    var cursor = root.first_child;
    while (cursor != 0) {
        try collectElements(window, cursor, selectors, output);
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.next_sibling;
    }
}

fn findFirstElement(window: *Window, root_handle: u64, selectors: []const SimpleSelector) ?u64 {
    const node = resolveNode(window, root_handle) orelse return null;

    if (node.kind == .element and matchesSelectorChain(window, root_handle, selectors)) {
        return root_handle;
    }

    var cursor = node.first_child;
    while (cursor != 0) {
        if (findFirstElement(window, cursor, selectors)) |match| {
            return match;
        }
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.next_sibling;
    }

    return null;
}

fn findFirstDescendantElement(window: *Window, root_handle: u64, selectors: []const SimpleSelector) ?u64 {
    const root = resolveNode(window, root_handle) orelse return null;
    var cursor = root.first_child;
    while (cursor != 0) {
        if (findFirstElement(window, cursor, selectors)) |match| {
            return match;
        }
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.next_sibling;
    }

    return null;
}

fn parseSelectorList(query: []const u8, output: *std.ArrayListUnmanaged(SimpleSelector)) !void {
    var token_iter = std.mem.tokenizeAny(u8, query, " \t\n\r\x0c");
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
        .next_node_id = 0,
        .nodes = .empty,
        .document_handle = 0,
        .html_handle = 0,
        .head_handle = 0,
        .body_handle = 0,
    };
    next_window_handle += 1;
    debug_windows_created += 1;

    registerWindow(window) catch {
        c_allocator.destroy(window);
        return STATUS_OOM;
    };

    const document_handle = createNode(window, .document, "#document", "", 0, false) catch {
        unregisterWindow(window.handle);
        c_allocator.destroy(window);
        return STATUS_OOM;
    };
    const html_handle = createNode(window, .element, "html", "", document_handle, false) catch return STATUS_OOM;
    const head_handle = createNode(window, .element, "head", "", document_handle, false) catch return STATUS_OOM;
    const body_handle = createNode(window, .element, "body", "", document_handle, false) catch return STATUS_OOM;

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

    for (window.nodes.items) |*node| {
        node.deinit();
        debug_nodes_destroyed += 1;
    }

    window.nodes.deinit(c_allocator);
    unregisterWindow(window_handle);
    c_allocator.destroy(window);
    debug_windows_destroyed += 1;
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

pub export fn zig_dom_node_child_handles(node: u64, out_ptr: *[*c]u64, out_len: *usize) u32 {

    const window = resolveNodeWindow(node) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, node) orelse return STATUS_INVALID_HANDLE;

    var handles: std.ArrayListUnmanaged(u64) = .empty;
    defer handles.deinit(c_allocator);

    var cursor = record.first_child;
    while (cursor != 0) {
        handles.append(c_allocator, cursor) catch return STATUS_OOM;
        const child = resolveNode(window, cursor) orelse return STATUS_INVALID_HANDLE;
        cursor = child.next_sibling;
    }

    return outputHandleArray(handles.items, out_ptr, out_len);
}

pub export fn zig_dom_node_contains(ancestor: u64, node: u64) u32 {

    const window = resolveNodeWindow(ancestor) orelse return 0;
    const other_window = resolveNodeWindow(node) orelse return 0;
    if (window.handle != other_window.handle) return 0;
    return if (isAncestor(window, ancestor, node)) 1 else 0;
}

pub export fn zig_dom_node_compare_document_position(left: u64, right: u64) u32 {
    return compareDocumentPositionInternal(left, right);
}

pub export fn zig_dom_node_name(node: u64, out_ptr: *[*c]u8, out_len: *usize) u32 {

    const window = resolveNodeWindow(node) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, node) orelse return STATUS_INVALID_HANDLE;

    return outputString(record.name, out_ptr, out_len);
}

pub export fn zig_dom_node_append_child(parent: u64, child: u64) u32 {

    const window_handle = decodeNodeWindowHandle(parent);
    if (window_handle == 0) return STATUS_INVALID_HANDLE;
    if (decodeNodeWindowHandle(child) != window_handle) return STATUS_HIERARCHY;

    const window = resolveWindow(window_handle) orelse return STATUS_INVALID_HANDLE;
    return @intFromEnum(appendChild(window, parent, child));
}

pub export fn zig_dom_node_append_fragment(parent: u64, fragment: u64) u32 {

    const window_handle = decodeNodeWindowHandle(parent);
    if (window_handle == 0) return STATUS_INVALID_HANDLE;
    if (decodeNodeWindowHandle(fragment) != window_handle) return STATUS_HIERARCHY;

    const window = resolveWindow(window_handle) orelse return STATUS_INVALID_HANDLE;
    return @intFromEnum(appendFragmentChildren(window, parent, fragment));
}

pub export fn zig_dom_node_replace_children(parent: u64, children_ptr: [*]const u64, children_len: usize) u32 {

    const window_handle = decodeNodeWindowHandle(parent);
    if (window_handle == 0) return STATUS_INVALID_HANDLE;
    const window = resolveWindow(window_handle) orelse return STATUS_INVALID_HANDLE;

    const children = children_ptr[0..children_len];
    for (children) |child| {
        if (decodeNodeWindowHandle(child) != window_handle) return STATUS_HIERARCHY;
    }

    return @intFromEnum(replaceChildrenWithDetached(window, parent, children));
}

pub export fn zig_dom_node_set_inner_html(parent: u64, html_ptr: [*]const u8, html_len: usize) u32 {

    const window = resolveNodeWindow(parent) orelse return STATUS_INVALID_HANDLE;
    return @intFromEnum(nativeParseHtmlInto(window, parent, html_ptr[0..html_len]));
}

pub export fn zig_dom_window_append_child(window: u64, parent: u64, child: u64) u32 {

    const win = resolveWindow(window) orelse return STATUS_INVALID_HANDLE;
    if (decodeNodeWindowHandle(parent) != 0 and decodeNodeWindowHandle(parent) != win.handle) return STATUS_HIERARCHY;
    if (decodeNodeWindowHandle(child) != 0 and decodeNodeWindowHandle(child) != win.handle) return STATUS_HIERARCHY;
    const parent_node = resolveNode(win, parent) orelse return STATUS_INVALID_HANDLE;
    const child_node = resolveNode(win, child) orelse return STATUS_INVALID_HANDLE;
    return @intFromEnum(appendChildResolved(win, parent, parent_node, child, child_node));
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

    out_handle.* = createNode(window, .element, name_ptr[0..name_len], "", document, false) catch return STATUS_OOM;
    return STATUS_OK;
}

pub export fn zig_dom_document_create_div_element(document: u64) u64 {

    const window = resolveNodeWindow(document) orelse return 0;

    return createNode(window, .element, "div", "", document, false) catch 0;
}

pub export fn zig_dom_document_create_text_node(document: u64, data_ptr: [*]const u8, data_len: usize, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (record.kind != .document) return STATUS_INVALID_ARGUMENT;

    out_handle.* = createNode(window, .text, "#text", data_ptr[0..data_len], document, false) catch return STATUS_OOM;
    return STATUS_OK;
}

pub export fn zig_dom_document_create_text_node_direct(document: u64, data_ptr: [*]const u8, data_len: usize) u64 {

    const window = resolveNodeWindow(document) orelse return 0;
    const record = resolveNode(window, document) orelse return 0;
    if (record.kind != .document) return 0;

    return createNode(window, .text, "#text", data_ptr[0..data_len], document, false) catch 0;
}

pub export fn zig_dom_document_create_comment(document: u64, data_ptr: [*]const u8, data_len: usize, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (record.kind != .document) return STATUS_INVALID_ARGUMENT;

    out_handle.* = createNode(window, .comment, "#comment", data_ptr[0..data_len], document, false) catch return STATUS_OOM;
    return STATUS_OK;
}

pub export fn zig_dom_document_create_document_fragment(document: u64, out_handle: *u64) u32 {

    const window = resolveNodeWindow(document) orelse return STATUS_INVALID_HANDLE;
    const record = resolveNode(window, document) orelse return STATUS_INVALID_HANDLE;
    if (record.kind != .document) return STATUS_INVALID_ARGUMENT;

    out_handle.* = createNode(window, .document_fragment, "#document-fragment", "", document, false) catch return STATUS_OOM;
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

pub export fn zig_dom_element_get_attribute_ref(element: u64, name_ptr: [*]const u8, name_len: usize, out_ptr: *[*c]u8, out_len: *usize, out_exists: *u8) u32 {

    const window = resolveNodeWindow(element) orelse return STATUS_INVALID_HANDLE;
    const node = resolveNode(window, element) orelse return STATUS_INVALID_HANDLE;
    if (node.kind != .element) return STATUS_INVALID_ARGUMENT;

    const name = name_ptr[0..name_len];
    const value = getAttribute(node, name);
    if (value) |existing| {
        out_exists.* = 1;
        if (existing.len == 0) {
            out_ptr.* = null;
            out_len.* = 0;
            return STATUS_OK;
        }
        out_ptr.* = @ptrCast(@constCast(existing.ptr));
        out_len.* = existing.len;
        return STATUS_OK;
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

pub export fn zig_dom_element_attributes_json(element: u64, out_ptr: *[*c]u8, out_len: *usize) u32 {

    const window = resolveNodeWindow(element) orelse return STATUS_INVALID_HANDLE;
    const node = resolveNode(window, element) orelse return STATUS_INVALID_HANDLE;
    if (node.kind != .element) return STATUS_INVALID_ARGUMENT;

    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(c_allocator);

    buffer.append(c_allocator, '[') catch return STATUS_OOM;
    for (node.attributes.items, 0..) |attr, index| {
        if (index > 0) {
            buffer.append(c_allocator, ',') catch return STATUS_OOM;
        }
        buffer.appendSlice(c_allocator, "{\"name\":\"") catch return STATUS_OOM;
        appendJsonEscaped(&buffer, attr.name) catch return STATUS_OOM;
        buffer.appendSlice(c_allocator, "\",\"value\":\"") catch return STATUS_OOM;
        appendJsonEscaped(&buffer, attr.value) catch return STATUS_OOM;
        buffer.appendSlice(c_allocator, "\"}") catch return STATUS_OOM;
    }
    buffer.append(c_allocator, ']') catch return STATUS_OOM;

    return outputString(buffer.items, out_ptr, out_len);
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
        const text_handle = createNode(window, .text, "#text", data, record.owner_document, false) catch return STATUS_OOM;
        const append_status = appendChild(window, node, text_handle);
        if (append_status != .ok) {
            return @intFromEnum(append_status);
        }
    }

    return STATUS_OK;
}

pub export fn zig_dom_character_data_set_data_direct(node: u64, data_ptr: [*]const u8, data_len: usize) void {

    const window = resolveNodeWindow(node) orelse return;
    const record = resolveNode(window, node) orelse return;
    switch (record.kind) {
        .text, .comment => setNodeData(record, data_ptr[0..data_len]) catch return,
        else => return,
    }
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

    out_handle.* = findFirstDescendantElement(window, document, selectors.items) orelse 0;
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

pub export fn zig_dom_node_query_selector_all(root: u64, selector_ptr: [*]const u8, selector_len: usize, out_ptr: *[*c]u64, out_len: *usize) u32 {

    const window = resolveNodeWindow(root) orelse return STATUS_INVALID_HANDLE;
    const root_node = resolveNode(window, root) orelse return STATUS_INVALID_HANDLE;
    if (root_node.kind != .element and root_node.kind != .document_fragment and root_node.kind != .document) {
        return STATUS_INVALID_ARGUMENT;
    }

    var selectors: std.ArrayListUnmanaged(SimpleSelector) = .empty;
    defer selectors.deinit(c_allocator);
    parseSelectorList(selector_ptr[0..selector_len], &selectors) catch return STATUS_OOM;

    var matches: std.ArrayListUnmanaged(u64) = .empty;
    defer matches.deinit(c_allocator);
    collectDescendantElements(window, root, selectors.items, &matches) catch return STATUS_OOM;

    return outputHandleArray(matches.items, out_ptr, out_len);
}

pub export fn zig_dom_node_query_selector(root: u64, selector_ptr: [*]const u8, selector_len: usize, out_handle: *u64) u32 {

    const window = resolveNodeWindow(root) orelse return STATUS_INVALID_HANDLE;
    const root_node = resolveNode(window, root) orelse return STATUS_INVALID_HANDLE;
    if (root_node.kind != .element and root_node.kind != .document_fragment and root_node.kind != .document) {
        return STATUS_INVALID_ARGUMENT;
    }

    var selectors: std.ArrayListUnmanaged(SimpleSelector) = .empty;
    defer selectors.deinit(c_allocator);
    parseSelectorList(selector_ptr[0..selector_len], &selectors) catch return STATUS_OOM;

    out_handle.* = findFirstDescendantElement(window, root, selectors.items) orelse 0;
    return STATUS_OK;
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

pub export fn zig_dom_debug_reset_counters() void {
    debug_windows_created = 0;
    debug_windows_destroyed = 0;
    debug_nodes_created = 0;
    debug_nodes_destroyed = 0;
}

pub export fn zig_dom_debug_get_counters(out_windows_created: *u64, out_windows_destroyed: *u64, out_nodes_created: *u64, out_nodes_destroyed: *u64) u32 {
    out_windows_created.* = debug_windows_created;
    out_windows_destroyed.* = debug_windows_destroyed;
    out_nodes_created.* = debug_nodes_created;
    out_nodes_destroyed.* = debug_nodes_destroyed;
    return STATUS_OK;
}

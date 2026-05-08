const std = @import("std");

const Status = enum(u32) {
    ok = 0,
    invalid_handle = 1,
    hierarchy_request = 2,
    not_found = 3,
    out_of_memory = 4,
    invalid_argument = 5,
    internal_error = 6,
};

const NodeKind = enum(u32) {
    unknown = 0,
    element = 1,
    text = 3,
    comment = 8,
    document = 9,
    document_fragment = 11,
};

const Allocator = std.mem.Allocator;
const c_allocator = std.heap.c_allocator;

const Attribute = struct {
    name: []u8,
    value: []u8,
};

const Node = struct {
    kind: NodeKind,
    name: []u8,
    data: []u8,
    namespace_uri: []u8,
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
        freeOwned(self.namespace_uri);
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

const STATUS_OK: u32 = @intFromEnum(Status.ok);
const STATUS_INVALID_HANDLE: u32 = @intFromEnum(Status.invalid_handle);
const STATUS_HIERARCHY: u32 = @intFromEnum(Status.hierarchy_request);
const STATUS_NOT_FOUND: u32 = @intFromEnum(Status.not_found);
const STATUS_OOM: u32 = @intFromEnum(Status.out_of_memory);
const STATUS_INVALID_ARGUMENT: u32 = @intFromEnum(Status.invalid_argument);
const STATUS_INTERNAL: u32 = @intFromEnum(Status.internal_error);

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

fn createNode(window: *Window, kind: NodeKind, name: []const u8, data: []const u8, owner_document: u64, lowercase_name: bool) !u64 {
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
        .namespace_uri = EMPTY_U8_SLICE,
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

fn detachFromParent(window: *Window, child_handle: u64) Status {
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

fn appendChildResolved(window: *Window, parent_handle: u64, parent: *Node, child_handle: u64, child: *Node) Status {
    if (parent_handle == child_handle) return .hierarchy_request;
    if (parent.kind == .text or parent.kind == .comment) return .hierarchy_request;

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

fn appendChild(window: *Window, parent_handle: u64, child_handle: u64) Status {
    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    const child = resolveNode(window, child_handle) orelse return .invalid_handle;
    return appendChildResolved(window, parent_handle, parent, child_handle, child);
}

fn appendFragmentChildren(window: *Window, parent_handle: u64, fragment_handle: u64) Status {
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

fn clearChildrenResolved(window: *Window, parent: *Node) Status {
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

fn replaceChildrenWithDetached(window: *Window, parent_handle: u64, handles: []const u64) Status {
    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    if (parent.kind == .text or parent.kind == .comment) return .hierarchy_request;
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

fn insertBefore(window: *Window, parent_handle: u64, child_handle: u64, reference_handle: u64) Status {
    if (reference_handle == 0) {
        return appendChild(window, parent_handle, child_handle);
    }
    if (parent_handle == child_handle) return .hierarchy_request;

    const parent = resolveNode(window, parent_handle) orelse return .invalid_handle;
    if (parent.kind == .text or parent.kind == .comment) return .hierarchy_request;
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

fn removeChild(window: *Window, parent_handle: u64, child_handle: u64) Status {
    _ = resolveNode(window, parent_handle) orelse return .invalid_handle;
    const child = resolveNode(window, child_handle) orelse return .invalid_handle;
    if (child.parent != parent_handle) {
        return .not_found;
    }
    return detachFromParent(window, child_handle);
}

fn replaceChild(window: *Window, parent_handle: u64, new_child_handle: u64, old_child_handle: u64) Status {
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
        const matches = if (namespaceUsesCaseSensitiveAttributes(node))
            std.mem.eql(u8, attr.name, name)
        else
            std.ascii.eqlIgnoreCase(attr.name, name);
        if (matches) {
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
        .name = if (namespaceUsesCaseSensitiveAttributes(node)) try makeOwned(name) else try makeOwnedLower(name),
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
            source[index] != '>') : (index += 1)
        {}
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
                    source[index] != '>') : (index += 1)
                {}
                raw_value = source[value_start..index];
            }
        }

        const decoded_value = try decodeHtmlEntitiesAlloc(raw_value);
        defer freeOwned(decoded_value);
        try setAttribute(node, raw_name, decoded_value);
    }
}

fn nativeParseHtmlInto(window: *Window, parent_handle: u64, html: []const u8) Status {
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

fn clearChildren(window: *Window, node_handle: u64) Status {
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
    while (left_index > 0 and
        right_index > 0 and
        left_path.items[left_index - 1] == right_path.items[right_index - 1])
    {
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

const SelectorCombinator = enum {
    descendant,
    child,
    adjacent,
    sibling,
};

const SelectorStep = struct {
    // Relation between the previous selector step and this one.
    combinator: SelectorCombinator = .descendant,
    compound: []const u8,
};

const SelectorChain = struct {
    steps: []SelectorStep,
};

const AttrOperator = enum {
    exists,
    equals,
    includes,
    dash_match,
    prefix,
    suffix,
    substring,
};

fn classContains(class_attr: []const u8, expected: []const u8) bool {
    var iter = std.mem.tokenizeAny(u8, class_attr, " \t\n\r\x0c");
    while (iter.next()) |token| {
        if (std.mem.eql(u8, token, expected)) return true;
    }
    return false;
}

fn isSelectorWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == '\x0c';
}

fn isCombinatorChar(ch: u8) bool {
    return ch == '>' or ch == '+' or ch == '~';
}

fn selectorCombinatorFromChar(ch: u8) SelectorCombinator {
    return switch (ch) {
        '>' => .child,
        '+' => .adjacent,
        '~' => .sibling,
        else => .descendant,
    };
}

fn isSelectorIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_';
}

fn consumeSelectorWhitespace(input: []const u8, cursor: *usize) bool {
    const start = cursor.*;
    while (cursor.* < input.len and isSelectorWhitespace(input[cursor.*])) {
        cursor.* += 1;
    }
    return cursor.* > start;
}

fn parseSelectorChain(group: []const u8, output: *std.ArrayListUnmanaged(SelectorStep)) !void {
    var i: usize = 0;
    var pending_combinator: ?SelectorCombinator = null;

    while (i < group.len) {
        const had_whitespace = consumeSelectorWhitespace(group, &i);
        if (i >= group.len) break;

        if (output.items.len > 0) {
            if (isCombinatorChar(group[i])) {
                pending_combinator = selectorCombinatorFromChar(group[i]);
                i += 1;
                _ = consumeSelectorWhitespace(group, &i);
            } else if (had_whitespace and pending_combinator == null) {
                pending_combinator = .descendant;
            }
        }

        const start = i;
        var bracket_depth: usize = 0;
        var paren_depth: usize = 0;
        var quote: u8 = 0;
        while (i < group.len) {
            const ch = group[i];
            if (quote != 0) {
                if (ch == quote) quote = 0;
                i += 1;
                continue;
            }
            switch (ch) {
                '\'', '"' => {
                    quote = ch;
                    i += 1;
                },
                '[' => {
                    bracket_depth += 1;
                    i += 1;
                },
                ']' => {
                    if (bracket_depth > 0) bracket_depth -= 1;
                    i += 1;
                },
                '(' => {
                    paren_depth += 1;
                    i += 1;
                },
                ')' => {
                    if (paren_depth > 0) paren_depth -= 1;
                    i += 1;
                },
                '>', '+', '~' => {
                    if (bracket_depth == 0 and paren_depth == 0) break;
                    i += 1;
                },
                ' ', '\t', '\n', '\r', '\x0c' => {
                    if (bracket_depth == 0 and paren_depth == 0) break;
                    i += 1;
                },
                else => i += 1,
            }
        }

        const compound = std.mem.trim(u8, group[start..i], " \t\n\r\x0c");
        if (compound.len == 0) continue;
        try output.append(c_allocator, .{
            .combinator = pending_combinator orelse .descendant,
            .compound = compound,
        });
        pending_combinator = null;
    }
}

fn deinitSelectorChains(chains: *std.ArrayListUnmanaged(SelectorChain)) void {
    for (chains.items) |chain| {
        c_allocator.free(chain.steps);
    }
    chains.deinit(c_allocator);
}

fn parseSelectorList(query: []const u8, output: *std.ArrayListUnmanaged(SelectorChain)) !void {
    var start: usize = 0;
    var i: usize = 0;
    var bracket_depth: usize = 0;
    var paren_depth: usize = 0;
    var quote: u8 = 0;

    while (i <= query.len) {
        const at_end = i == query.len;
        var split = at_end;

        if (!at_end) {
            const ch = query[i];
            if (quote != 0) {
                if (ch == quote) quote = 0;
            } else {
                switch (ch) {
                    '\'', '"' => quote = ch,
                    '[' => bracket_depth += 1,
                    ']' => {
                        if (bracket_depth > 0) bracket_depth -= 1;
                    },
                    '(' => paren_depth += 1,
                    ')' => {
                        if (paren_depth > 0) paren_depth -= 1;
                    },
                    ',' => {
                        if (bracket_depth == 0 and paren_depth == 0) split = true;
                    },
                    else => {},
                }
            }
        }

        if (split) {
            const group = std.mem.trim(u8, query[start..i], " \t\n\r\x0c");
            if (group.len > 0) {
                var steps: std.ArrayListUnmanaged(SelectorStep) = .empty;
                defer steps.deinit(c_allocator);
                try parseSelectorChain(group, &steps);
                if (steps.items.len > 0) {
                    const owned_steps = try c_allocator.dupe(SelectorStep, steps.items);
                    try output.append(c_allocator, .{ .steps = owned_steps });
                }
            }
            start = i + 1;
        }

        i += 1;
    }
}

fn previousElementSibling(window: *Window, node_handle: u64) u64 {
    const node = resolveNode(window, node_handle) orelse return 0;
    var cursor = node.prev_sibling;
    while (cursor != 0) {
        const candidate = resolveNode(window, cursor) orelse return 0;
        if (candidate.kind == .element) return cursor;
        cursor = candidate.prev_sibling;
    }
    return 0;
}

fn elementParent(window: *Window, node_handle: u64) u64 {
    const node = resolveNode(window, node_handle) orelse return 0;
    var cursor = node.parent;
    while (cursor != 0) {
        const candidate = resolveNode(window, cursor) orelse return 0;
        if (candidate.kind == .element) return cursor;
        cursor = candidate.parent;
    }
    return 0;
}

fn isFirstElementChild(window: *Window, node_handle: u64) bool {
    const node = resolveNode(window, node_handle) orelse return false;
    const parent = resolveNode(window, node.parent) orelse return false;
    var cursor = parent.first_child;
    while (cursor != 0) {
        const child = resolveNode(window, cursor) orelse return false;
        if (child.kind == .element) return cursor == node_handle;
        cursor = child.next_sibling;
    }
    return false;
}

fn isLastElementChild(window: *Window, node_handle: u64) bool {
    const node = resolveNode(window, node_handle) orelse return false;
    const parent = resolveNode(window, node.parent) orelse return false;
    var cursor = parent.last_child;
    while (cursor != 0) {
        const child = resolveNode(window, cursor) orelse return false;
        if (child.kind == .element) return cursor == node_handle;
        cursor = child.prev_sibling;
    }
    return false;
}

fn elementChildIndex(window: *Window, node_handle: u64) ?usize {
    const node = resolveNode(window, node_handle) orelse return null;
    const parent = resolveNode(window, node.parent) orelse return null;
    var cursor = parent.first_child;
    var index: usize = 0;
    while (cursor != 0) {
        const child = resolveNode(window, cursor) orelse return null;
        if (child.kind == .element) {
            index += 1;
            if (cursor == node_handle) return index;
        }
        cursor = child.next_sibling;
    }
    return null;
}

fn parseIdentifierEnd(input: []const u8, start: usize) usize {
    var i = start;
    while (i < input.len and isSelectorIdentChar(input[i])) {
        i += 1;
    }
    return i;
}

fn parseParenthesized(input: []const u8, open_index: usize, out_end: *usize) ?[]const u8 {
    if (open_index >= input.len or input[open_index] != '(') return null;
    var i: usize = open_index + 1;
    var depth: usize = 1;
    var quote: u8 = 0;
    const content_start = i;
    while (i < input.len) {
        const ch = input[i];
        if (quote != 0) {
            if (ch == quote) quote = 0;
            i += 1;
            continue;
        }
        switch (ch) {
            '\'', '"' => {
                quote = ch;
                i += 1;
            },
            '(' => {
                depth += 1;
                i += 1;
            },
            ')' => {
                depth -= 1;
                if (depth == 0) {
                    out_end.* = i + 1;
                    return input[content_start..i];
                }
                i += 1;
            },
            else => i += 1,
        }
    }
    return null;
}

fn containsTopLevelCombinatorOrComma(input: []const u8) bool {
    var i: usize = 0;
    var bracket_depth: usize = 0;
    var paren_depth: usize = 0;
    var quote: u8 = 0;
    while (i < input.len) : (i += 1) {
        const ch = input[i];
        if (quote != 0) {
            if (ch == quote) quote = 0;
            continue;
        }
        switch (ch) {
            '\'', '"' => quote = ch,
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            ',', '>', '+', '~' => {
                if (bracket_depth == 0 and paren_depth == 0) return true;
            },
            ' ', '\t', '\n', '\r', '\x0c' => {
                if (bracket_depth == 0 and paren_depth == 0) return true;
            },
            else => {},
        }
    }
    return false;
}

fn attributeMatches(node: *Node, name: []const u8, op: AttrOperator, expected: []const u8) bool {
    return attributeMatchesWithValueFlag(node, name, op, expected, false);
}

fn namespaceUsesCaseSensitiveAttributes(node: *Node) bool {
    return std.mem.eql(u8, node.namespace_uri, "http://www.w3.org/2000/svg") or
        std.mem.eql(u8, node.namespace_uri, "http://www.w3.org/1998/Math/MathML");
}

fn getSelectorAttribute(node: *Node, name: []const u8) ?[]u8 {
    for (node.attributes.items) |attr| {
        const name_matches = if (namespaceUsesCaseSensitiveAttributes(node))
            std.mem.eql(u8, attr.name, name)
        else
            std.ascii.eqlIgnoreCase(attr.name, name);
        if (name_matches) return attr.value;
    }
    return null;
}

fn selectorValueEql(actual: []const u8, expected: []const u8, ignore_case: bool) bool {
    return if (ignore_case) std.ascii.eqlIgnoreCase(actual, expected) else std.mem.eql(u8, actual, expected);
}

fn selectorValueStartsWith(actual: []const u8, expected: []const u8, ignore_case: bool) bool {
    if (!ignore_case) return std.mem.startsWith(u8, actual, expected);
    return expected.len <= actual.len and std.ascii.eqlIgnoreCase(actual[0..expected.len], expected);
}

fn selectorValueEndsWith(actual: []const u8, expected: []const u8, ignore_case: bool) bool {
    if (!ignore_case) return std.mem.endsWith(u8, actual, expected);
    return expected.len <= actual.len and std.ascii.eqlIgnoreCase(actual[actual.len - expected.len ..], expected);
}

fn selectorValueContains(actual: []const u8, expected: []const u8, ignore_case: bool) bool {
    if (!ignore_case) return std.mem.indexOf(u8, actual, expected) != null;
    if (expected.len == 0) return true;
    if (expected.len > actual.len) return false;
    var index: usize = 0;
    while (index + expected.len <= actual.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(actual[index .. index + expected.len], expected)) return true;
    }
    return false;
}

fn attributeMatchesWithValueFlag(node: *Node, name: []const u8, op: AttrOperator, expected: []const u8, ignore_case_value: bool) bool {
    const actual = getSelectorAttribute(node, name) orelse return false;
    return switch (op) {
        .exists => true,
        .equals => selectorValueEql(actual, expected, ignore_case_value),
        .includes => classContains(actual, expected),
        .dash_match => selectorValueEql(actual, expected, ignore_case_value) or
            (actual.len > expected.len and selectorValueStartsWith(actual, expected, ignore_case_value) and actual[expected.len] == '-'),
        .prefix => selectorValueStartsWith(actual, expected, ignore_case_value),
        .suffix => selectorValueEndsWith(actual, expected, ignore_case_value),
        .substring => selectorValueContains(actual, expected, ignore_case_value),
    };
}

fn matchesCompoundSelector(window: *Window, node_handle: u64, compound_raw: []const u8) bool {
    const node = resolveNode(window, node_handle) orelse return false;
    if (node.kind != .element) return false;
    const compound = std.mem.trim(u8, compound_raw, " \t\n\r\x0c");
    if (compound.len == 0) return false;

    var i: usize = 0;
    if (compound[i] == '*') {
        i += 1;
    } else if (isSelectorIdentChar(compound[i])) {
        const tag_end = parseIdentifierEnd(compound, i);
        if (!std.ascii.eqlIgnoreCase(node.name, compound[i..tag_end])) return false;
        i = tag_end;
    }

    while (i < compound.len) {
        const ch = compound[i];
        switch (ch) {
            '#' => {
                i += 1;
                const end = parseIdentifierEnd(compound, i);
                if (end == i) return false;
                const actual = getAttribute(node, "id") orelse return false;
                if (!std.mem.eql(u8, actual, compound[i..end])) return false;
                i = end;
            },
            '.' => {
                i += 1;
                const end = parseIdentifierEnd(compound, i);
                if (end == i) return false;
                const class_attr = getAttribute(node, "class") orelse return false;
                if (!classContains(class_attr, compound[i..end])) return false;
                i = end;
            },
            '[' => {
                var end = i + 1;
                var quote: u8 = 0;
                while (end < compound.len) : (end += 1) {
                    const attr_ch = compound[end];
                    if (quote != 0) {
                        if (attr_ch == quote) quote = 0;
                        continue;
                    }
                    if (attr_ch == '\'' or attr_ch == '"') {
                        quote = attr_ch;
                        continue;
                    }
                    if (attr_ch == ']') break;
                }
                if (end >= compound.len or compound[end] != ']') return false;

                const attr_expr = std.mem.trim(u8, compound[i + 1 .. end], " \t\n\r\x0c");
                if (attr_expr.len == 0) return false;

                var attr_i: usize = 0;
                _ = consumeSelectorWhitespace(attr_expr, &attr_i);
                const name_start = attr_i;
                while (attr_i < attr_expr.len and isSelectorIdentChar(attr_expr[attr_i])) {
                    attr_i += 1;
                }
                if (attr_i == name_start) return false;
                const attr_name = attr_expr[name_start..attr_i];

                _ = consumeSelectorWhitespace(attr_expr, &attr_i);
                var op: AttrOperator = .exists;
                var value: []const u8 = "";
                var ignore_case_value = false;
                if (attr_i < attr_expr.len) {
                    if (attr_expr[attr_i] == '=') {
                        op = .equals;
                        attr_i += 1;
                    } else if (attr_i + 1 < attr_expr.len and attr_expr[attr_i + 1] == '=') {
                        op = switch (attr_expr[attr_i]) {
                            '~' => .includes,
                            '|' => .dash_match,
                            '^' => .prefix,
                            '$' => .suffix,
                            '*' => .substring,
                            else => return false,
                        };
                        attr_i += 2;
                    } else {
                        return false;
                    }

                    _ = consumeSelectorWhitespace(attr_expr, &attr_i);
                    if (attr_i >= attr_expr.len) return false;
                    if (attr_expr[attr_i] == '\'' or attr_expr[attr_i] == '"') {
                        const quote_ch = attr_expr[attr_i];
                        attr_i += 1;
                        const value_start = attr_i;
                        while (attr_i < attr_expr.len and attr_expr[attr_i] != quote_ch) {
                            attr_i += 1;
                        }
                        if (attr_i >= attr_expr.len) return false;
                        value = attr_expr[value_start..attr_i];
                        attr_i += 1;
                    } else {
                        const value_start = attr_i;
                        while (attr_i < attr_expr.len and !isSelectorWhitespace(attr_expr[attr_i])) {
                            attr_i += 1;
                        }
                        value = attr_expr[value_start..attr_i];
                    }

                    _ = consumeSelectorWhitespace(attr_expr, &attr_i);
                    if (attr_i < attr_expr.len) {
                        const flag = attr_expr[attr_i];
                        if ((flag == 'i' or flag == 'I') and attr_i + 1 == attr_expr.len) {
                            ignore_case_value = true;
                            attr_i += 1;
                        } else if ((flag == 's' or flag == 'S') and attr_i + 1 == attr_expr.len) {
                            attr_i += 1;
                        }
                    }
                    if (attr_i != attr_expr.len) return false;
                }

                if (!attributeMatchesWithValueFlag(node, attr_name, op, value, ignore_case_value)) return false;
                i = end + 1;
            },
            ':' => {
                i += 1;
                const name_end = parseIdentifierEnd(compound, i);
                if (name_end == i) return false;
                const pseudo_name = compound[i..name_end];
                i = name_end;

                if (std.mem.eql(u8, pseudo_name, "first-child")) {
                    if (!isFirstElementChild(window, node_handle)) return false;
                } else if (std.mem.eql(u8, pseudo_name, "last-child")) {
                    if (!isLastElementChild(window, node_handle)) return false;
                } else if (std.mem.eql(u8, pseudo_name, "nth-child")) {
                    if (i >= compound.len or compound[i] != '(') return false;
                    var close_index: usize = 0;
                    const inside = parseParenthesized(compound, i, &close_index) orelse return false;
                    i = close_index;
                    const ordinal_text = std.mem.trim(u8, inside, " \t\n\r\x0c");
                    const ordinal = std.fmt.parseUnsigned(usize, ordinal_text, 10) catch return false;
                    const actual_index = elementChildIndex(window, node_handle) orelse return false;
                    if (actual_index != ordinal) return false;
                } else if (std.mem.eql(u8, pseudo_name, "not")) {
                    if (i >= compound.len or compound[i] != '(') return false;
                    var close_index: usize = 0;
                    const inside = parseParenthesized(compound, i, &close_index) orelse return false;
                    i = close_index;
                    const inner = std.mem.trim(u8, inside, " \t\n\r\x0c");
                    if (inner.len == 0 or containsTopLevelCombinatorOrComma(inner)) return false;
                    if (matchesCompoundSelector(window, node_handle, inner)) return false;
                } else {
                    return false;
                }
            },
            '*', ' ', '\t', '\n', '\r', '\x0c' => {
                // Whitespace within a compound selector is invalid for this parser.
                return false;
            },
            else => return false,
        }
    }

    return true;
}

fn matchesSelectorChain(window: *Window, node_handle: u64, steps: []const SelectorStep) bool {
    if (steps.len == 0) return false;
    if (!matchesCompoundSelector(window, node_handle, steps[steps.len - 1].compound)) {
        return false;
    }

    if (steps.len == 1) return true;

    var cursor = node_handle;
    var index: usize = steps.len - 1;

    while (index > 0) {
        const relation = steps[index].combinator;
        index -= 1;
        switch (relation) {
            .descendant => {
                var ancestor = elementParent(window, cursor);
                var matched = false;
                while (ancestor != 0) {
                    if (matchesCompoundSelector(window, ancestor, steps[index].compound)) {
                        cursor = ancestor;
                        matched = true;
                        break;
                    }
                    ancestor = elementParent(window, ancestor);
                }
                if (!matched) return false;
            },
            .child => {
                const current = resolveNode(window, cursor) orelse return false;
                const parent_handle = current.parent;
                if (parent_handle == 0) return false;
                const parent = resolveNode(window, parent_handle) orelse return false;
                if (parent.kind != .element) return false;
                if (!matchesCompoundSelector(window, parent_handle, steps[index].compound)) return false;
                cursor = parent_handle;
            },
            .adjacent => {
                const sibling = previousElementSibling(window, cursor);
                if (sibling == 0 or !matchesCompoundSelector(window, sibling, steps[index].compound)) return false;
                cursor = sibling;
            },
            .sibling => {
                var sibling = previousElementSibling(window, cursor);
                var matched = false;
                while (sibling != 0) {
                    if (matchesCompoundSelector(window, sibling, steps[index].compound)) {
                        cursor = sibling;
                        matched = true;
                        break;
                    }
                    sibling = previousElementSibling(window, sibling);
                }
                if (!matched) return false;
            },
        }
    }

    return true;
}

fn matchesAnySelectorChain(window: *Window, node_handle: u64, chains: []const SelectorChain) bool {
    for (chains) |chain| {
        if (matchesSelectorChain(window, node_handle, chain.steps)) return true;
    }
    return false;
}

fn pushChildrenReverse(window: *Window, node: *const Node, stack: *std.ArrayListUnmanaged(u64)) !void {
    var cursor = node.last_child;
    while (cursor != 0) {
        try stack.append(c_allocator, cursor);
        const child = resolveNode(window, cursor) orelse break;
        cursor = child.prev_sibling;
    }
}

fn collectElements(window: *Window, root_handle: u64, chains: []const SelectorChain, output: *std.ArrayListUnmanaged(u64)) !void {
    var stack: std.ArrayListUnmanaged(u64) = .empty;
    defer stack.deinit(c_allocator);
    try stack.append(c_allocator, root_handle);
    while (stack.items.len > 0) {
        const handle = stack.items[stack.items.len - 1];
        stack.items.len -= 1;
        const node = resolveNode(window, handle) orelse continue;
        if (node.kind == .element and matchesAnySelectorChain(window, handle, chains)) {
            try output.append(c_allocator, handle);
        }
        try pushChildrenReverse(window, node, &stack);
    }
}

fn collectDescendantElements(window: *Window, root_handle: u64, chains: []const SelectorChain, output: *std.ArrayListUnmanaged(u64)) !void {
    const root = resolveNode(window, root_handle) orelse return;
    var stack: std.ArrayListUnmanaged(u64) = .empty;
    defer stack.deinit(c_allocator);
    try pushChildrenReverse(window, root, &stack);
    while (stack.items.len > 0) {
        const handle = stack.items[stack.items.len - 1];
        stack.items.len -= 1;
        const node = resolveNode(window, handle) orelse continue;
        if (node.kind == .element and matchesAnySelectorChain(window, handle, chains)) {
            try output.append(c_allocator, handle);
        }
        try pushChildrenReverse(window, node, &stack);
    }
}

fn findFirstElement(window: *Window, root_handle: u64, chains: []const SelectorChain) ?u64 {
    var stack: std.ArrayListUnmanaged(u64) = .empty;
    defer stack.deinit(c_allocator);
    stack.append(c_allocator, root_handle) catch return null;
    while (stack.items.len > 0) {
        const handle = stack.items[stack.items.len - 1];
        stack.items.len -= 1;
        const node = resolveNode(window, handle) orelse continue;
        if (node.kind == .element and matchesAnySelectorChain(window, handle, chains)) {
            return handle;
        }
        pushChildrenReverse(window, node, &stack) catch return null;
    }
    return null;
}

fn findFirstDescendantElement(window: *Window, root_handle: u64, chains: []const SelectorChain) ?u64 {
    const root = resolveNode(window, root_handle) orelse return null;
    var stack: std.ArrayListUnmanaged(u64) = .empty;
    defer stack.deinit(c_allocator);
    pushChildrenReverse(window, root, &stack) catch return null;
    while (stack.items.len > 0) {
        const handle = stack.items[stack.items.len - 1];
        stack.items.len -= 1;
        const node = resolveNode(window, handle) orelse continue;
        if (node.kind == .element and matchesAnySelectorChain(window, handle, chains)) {
            return handle;
        }
        pushChildrenReverse(window, node, &stack) catch return null;
    }
    return null;
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

fn toNodeType(kind: NodeKind) u32 {
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

fn findDocumentElementHandle(win: *Window) u64 {
    const document = resolveNode(win, win.document_handle) orelse return 0;
    var cursor = document.first_child;
    while (cursor != 0) {
        const node = resolveNode(win, cursor) orelse break;
        if (node.kind == .element) {
            if (std.ascii.eqlIgnoreCase(node.name, "html")) return cursor;
            return cursor;
        }
        cursor = node.next_sibling;
    }
    return 0;
}

fn findNamedElementChild(win: *Window, parent_handle: u64, tag_name: []const u8) u64 {
    if (parent_handle == 0) return 0;
    const parent = resolveNode(win, parent_handle) orelse return 0;
    var cursor = parent.first_child;
    while (cursor != 0) {
        const node = resolveNode(win, cursor) orelse break;
        if (node.kind == .element and std.ascii.eqlIgnoreCase(node.name, tag_name)) {
            return cursor;
        }
        cursor = node.next_sibling;
    }
    return 0;
}

pub export fn zig_dom_window_document_element(window: u64, out_element: *u64) u32 {
    const win = resolveWindow(window) orelse return STATUS_INVALID_HANDLE;
    out_element.* = findDocumentElementHandle(win);
    return STATUS_OK;
}

pub export fn zig_dom_window_head(window: u64, out_head: *u64) u32 {
    const win = resolveWindow(window) orelse return STATUS_INVALID_HANDLE;
    const document_element = findDocumentElementHandle(win);
    out_head.* = findNamedElementChild(win, document_element, "head");
    return STATUS_OK;
}

pub export fn zig_dom_window_body(window: u64, out_body: *u64) u32 {
    const win = resolveWindow(window) orelse return STATUS_INVALID_HANDLE;
    const document_element = findDocumentElementHandle(win);
    out_body.* = findNamedElementChild(win, document_element, "body");
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

pub export fn zig_dom_element_set_namespace(element: u64, namespace_ptr: [*]const u8, namespace_len: usize) u32 {
    const window = resolveNodeWindow(element) orelse return STATUS_INVALID_HANDLE;
    const node = resolveNode(window, element) orelse return STATUS_INVALID_HANDLE;
    if (node.kind != .element) return STATUS_INVALID_ARGUMENT;
    freeOwned(node.namespace_uri);
    node.namespace_uri = makeOwned(namespace_ptr[0..namespace_len]) catch return STATUS_OOM;
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

    var selectors: std.ArrayListUnmanaged(SelectorChain) = .empty;
    defer deinitSelectorChains(&selectors);

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

    var selectors: std.ArrayListUnmanaged(SelectorChain) = .empty;
    defer deinitSelectorChains(&selectors);

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

    var selectors: std.ArrayListUnmanaged(SelectorChain) = .empty;
    defer deinitSelectorChains(&selectors);
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

    var selectors: std.ArrayListUnmanaged(SelectorChain) = .empty;
    defer deinitSelectorChains(&selectors);
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

const std = @import("std");

pub fn skipAsciiSpaces(source: []const u8, start: usize) usize {
    var cursor = start;
    while (cursor < source.len and (source[cursor] == ' ' or source[cursor] == '\t' or source[cursor] == '\r' or source[cursor] == '\n')) : (cursor += 1) {}
    return cursor;
}

pub fn findMatchingDelimiter(source: []const u8, open_index: usize, open: u8, close: u8) ?usize {
    if (open_index >= source.len or source[open_index] != open) return null;

    var cursor = open_index;
    var depth: usize = 0;
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

        if (ch == open) {
            depth += 1;
            continue;
        }
        if (ch == close) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return cursor;
        }
    }

    return null;
}

pub fn findTopLevelDelimiter(source: []const u8, start: usize, delimiter: u8) ?usize {
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
            else => {},
        }

        if (ch == delimiter and paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) {
            return cursor;
        }
    }

    return null;
}


const std = @import("std");

pub const Status = enum(u32) {
    ok = 0,
    invalid_handle = 1,
    hierarchy_request = 2,
    not_found = 3,
    out_of_memory = 4,
    invalid_argument = 5,
    internal_error = 6,
};

pub const NodeKind = enum(u32) {
    unknown = 0,
    element = 1,
    text = 3,
    comment = 8,
    document = 9,
    document_fragment = 11,
};

pub fn isOk(status: Status) bool {
    return status == .ok;
}

pub fn statusName(status: Status) []const u8 {
    return @tagName(status);
}

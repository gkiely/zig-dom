pub const ValueTag = enum {
    undefined,
    null,
    boolean,
    number,
    string,
    object,
    function,
};

pub const ValueRef = struct {
    id: u64,
    tag: ValueTag,
};

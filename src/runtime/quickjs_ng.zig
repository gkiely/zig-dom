const quickjs = @import("quickjs");

pub fn isLinked() bool {
    _ = quickjs.Runtime;
    return true;
}

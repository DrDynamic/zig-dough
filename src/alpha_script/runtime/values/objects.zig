pub const ObjectType = enum(u8) {
    string,
};

pub const ObjectHeader = struct {
    tag: ObjectType,
    is_marked: bool,
    next: ?*ObjectHeader,

    pub inline fn equals(self: ObjectHeader, other: Value) bool {
        _ = self;
        _ = other;
        return false;
    }
};

pub const ObjString = struct {
    header: ObjectHeader,
    data: []const u8,
};

const as = @import("as");
const Value = as.runtime.values.Value;

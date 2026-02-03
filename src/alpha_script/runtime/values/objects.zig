pub const ObjectType = enum(u8) {
    native_function,
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

    pub inline fn as(self: *ObjectHeader, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("header", self));
    }
};

pub const ObjString = struct {
    header: ObjectHeader,
    data: []const u8,
};

const as = @import("as");
const Value = as.runtime.values.Value;

pub const ValueType = enum(u8) {
    uninitialized,
    null,
    bool,
    integer,
    float,
    object,
};

pub const Value = struct {
    tag: ValueType,
    data: union {
        boolean: bool,
        integer: i64,
        float: f64,
        object: *ObjectHeader,
    },
};

const objects = @import("objects.zig");
pub const ObjectType = objects.ObjectType;
pub const ObjectHeader = objects.ObjectHeader;
pub const ObjString = objects.ObjString;

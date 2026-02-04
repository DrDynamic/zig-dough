pub const NativeFn = *const fn (args: []Value) Value;

pub const ObjNative = struct {
    header: ObjectHeader,
    name_id: StringId,
    function: NativeFn,
};

pub fn nativePrint(args: []Value) Value {
    for (args) |value| {
        std.io.getStdOut().writer().print("{}\n", .{value}) catch {};
    }
    return Value.makeNull();
}

const std = @import("std");
const as = @import("as");
const Value = as.runtime.values.Value;
const ObjectHeader = as.runtime.values.ObjectHeader;

const StringId = as.common.StringId;

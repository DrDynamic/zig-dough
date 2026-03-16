pub const NativeFn = *const fn (context: *ExecutionContext, args: []Value) Value;

pub const ObjNative = struct {
    header: ObjectHeader,
    name_id: StringId,
    function: NativeFn,

    pub fn deinit(self: *ObjNative, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub fn nativePrint(context: *ExecutionContext, args: []Value) Value {
    const writer = std.io.getStdOut().writer();
    for (args) |value| {
        if (value == .error_value) {
            const error_name_id = context.error_pool.getErrorNameId(value.error_value);
            const error_name = context.string_table.get(error_name_id);

            writer.print("{s}", .{error_name}) catch {};
        } else {
            writer.print("{}\n", .{value}) catch {};
        }
    }
    return Value.makeNull();
}

const std = @import("std");
const as = @import("as");
const Value = as.runtime.values.Value;
const ObjectHeader = as.runtime.values.ObjectHeader;
const ExecutionContext = as.runtime.ExecutionContext;
const StringId = as.common.StringId;

pub const NativeFn = *const fn (context: *ExecutionContext, args: []Value) Value;

pub const ObjNative = struct {
    header: ObjectHeader,
    name_id: StringId,
    function: NativeFn,

    pub fn init(name_id: StringId, function: NativeFn, garbage_collector: *GarbageCollector) *ObjNative {
        var native = garbage_collector.createObject(ObjNative, .native_function);
        native.name_id = name_id;
        native.function = function;

        return native;
    }

    pub fn deinit(self: *ObjNative, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub fn nativePrint(context: *ExecutionContext, args: []Value) Value {
    var buffer: [4096]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer).interface;
    for (args) |value| {
        if (value == .error_value) {
            const error_name_id = context.error_pool.getErrorNameId(value.error_value);
            const error_name = context.string_table.get(error_name_id);

            writer.print("{s}\n", .{error_name}) catch {};
        } else {
            writer.print("{f}\n", .{value}) catch {};
        }
    }
    return Value.makeNull();
}

const std = @import("std");

const as = @import("as");
const ExecutionContext = as.runtime.ExecutionContext;
const GarbageCollector = as.common.memory.GarbageCollector;
const ObjectHeader = as.runtime.values.ObjectHeader;
const StringId = as.common.StringId;
const Value = as.runtime.values.Value;

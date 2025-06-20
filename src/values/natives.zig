const std = @import("std");
const Value = @import("values.zig").Value;

pub fn print(arg_count: usize, args: []Value) Value {
    for (0..arg_count) |index| {
        args[index].print();
        std.debug.print("\n", .{});
    }
    return Value.makeVoid();
}

const console = @import("../util/util.zig").console;
const Value = @import("values.zig").Value;

pub fn print(arg_count: usize, args: []Value) Value {
    for (0..arg_count) |index| {
        console.println("{s}", .{args[index].toString().bytes});
    }
    return Value.makeVoid();
}

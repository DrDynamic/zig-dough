const dough = @import("dough");
const io_config = dough.config.io_config;
const Value = dough.values.Value;

pub fn print(arg_count: usize, args: []Value) Value {
    for (0..arg_count) |index| {
        io_config.print("{}\n", .{args[index]});
    }
    return Value.makeVoid();
}

const std = @import("std");
pub fn main() !void {
    const config = @import("./config.zig");

    const allocator = config.allocator;

    var file = try std.fs.cwd().openFile("test.dough", .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, config.max_file_size);
    defer allocator.free(source);

    var vm = @import("core/vm.zig").VirtualMachine.init(allocator);
    var compiler = @import("core/compiler.zig").ModuleCompiler.init(&vm, source);

    _ = try compiler.compile();
}

const std = @import("std");
pub fn main() !void {
    const config = @import("./config.zig");
    config.debug_print_code = true;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    config.allocator = gpa.allocator();
    config.dough_allocator = @import("core/memory.zig").GarbageColletingAllocator.init(config.allocator);

    const allocator = config.allocator;

    var file = try std.fs.cwd().openFile("test.dough", .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, config.MAX_FILE_SIZE);

    //    var vm = @import("core/vm.zig").VirtualMachine.init(allocator);
    var compiler = @import("core/compiler.zig").ModuleCompiler.init(source);

    var n = [_]*DoughNativeFunction{undefined};
    n[0] = try DoughNativeFunction.init("print", natives.print);

    const module = try compiler.compile(&n);

    defer allocator.free(source);

    var vm = @import("core/vm.zig").VirtualMachine{};
    try vm.init();
    std.debug.print("----------- Start Execution -------------", .{});
    try vm.execute(module);
}

const DoughNativeFunction = @import("values/objects.zig").DoughNativeFunction;
const natives = @import("values/natives.zig");

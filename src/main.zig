const config = @import("./config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    config.allocator = gpa.allocator();
    config.dough_allocator = @import("core/memory.zig").GarbageColletingAllocator.init(config.allocator);

    var argsIterator = try std.process.ArgIterator.initWithAllocator(config.allocator);
    defer argsIterator.deinit();

    // Skip executable
    _ = argsIterator.next();

    // Handle cases accordingly
    if (argsIterator.next()) |path| {
        try runFile(path);
    } else {
        std.debug.print("REPL not implemented yet!\n", .{});
    }
}

fn runFile(path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(config.allocator, config.MAX_FILE_SIZE);

    //    var vm = @import("core/vm.zig").VirtualMachine.init(allocator);
    var compiler = @import("core/compiler.zig").ModuleCompiler.init(source);

    var n = [_]*DoughNativeFunction{undefined};
    n[0] = try DoughNativeFunction.init("print", natives.print);

    const module = try compiler.compile(&n);

    defer config.allocator.free(source);

    var vm = @import("core/vm.zig").VirtualMachine{};
    try vm.init();

    try vm.execute(module);
}

const std = @import("std");
const DoughNativeFunction = @import("values/objects.zig").DoughNativeFunction;
const natives = @import("values/natives.zig");

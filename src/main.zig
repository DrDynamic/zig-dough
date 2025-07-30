pub fn main() !void {
    globals.init();
    defer globals.deinit();

    var argsIterator = try std.process.ArgIterator.initWithAllocator(globals.allocator);
    defer argsIterator.deinit();

    // Skip executable
    _ = argsIterator.next();

    // Handle cases accordingly
    if (argsIterator.next()) |path| {
        runFile(path) catch |err| {
            if (err == core.vm.InterpretError.CompileError) {
                std.process.exit(65);
            }
            if (err == core.vm.InterpretError.RuntimeError) {
                std.process.exit(70);
            }
            return err;
        };
    } else {
        std.debug.print("REPL not implemented yet!\n", .{});
    }
}

fn runFile(path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(globals.allocator, config.MAX_FILE_SIZE);

    var vm = @import("core/vm.zig").VirtualMachine{};
    try vm.init();

    var compiler = @import("core/compiler.zig").ModuleCompiler.init(&vm, source);

    var n = [_]*DoughNativeFunction{undefined};
    n[0] = try DoughNativeFunction.init("print", natives.print);

    const module = try compiler.compile(&n);

    defer globals.allocator.free(source);

    try vm.execute(module);
}

const std = @import("std");

const globals = @import("globals.zig");
const config = @import("./config.zig");
const core = @import("core/core.zig");

const DoughNativeFunction = @import("values/objects.zig").DoughNativeFunction;
const natives = @import("values/natives.zig");

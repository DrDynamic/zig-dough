pub fn main() !void {
    try globals.init();
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

    const source = try file.readToEndAllocOptions(globals.allocator, config.MAX_FILE_SIZE, null, @alignOf(u8), 0);
    defer globals.allocator.free(source);

    var n = [_]*DoughNativeFunction{undefined};
    n[0] = try DoughNativeFunction.init("print", natives.print);
    try globals.tmpObjects.append(n[0].asObject());

    const module = try globals.compiler.compile(source, &n);
    try globals.tmpObjects.append(module.asObject());

    try globals.virtual_machine.execute(module);

    _ = globals.tmpObjects.pop();
    _ = globals.tmpObjects.pop();

    //std.debug.print("--- program end ---", .{});
    //config.debug_log_gc_stats = true;

    globals.garbage_collector.collectGarbage();
}

const std = @import("std");

const globals = @import("globals.zig");
const config = @import("./config.zig");
const core = @import("core/core.zig");

const DoughNativeFunction = @import("values/objects.zig").DoughNativeFunction;
const natives = @import("values/natives.zig");

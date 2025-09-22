pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    try dough.init(gpa.allocator());
    //    dough.config.debug_dump_code = true;
    //    dough.config.debug_print_code = true;

    defer dough.deinit();

    var argsIterator = try std.process.ArgIterator.initWithAllocator(dough.allocator);
    defer argsIterator.deinit();

    // Skip executable
    _ = argsIterator.next();

    // Handle cases accordingly
    if (argsIterator.next()) |path| {
        runFile(path) catch |err| {
            if (err == dough.backend.InterpretError.CompileError) {
                std.process.exit(65);
            }
            if (err == dough.backend.InterpretError.RuntimeError) {
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

    const source = try file.readToEndAllocOptions(dough.allocator, config.MAX_FILE_SIZE, null, @alignOf(u8), 0);
    defer dough.allocator.free(source);

    var n = [_]*DoughNativeFunction{undefined};
    n[0] = DoughNativeFunction.init("print", natives.print);
    try dough.tmpObjects.append(n[0].asObject());

    const module = try dough.compiler.compile(source, &n);
    try dough.tmpObjects.append(module.asObject());

    try dough.virtual_machine.execute(module);

    _ = dough.tmpObjects.pop();
    _ = dough.tmpObjects.pop();

    //std.debug.print("--- program end ---", .{});
    //config.debug_log_gc_stats = true;

    dough.garbage_collector.collectGarbage();
}

const std = @import("std");

const dough = @import("dough");
const config = dough.config;

const DoughNativeFunction = dough.values.objects.DoughNativeFunction;
const natives = dough.values.natives;

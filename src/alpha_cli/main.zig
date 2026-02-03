pub fn main() !void {
    const allocator = std.heap.page_allocator;

    //const stdout_terminal = as.common.Terminal.init(std.io.getStdOut());
    const stderr_terminal = as.common.Terminal.init(std.io.getStdErr());

    var argsIterator = try std.process.ArgIterator.initWithAllocator(allocator);
    defer argsIterator.deinit();

    // Skip executable
    _ = argsIterator.next();

    var chunk = as.compiler.Chunk.init(allocator);

    if (argsIterator.next()) |path| {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const source = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
        defer allocator.free(source);

        const error_reporter = as.frontend.ErrorReporter.init(source, "test_string", &stderr_terminal);

        const scanner = try as.frontend.Scanner.init(source, &error_reporter);

        var ast = try as.frontend.AST.init(allocator);
        defer ast.deinit();

        var parser = as.frontend.Parser.init(
            scanner,
            &ast,
            &error_reporter,
            allocator,
        );
        try parser.parse();

        var type_pool = try as.frontend.TypePool.init(allocator);
        defer type_pool.deinit();

        var semantic_analyzer = try as.frontend.SemanticAnalyzer.init(
            allocator,
            &ast,
            &type_pool,
            &error_reporter,
        );
        defer semantic_analyzer.deinit();

        for (ast.getRoots()) |root_node_id| {
            _ = try semantic_analyzer.analyze(root_node_id);
        }
        //    try as.frontend.debug.ASTPrinter.printAST(&ast, &type_pool, &stdout_terminal);

        var compiler = as.compiler.Compiler.init(&ast, &chunk, allocator);
        try compiler.compile();

        //const disassambler = as.frontend.debug.Disassambler.init(&stdout_terminal);
        //    disassambler.disassambleChunk(&chunk, "debug");
    } else {
        stderr_terminal.print("No source file given!", .{});
    }

    var vm = as.runtime.VirtualMachine.init(allocator);
    try vm.execute(&chunk);
}

fn registerNatives(compiler: *as.compiler.Compiler, vm: *as.runtime.VirtualMachine) !void {
    const name_id = compiler.ast.string_table.add("print");

    try compiler.locals.append(.{
        .name_id = name_id,
        .depth = 0,
        .reg_slot = 0,
        .is_captured = false,
        .is_initialized = true,
    });
    compiler.next_free_reg += 1;

    const native_print = try vm.allocator.create(as.runtime.values.ObjNative);
    native_print.* = .{
        .header = .{ .tag = .native_function, .is_marked = false, .next = null },
        .name_id = name_id,
        .function = as.runtime.values.natives.nativePrint,
    };

    vm.stack[0] = as.runtime.values.Value.fromObject(native_print);
}

pub fn _main() !void {
    const allocator = std.heap.page_allocator;

    const stdout_terminal = as.common.Terminal.init(std.io.getStdOut());
    const stderr_terminal = as.common.Terminal.init(std.io.getStdErr());

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const command = commands.Command.fromArgs(args) catch |err| {
        switch (err) {
            .MissingCommand => stderr_terminal.print("no command specified", .{}),
            .MissingPathArgument => stderr_terminal.print("run command needs path argument", .{}),
        }
    };

    command.run();

    _ =
        \\ var x: i32 = 1 + 2 * 3 > 4.5;
        \\ var a = 1*2+3;
        \\ //var uninitialized;
        \\ var y: bool = true == false;
        \\ //var z = @broken.call()
        \\ /* Multi
        \\line */
        \\ // var s = "Lorem Ipsum ";
        \\ //var t = "a + 2;
        \\ var res = 9*9+9;
        \\ var res2 = 9+9*9;
        \\ return res;
        \\ return res2;
        \\ return res == res2;
        \\
    ;

    const source =
        \\ var res = 9*9+9;
        \\ var res2 = 9+9*9;
        \\ return res;
        \\ return res2;
        \\ return res == res2;
    ;

    //const stdout_terminal = as.common.Terminal.init(std.io.getStdOut());
    //const stderr_terminal = as.common.Terminal.init(std.io.getStdErr());

    const error_reporter = as.frontend.ErrorReporter.init(source, "test_string", &stderr_terminal);

    var scanner = try as.frontend.Scanner.init(source, &error_reporter);

    as.frontend.debug.TokenPrinter.printTokens(&scanner, std.io.getStdOut().writer()) catch |err| {
        std.debug.print("Error printing tokens: {}\n", .{err});
        return err;
    };
    try scanner.reset();
    std.debug.print("\n----------\n", .{});

    var ast = try as.frontend.AST.init(allocator);

    var parser = as.frontend.Parser.init(
        scanner,
        &ast,
        &error_reporter,
        allocator,
    );
    defer ast.deinit();

    parser.parse() catch {};

    var type_pool = try as.frontend.TypePool.init(allocator);
    defer type_pool.deinit();

    var semantic_analyzer = try as.frontend.SemanticAnalyzer.init(
        allocator,
        &ast,
        &type_pool,
        &error_reporter,
    );
    defer semantic_analyzer.deinit();

    for (ast.getRoots()) |root_node_id| {
        _ = try semantic_analyzer.analyze(root_node_id);
    }

    try as.frontend.debug.ASTPrinter.printAST(&ast, &type_pool, &stdout_terminal);

    var chunk = as.compiler.Chunk.init(allocator);
    var compiler = as.compiler.Compiler.init(&ast, &chunk, allocator);
    try compiler.compile();

    const disassambler = as.frontend.debug.Disassambler.init(&stdout_terminal);
    disassambler.disassambleChunk(&chunk, "debug");

    var vm = as.runtime.VirtualMachine.init(allocator);
    try vm.execute(&chunk);

    //    const Value = as.runtime.values.Value;
    //    const a: Value = Value.makeInteger(2);
    //    const b: Value = Value.makeFloat(2.1);
    //    const res = a < b; //std.math.compare(a, .eq, b);
    //
    //    std.debug.print("{d} < {d} = {s}\n", .{ a, b, if (res) "true" else "false" });
}

const std = @import("std");
const as = @import("as");
const commands = @import("./commands/commands.zig");

const EXIT_CODE_COMPILER_ERROR = 65; // EX_DATAERR
const EXIT_CODE_RUNTIME_ERROR = 70; // EX_SOFTWARE

const StartOptions = struct {
    path: ?[]const u8,
    print_tokens: bool,
    print_ast: bool,
    print_asm: bool,
    error_output: OutputType,
};

const OutputType = enum {
    pretty,
    integration_test,
};

fn makeStartOptions(iterator: *std.process.ArgIterator) !StartOptions {
    var options: StartOptions = .{
        .path = null,
        .print_tokens = false,
        .print_ast = false,
        .print_asm = false,
        .error_output = .pretty,
    };

    // Skip executable
    _ = iterator.next();

    while (iterator.next()) |arg| {
        if (arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--print-tokens")) {
                options.print_tokens = true;
            } else if (std.mem.eql(u8, arg, "--print-ast")) {
                options.print_ast = true;
            } else if (std.mem.eql(u8, arg, "--print-asm")) {
                options.print_asm = true;
            } else if (std.mem.eql(u8, arg, "--errors=test")) {
                options.error_output = .integration_test;
            } else {
                return error.UnknownOption;
            }
        } else {
            options.path = arg;
        }
    }

    return options;
}

fn getFile(path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const source = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    return source;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const stdout_terminal = as.common.Terminal.init(std.io.getStdOut());
    const stderr_terminal = as.common.Terminal.init(std.io.getStdErr());

    var argsIterator = try std.process.ArgIterator.initWithAllocator(allocator);
    defer argsIterator.deinit();

    const start_options = try makeStartOptions(&argsIterator);

    var chunk = as.compiler.Chunk.init(allocator);
    var vm = as.runtime.VirtualMachine.init(allocator);

    if (start_options.path) |path| {
        const source = try getFile(path, allocator);
        defer allocator.free(source);

        const output: as.common.reporting.ErrorOutput = switch (start_options.error_output) {
            .pretty => case: {
                var pretty_output = as.common.reporting.outputs.PrettyErrorOutput.init(&stderr_terminal);
                break :case pretty_output.output();
            },
            .integration_test => case: {
                var pretty_output = as.common.reporting.outputs.IntegrationTestErrorOutput.init(&stderr_terminal);
                break :case pretty_output.output();
            },
        };

        const error_reporter = as.common.reporting.ErrorReporter.init(output);

        const token_stream = as.frontend.TokenStream.init(path, source, error_reporter);

        var scanner = try as.frontend.Scanner.init(token_stream, &error_reporter);

        if (start_options.print_tokens) {
            try as.frontend.debug.TokenPrinter.printTokens(&scanner, stdout_terminal.writer);
            try scanner.reset();
        }

        var ast = try as.frontend.AST.init(&scanner, allocator);
        defer ast.deinit();

        var parser = as.frontend.Parser.init(
            &scanner,
            &ast,
            &error_reporter,
            allocator,
        );
        try parser.parse();

        if (!ast.is_valid) {
            std.process.exit(EXIT_CODE_COMPILER_ERROR);
        }

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

        if (!ast.is_valid) {
            std.process.exit(EXIT_CODE_COMPILER_ERROR);
        }

        if (start_options.print_ast) {
            try as.frontend.debug.ASTPrinter.printAST(&ast, &type_pool, &stdout_terminal);
        }

        var compiler = as.compiler.Compiler.init(&ast, &chunk, &error_reporter, allocator);

        try registerNatives(&ast, &compiler, &vm);
        compiler.compile() catch {
            std.process.exit(EXIT_CODE_COMPILER_ERROR);
        };

        if (start_options.print_asm) {
            const disassambler = as.frontend.debug.Disassambler.init(&stdout_terminal);
            disassambler.disassambleChunk(&chunk, "debug");
        }

        vm.execute(&chunk) catch {
            std.process.exit(EXIT_CODE_RUNTIME_ERROR);
        };
    } else {
        stderr_terminal.print("no file specified!\n", .{});
    }
}

fn registerNatives(ast: *as.frontend.AST, compiler: *as.compiler.Compiler, vm: *as.runtime.VirtualMachine) !void {
    const name_id = try ast.string_table.add("print");

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

    vm.stack[0] = as.runtime.values.Value.fromObject(&native_print.header);
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

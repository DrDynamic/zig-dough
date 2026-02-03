pub const RunCommand = struct {
    pub const Options = struct {
        script_path: []const u8,
        print_tokens: bool,
        print_ast: bool,
        print_asm: bool,
    };

    pub fn shouldRun(command_arg: []const u8) bool {
        return std.mem.eql(u8, command_arg, "run");
    }

    pub fn buildOptions(args: [][]u8) !Options {
        if (args.len < 1) {
            return error.MissingPathArgument;
        }

        var options: Options = .{
            .script_path = args[0],
            .print_ast = false,
            .print_asm = false,
        };

        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--print-tokens")) {
                options.print_tokens = true;
            } else if (std.mem.eql(u8, arg, "--print-ast")) {
                options.print_ast = true;
            } else if (std.mem.eql(u8, arg, "--print-asm")) {
                options.print_asm = true;
            }
        }

        return options;
    }

    pub fn run(options: Options) !void {
        _ = options;
        // _ =
        //     \\ var x: i32 = 1 + 2 * 3 > 4.5;
        //     \\ var a = 1*2+3;
        //     \\ //var uninitialized;
        //     \\ var y: bool = true == false;
        //     \\ //var z = @broken.call()
        //     \\ /* Multi
        //     \\line */
        //     \\ // var s = "Lorem Ipsum ";
        //     \\ //var t = "a + 2;
        //     \\ var res = 9*9+9;
        //     \\ var res2 = 9+9*9;
        //     \\ return res;
        //     \\ return res2;
        //     \\ return res == res2;
        //     \\
        // ;

        // const source =
        //     \\ var res = 9*9+9;
        //     \\ var res2 = 9+9*9;
        //     \\ return res;
        //     \\ return res2;
        //     \\ return res == res2;
        // ;

        // const stdout_terminal = as.common.Terminal.init(std.io.getStdOut());
        // const stderr_terminal = as.common.Terminal.init(std.io.getStdErr());

        // const error_reporter = as.frontend.ErrorReporter.init(source, "test_string", &stderr_terminal);

        // var scanner = try as.frontend.Scanner.init(source, &error_reporter);

        // as.frontend.debug.TokenPrinter.printTokens(&scanner, std.io.getStdOut().writer()) catch |err| {
        //     std.debug.print("Error printing tokens: {}\n", .{err});
        //     return err;
        // };
        // try scanner.reset();
        // std.debug.print("\n----------\n", .{});

        // var ast = try as.frontend.AST.init(allocator);

        // var parser = as.frontend.Parser.init(
        //     scanner,
        //     &ast,
        //     &error_reporter,
        //     allocator,
        // );
        // defer ast.deinit();

        // parser.parse() catch {};

        // var type_pool = try as.frontend.TypePool.init(allocator);
        // defer type_pool.deinit();

        // var semantic_analyzer = try as.frontend.SemanticAnalyzer.init(
        //     allocator,
        //     &ast,
        //     &type_pool,
        //     &error_reporter,
        // );
        // defer semantic_analyzer.deinit();

        // for (ast.getRoots()) |root_node_id| {
        //     _ = try semantic_analyzer.analyze(root_node_id);
        // }

        // try as.frontend.debug.ASTPrinter.printAST(&ast, &type_pool, &stdout_terminal);

        // var chunk = as.compiler.Chunk.init(allocator);
        // var compiler = as.compiler.Compiler.init(&ast, &chunk, allocator);
        // try compiler.compile();

        // const disassambler = as.frontend.debug.Disassambler.init(&stdout_terminal);
        // disassambler.disassambleChunk(&chunk, "debug");

        // var vm = as.runtime.VirtualMachine.init(allocator);
        // try vm.execute(&chunk);

        //    const Value = as.runtime.values.Value;
        //    const a: Value = Value.makeInteger(2);
        //    const b: Value = Value.makeFloat(2.1);
        //    const res = a < b; //std.math.compare(a, .eq, b);
        //
        //    std.debug.print("{d} < {d} = {s}\n", .{ a, b, if (res) "true" else "false" });

    }
};

const std = @import("std");

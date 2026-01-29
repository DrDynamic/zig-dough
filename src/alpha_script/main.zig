pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source =
        \\ var x: i32 = 1 + 2 * 3 > 4.5;
        \\ var a = 1*2+3;
        \\ //var uninitialized;
        \\ var y: bool = true == false;
        \\ //var z = @broken.call()
        \\ /* Multi
        \\line */
        \\ // var s = "Lorem Ipsum ";
        \\ //var t = "a + 2;
        \\
    ;

    const stdout_terminal = as.common.Terminal.init(std.io.getStdOut());
    const stderr_terminal = as.common.Terminal.init(std.io.getStdErr());

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
}

const std = @import("std");
const as = @import("as");

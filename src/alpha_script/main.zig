pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source =
        \\ var x: i32 = 1 + 2 * 3 > 4.5;
        \\ var y: bool = true == false;
        \\ var z = @broken.call()
        \\ /* Multi
        \\line */
        \\ var s = "Lorem Ipsum ";
        \\ var t = "a + 2;
        \\
    ;

    const terminal = as.frontend.terminal.Terminal.init(std.io.getStdErr());

    const error_reporter = as.frontend.ErrorReporter.init(source, "test_string", &terminal);

    var scanner = try as.frontend.Scanner.init(source, &error_reporter);

    as.frontend.debug.TokenPrinter.printTokens(&scanner, std.io.getStdOut().writer()) catch |err| {
        std.debug.print("Error printing tokens: {}\n", .{err});
        return err;
    };
    try scanner.reset();
    std.debug.print("\n----------\nAST\n", .{});

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

    const stdout = std.io.getStdOut().writer();
    try as.frontend.debug.ASTPrinter.printAST(&ast, &type_pool, stdout);
}

const std = @import("std");
const as = @import("as");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source = "var x: i32 = 1 + 2 * 3 > 4;var y: bool = true == false;";
    var scanner = as.frontend.Scanner.init(source);

    as.frontend.debug.TokenPrinter.printTokens(&scanner, std.io.getStdOut().writer()) catch |err| {
        std.debug.print("Error printing tokens: {}\n", .{err});
        return err;
    };
    scanner.reset();
    std.debug.print("\n----------\nAST\n", .{});

    var ast = try as.frontend.AST.init(allocator);

    var parser = as.frontend.Parser.init(scanner, &ast, allocator);
    defer ast.deinit();

    try parser.parse();

    var type_pool = try as.frontend.TypePool.init(allocator);
    defer type_pool.deinit();

    var semantic_analyzer = try as.frontend.SemanticAnalyzer.init(allocator, &ast, &type_pool);
    defer semantic_analyzer.deinit();

    for (ast.getRoots()) |root_node_id| {
        _ = try semantic_analyzer.analyze(root_node_id);
    }

    const stdout = std.io.getStdOut().writer();
    try as.frontend.debug.ASTPrinter.printAST(&ast, &type_pool, stdout);
}

const std = @import("std");
const as = @import("as");

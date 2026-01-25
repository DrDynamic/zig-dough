pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source = "var x: i32 = 1 + 2 * 3 > 4;var y: bool = true == false;";
    var scanner = as.frontend.Scanner.init(source);

    as.frontend.debug.TokenPrinter.printTokens(&scanner, std.io.getStdOut().writer()) catch |err| {
        std.debug.print("Error printing tokens: {}\n", .{err});
        return err;
    };
    scanner.reset();

    var ast = as.frontend.AST.init(allocator);

    var parser = as.frontend.Parser.init(scanner, &ast, allocator);
    defer ast.deinit();

    try parser.parse();

    const stdout = std.io.getStdOut().writer();
    try as.frontend.debug.ASTPrinter.printAST(&ast, stdout);
}

const std = @import("std");
const as = @import("as");

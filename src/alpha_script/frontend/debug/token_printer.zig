pub const TokenPrinter = struct {
    writer: std.fs.File.Writer,
    scanner: Scanner,

    pub fn printTokens(scanner: *Scanner, writer: std.fs.File.Writer) !void {
        while (scanner.previous().tag != .eof) {
            //            try TokenPrinter.printToken(scanner.previous(), scanner, writer);
            try TokenPrinter.printToken(scanner.current(), scanner, writer);
            //            try TokenPrinter.printToken(scanner.peek(), scanner, writer);
            try writer.print("\n", .{});
            scanner.advance();
        }
    }

    pub fn printToken(token: Token, scanner: *const Scanner, writer: std.fs.File.Writer) !void {
        const tagName = @tagName(token.tag);
        const lexeme = scanner.getLexeme(token);
        try writer.print("[{s}: '{s}'] ", .{ tagName, lexeme });
    }
};

const std = @import("std");
const as = @import("as");
const Scanner = as.frontend.Scanner;
const Token = as.frontend.Token;
const TokenType = as.frontend.TokenType;

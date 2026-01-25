pub const TokenPrinter = struct {
    writer: std.fs.File.Writer,
    scanner: Scanner,

    pub fn printTokens(scanner: *Scanner, writer: std.fs.File.Writer) !void {
        while (scanner.next.tag.? != .eof) {
            try TokenPrinter.printToken(scanner.current, writer);
            scanner.scanToken();
        }
    }

    pub fn printToken(token: Token, writer: std.fs.File.Writer) !void {
        try writer.print("{} \n", .{token});
    }
};

const std = @import("std");
const as = @import("as");
const Scanner = as.frontend.Scanner;
const Token = as.frontend.Token;
const TokenType = as.frontend.TokenType;

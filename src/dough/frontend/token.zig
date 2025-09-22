const std = @import("std");

pub const TokenType = enum {
    // Single-character tokens.
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    LeftBracket,
    RightBracket,
    Colon,
    Comma,
    Dot,
    Minus,
    Plus,
    QuestionMark,
    Semicolon,
    Slash,
    Star,
    VerticalLine,
    // One or two character tokens.
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    LogicalAnd,
    LogicalOr,
    // Literals.
    Identifier,
    String,
    Number,
    // Keywords.
    Const,
    Else,
    Error,
    False,
    For,
    Function,
    If,
    Null,
    Return,
    True,
    Type,
    Var,
    While,
    // Special tokens
    Synthetic,
    ScannerError,
    Eof,
};

pub const Token = struct {
    token_type: ?TokenType,
    lexeme: ?[]const u8,
    line: usize,

    pub fn format(
        self: Token,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const tagname = if (self.token_type == null) "NULL" else std.enums.tagName(TokenType, self.token_type.?);
        try writer.print("{?d: >4}: {?s} => '{?s}'", .{ self.line, tagname, self.lexeme orelse "NULL" });
    }

    pub fn debugPrint(self: Token) void {
        const tagname = if (self.token_type == null) "NULL" else std.enums.tagName(TokenType, self.token_type.?);
        std.debug.print("{?d: >4}: {?s} => '{?s}'\n", .{ self.line, tagname, self.lexeme orelse "NULL" });
    }
};

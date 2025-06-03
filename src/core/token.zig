const std = @import("std");

pub const TokenType = enum {
    // Single-character tokens.
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    LeftBracket,
    RightBracket,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,
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
    False,
    For,
    Function,
    If,
    Null,
    Return,
    True,
    Var,
    While,

    // Special tokens
    Synthetic,
    Error,
    Eof,
};

pub const Token = struct {
    type: ?TokenType,
    lexeme: ?[]const u8,
    line: usize,

    pub fn debugPrint(self: Token) void {
        std.debug.print("{d: >4}: {?s} => '{?s}'\n", .{ self.line, std.enums.tagName(TokenType, self.type), self.lexeme orelse "NULL" });
    }
};

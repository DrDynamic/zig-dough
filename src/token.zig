const std = @import("std");

pub const TokenType = enum {
    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    LEFT_BRACKET,
    RIGHT_BRACKET,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,
    // One or two character tokens.
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,
    LOGICAL_AND,
    LOGICAL_OR,
    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,
    // Keywords.
    CONST,
    ELSE,
    FALSE,
    FOR,
    FUNCTION,
    IF,
    NULL,
    RETURN,
    TRUE,
    VAR,
    WHILE,

    // Special tokens
    SYNTHETIC,
    ERROR,
    EOF,
};

pub const Token = struct {
    type: TokenType,
    lexeme: ?[]const u8,
    line: usize,

    pub fn debugPrint(self: Token) void {
        std.debug.print("{d: >4}: {?s} => '{?s}'\n", .{ self.line, std.enums.tagName(TokenType, self.type), self.lexeme orelse "NULL" });
    }
};

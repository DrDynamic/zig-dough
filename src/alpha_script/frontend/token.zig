const std = @import("std");

pub const TokenType = enum {
    // Single-character tokens.
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    colon,
    comma,
    dot,
    minus,
    plus,
    question_mark,
    semicolon,
    slash,
    star,
    vertical_line,
    // One or two character tokens.
    bang,
    bang_equal,
    equal,
    equal_equal,
    greater,
    greater_equal,
    less,
    less_equal,
    logical_and,
    logical_or,
    // Literals.
    identifier,
    string,
    number,
    // Keywords.
    const_,
    else_,
    error_,
    false_,
    for_,
    function_,
    if_,
    null_,
    return_,
    true_,
    type_,
    var_,
    while_,
    // Special tokens
    synthetic,
    scanner_error,
    eof,
};

pub const Token = struct {
    tag: ?TokenType,
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

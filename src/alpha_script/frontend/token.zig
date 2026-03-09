const std = @import("std");

pub const TokenType = enum {
    comptime_uninitialized, // when the Scanner hasn't scanned a value yet
    comptime_corrupt, // when the TokenStream finds chars it con not parse into a valid token (for error reporting)

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
    pipe,
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
    string_double_quote,
    number,

    // Keywords.
    const_,
    else_,
    error_,
    for_,
    function,
    if_,
    return_,
    type,
    var_,
    while_,
    // types
    Anyerror,
    Bool,
    Float,
    Int,
    Null,
    String,
    Void,
    // values
    false,
    null,
    true,

    // Special tokens
    synthetic,
    eof,
};

pub const Token = struct {
    tag: TokenType,
    location: struct {
        start: usize,
        end: usize,
    },
};

const std = @import("std");

pub const TokenType = enum {
    comptime_uninitialized, // when the scanner hasn't scanned a value yet
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
    eof,
};

pub const Token = struct {
    tag: TokenType,
    location: struct {
        start: usize,
        end: usize,
    },
};

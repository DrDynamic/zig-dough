const std = @import("std");

pub const TokenType = enum {
    t_comptime_uninitialized, // when the Scanner hasn't scanned a value yet
    t_comptime_corrupt, // when the TokenStream finds chars it con not parse into a valid token (for error reporting)

    // Single-character tokens.
    t_left_paren,
    t_right_paren,
    t_left_brace,
    t_right_brace,
    t_left_bracket,
    t_right_bracket,
    t_colon,
    t_comma,
    t_dot,
    t_minus,
    t_plus,
    t_question_mark,
    t_semicolon,
    t_slash,
    t_star,
    t_pipe,
    // One or two character tokens.
    t_bang,
    t_bang_equal,
    t_equal,
    t_equal_equal,
    t_greater,
    t_greater_equal,
    t_less,
    t_less_equal,
    t_logical_and,
    t_logical_or,

    // Literals.
    t_identifier,
    t_string_double_quote,
    t_number,

    // Keywords.
    t_const,
    t_else,
    t_error,
    t_for,
    t_function,
    t_if,
    t_return,
    t_type,
    t_var,
    t_while,
    // types
    t_anyerror,
    t_bool,
    t_float,
    t_int,
    t_null,
    t_string,
    t_void,
    // values
    t_false,
    t_true,

    // Special tokens
    t_synthetic,
    t_eof,
};

pub const Token = struct {
    tag: TokenType,
    location: struct {
        start: usize,
        end: usize,
    },
};

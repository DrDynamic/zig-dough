pub const Scanner = struct {
    pub const Error = error{
        UnexpectedCharacter,
        UnterminatedString,
    };
    error_reporter: *const ErrorReporter,

    token_stream: TokenStream,
    window: [3]Token,
    window_index: usize,

    pub fn init(token_stream: TokenStream, error_reporter: *const ErrorReporter) Error!Scanner {
        var scanner = Scanner{
            .error_reporter = error_reporter,
            .token_stream = token_stream,
            .window = .{
                .{ .tag = .t_comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
                .{ .tag = .t_comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
                .{ .tag = .t_comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
            },
            .window_index = 0,
        };

        // initialize the scanner
        try scanner.advance(); // fill next()
        try scanner.advance(); // fill current()

        return scanner;
    }

    pub fn reset(self: *Scanner) Error!void {
        self.token_stream.pos = 0;
        self.window = .{
            .{ .tag = .t_comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
            .{ .tag = .t_comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
            .{ .tag = .t_comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
        };
        self.window_index = 0;

        // initialize the scanner
        try self.advance(); // fill peek()
        try self.advance(); // fill current()
    }

    pub fn next(self: *const Scanner) Token {
        return self.window[(self.window_index + 2) % 3];
    }

    pub fn current(self: *const Scanner) Token {
        return self.window[(self.window_index + 1) % 3];
    }

    pub fn previous(self: *const Scanner) Token {
        return self.window[self.window_index % 3];
    }

    pub fn advance(self: *Scanner) Error!void {
        const token = try self.token_stream.nextToken();

        self.window_index = (self.window_index + 1) % 3;
        self.window[(self.window_index + 2) % 3] = token;
    }

    pub inline fn getLexeme(self: *const Scanner, token: Token) []const u8 {
        return self.token_stream.getLexeme(token);
    }
};

pub const TokenStream = struct {
    error_reporter: ?ErrorReporter,
    file_path: []const u8,
    source: []const u8,
    pos: usize,

    pub fn init(file_path: []const u8, source: []const u8, error_reporter: ?ErrorReporter) TokenStream {
        return .{
            .error_reporter = error_reporter,
            .file_path = file_path,
            .source = source,
            .pos = 0,
        };
    }

    pub fn getFilePath(self: *const TokenStream) []const u8 {
        return self.file_path;
    }

    pub fn getLexeme(self: *const TokenStream, token: Token) []const u8 {
        return self.source[token.location.start..token.location.end];
    }

    pub fn scanPosition(self: *TokenStream, lexeme_start: usize) !Token {
        const currentPosition = self.pos;
        self.pos = lexeme_start;
        const token = self.nextToken();
        self.pos = currentPosition;

        return token;
    }

    fn nextToken(self: *TokenStream) Scanner.Error!Token {
        self.skipWhitespaceAndComments();

        if (self.isAtEnd()) {
            return .{
                .tag = .t_eof,
                .location = .{
                    .start = self.pos,
                    .end = self.pos,
                },
            };
        }

        const start = self.pos;
        const char = self.source[self.pos];
        self.pos += 1;

        return switch (char) {
            // Single-character tokens.
            '(' => .{ .tag = .t_left_paren, .location = .{ .start = start, .end = start + 1 } },
            ')' => .{ .tag = .t_right_paren, .location = .{ .start = start, .end = start + 1 } },
            '{' => .{ .tag = .t_left_brace, .location = .{ .start = start, .end = start + 1 } },
            '}' => .{ .tag = .t_right_brace, .location = .{ .start = start, .end = start + 1 } },
            '[' => .{ .tag = .t_left_bracket, .location = .{ .start = start, .end = start + 1 } },
            ']' => .{ .tag = .t_right_bracket, .location = .{ .start = start, .end = start + 1 } },
            ':' => .{ .tag = .t_colon, .location = .{ .start = start, .end = start + 1 } },
            ',' => .{ .tag = .t_comma, .location = .{ .start = start, .end = start + 1 } },
            '.' => .{ .tag = .t_dot, .location = .{ .start = start, .end = start + 1 } },
            '-' => .{ .tag = .t_minus, .location = .{ .start = start, .end = start + 1 } },
            '+' => .{ .tag = .t_plus, .location = .{ .start = start, .end = start + 1 } },
            '?' => .{ .tag = .t_question_mark, .location = .{ .start = start, .end = start + 1 } },
            ';' => .{ .tag = .t_semicolon, .location = .{ .start = start, .end = start + 1 } },
            '/' => .{ .tag = .t_slash, .location = .{ .start = start, .end = start + 1 } },
            '*' => .{ .tag = .t_star, .location = .{ .start = start, .end = start + 1 } },
            '|' => .{ .tag = .t_pipe, .location = .{ .start = start, .end = start + 1 } },

            // One or two character tokens.
            '!' => if (self.matchChar('='))
                .{ .tag = .t_bang_equal, .location = .{ .start = start, .end = start + 2 } }
            else
                .{ .tag = .t_bang, .location = .{ .start = start, .end = start + 1 } },

            '=' => if (self.matchChar('='))
                .{ .tag = .t_equal_equal, .location = .{ .start = start, .end = start + 2 } }
            else
                .{ .tag = .t_equal, .location = .{ .start = start, .end = start + 1 } },

            '>' => if (self.matchChar('='))
                .{ .tag = .t_greater_equal, .location = .{ .start = start, .end = start + 2 } }
            else
                .{ .tag = .t_greater, .location = .{ .start = start, .end = start + 1 } },
            '<' => if (self.matchChar('='))
                .{ .tag = .t_less_equal, .location = .{ .start = start, .end = start + 2 } }
            else
                .{ .tag = .t_less, .location = .{ .start = start, .end = start + 1 } },

            '"' => self.makeString('"'),
            '0' => self.makeNumber(),
            '1'...'9' => self.makeNumber(),
            else => |c| else_case: {
                if (self.isIdentifierChar(c)) {
                    break :else_case self.makeIdentifier();
                } else {
                    // collect all character to the next whitespace
                    while (!self.isAtEnd()) {
                        const uc = self.source[self.pos];
                        if (std.ascii.isWhitespace(uc)) break;
                        self.pos += 1;
                    }

                    if (self.error_reporter) |error_reporter| {
                        error_reporter.tokenStreamError(self, Scanner.Error.UnexpectedCharacter, start, self.pos, "Unexpected Character");
                    }

                    // TODO collect character to the next whitespace
                    return Scanner.Error.UnexpectedCharacter;
                }
            },
        };
    }

    fn makeString(self: *TokenStream, stringChar: u8) !Token {
        const token_start = self.pos - 1;
        while (!self.matchChar(stringChar) and !self.isAtEnd()) {
            self.pos += 1;
        }

        if (self.isAtEnd() and self.source[self.pos - 1] != stringChar) {
            if (self.error_reporter) |error_reporter| {
                error_reporter.tokenStreamError(self, Scanner.Error.UnterminatedString, token_start, self.pos, "Unterminated String");
            }
            return Scanner.Error.UnterminatedString;
        }

        return .{
            .tag = .t_string_double_quote,
            .location = .{
                .start = token_start,
                .end = self.pos,
            },
        };
    }

    fn makeNumber(self: *TokenStream) Token {
        const token_start = self.pos - 1;
        while (!self.isAtEnd()) {
            if (std.ascii.isDigit(self.source[self.pos]) or (self.source[self.pos] == '.' and self.pos < self.source.len - 1 and std.ascii.isDigit(self.source[self.pos + 1]))) {
                self.pos += 1;
            } else {
                break;
            }
        }

        return .{
            .tag = .t_number,
            .location = .{
                .start = token_start,
                .end = self.pos,
            },
        };
    }

    fn makeIdentifier(self: *TokenStream) Token {
        const token_start = self.pos - 1;
        while (self.isIdentifierChar(self.source[self.pos])) {
            self.pos += 1;
        }
        const token_end = self.pos;
        const token_length = token_end - token_start;

        const tokenType = switch (self.source[token_start]) {
            'a' => |_| a_case: {
                if (token_length > 1) {
                    break :a_case switch (self.source[token_start + 1]) {
                        'n' => {
                            if (token_length > 2) {
                                break :a_case switch (self.source[token_start + 2]) {
                                    'y' => self.matchIdentifier("error", 3, 5, token_start, token_end, .t_anyerror),
                                    'd' => self.matchIdentifier("", 3, 0, token_start, token_end, .t_logical_and),
                                    else => .t_identifier,
                                };
                            }
                            break :a_case .t_identifier;
                        },
                        else => .t_identifier,
                    };
                }
                break :a_case .t_identifier;
            },
            'b' => self.matchIdentifier("ool", 1, 3, token_start, token_end, .t_bool),
            'c' => self.matchIdentifier("onst", 1, 4, token_start, token_end, .t_const),
            'e' => |_| e_case: {
                if (token_length > 1) {
                    break :e_case switch (self.source[token_start + 1]) {
                        'l' => self.matchIdentifier("se", 2, 2, token_start, token_end, .t_else),
                        'r' => self.matchIdentifier("ror", 2, 3, token_start, token_end, .t_error),
                        else => .t_identifier,
                    };
                }
                break :e_case .t_identifier;
            },
            'f' => |_| f_case: {
                if (token_length > 1) {
                    break :f_case switch (self.source[token_start + 1]) {
                        'a' => self.matchIdentifier("lse", 2, 3, token_start, token_end, .t_false),
                        'l' => self.matchIdentifier("oat", 2, 3, token_start, token_end, .t_float),
                        'n' => self.matchIdentifier("", 2, 0, token_start, token_end, .t_function),
                        'o' => self.matchIdentifier("r", 2, 1, token_start, token_end, .t_for),
                        else => .t_identifier,
                    };
                }
                break :f_case .t_identifier;
            },
            'i' => |_| i_case: {
                if (token_length > 1) {
                    break :i_case switch (self.source[token_start + 1]) {
                        'f' => self.matchIdentifier("", 2, 0, token_start, token_end, .t_if),
                        'n' => self.matchIdentifier("t", 2, 1, token_start, token_end, .t_int),
                        else => .t_identifier,
                    };
                }
                break :i_case .t_identifier;
            },
            //            'n' => self.matchIdentifier("ull", 1, 3, token_start, token_end, .t_Null), // TODO: do we have conflicts here? null type vs null value
            'n' => self.matchIdentifier("ull", 1, 3, token_start, token_end, .t_null),
            'o' => self.matchIdentifier("r", 1, 1, token_start, token_end, .t_logical_or),
            'r' => self.matchIdentifier("eturn", 1, 5, token_start, token_end, .t_return),
            's' => self.matchIdentifier("tring", 1, 5, token_start, token_end, .t_string),
            't' => |_| t_case: {
                if (token_length > 1) {
                    break :t_case switch (self.source[token_start + 1]) {
                        'r' => self.matchIdentifier("ue", 2, 2, token_start, token_end, .t_true),
                        'y' => self.matchIdentifier("pe", 2, 2, token_start, token_end, .t_type),
                        else => .t_identifier,
                    };
                }
                break :t_case .t_identifier;
            },
            'v' => |_| v_case: {
                if (token_length > 1) {
                    break :v_case switch (self.source[token_start + 1]) {
                        'a' => self.matchIdentifier("r", 2, 1, token_start, token_end, .t_var),
                        'o' => self.matchIdentifier("id", 2, 2, token_start, token_end, .t_void),
                        else => .t_identifier,
                    };
                }
                break :v_case .t_identifier;
            },

            'w' => self.matchIdentifier("hile", 1, 4, token_start, token_end, .t_while),
            else => .t_identifier,
        };
        return .{
            .tag = tokenType,
            .location = .{
                .start = token_start,
                .end = token_end,
            },
        };
    }

    fn skipWhitespaceAndComments(self: *TokenStream) void {
        while (!self.isAtEnd()) {
            const char = self.source[self.pos];
            switch (char) {
                ' ', '\t'...'\r' => {
                    self.pos += 1;
                },
                '/' => {
                    const nextChar = self.source[self.pos + 1];
                    if (nextChar == '/') {
                        // single line comment
                        self.pos += 2;

                        while (!self.isAtEnd()) {
                            if (self.source[self.pos] == '\n') break;
                            self.pos += 1;
                        }
                    } else if (nextChar == '*') {
                        // multiline comment
                        self.pos += 2;

                        while (!self.isAtEnd()) {
                            if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                                self.pos += 2;
                                break;
                            }
                            self.pos += 1;
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn matchChar(self: *TokenStream, char: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.pos] != char) return false;
        self.pos += 1;
        return true;
    }

    /// checks if the last part of a token matches a given string
    fn matchIdentifier(self: *const TokenStream, rest: []const u8, offset: usize, length: usize, token_start: usize, token_end: usize, guessedTag: TokenType) TokenType {
        if (offset + length == token_end - token_start and std.mem.eql(u8, self.source[token_start + offset .. token_end], rest)) {
            return guessedTag;
        }
        return .t_identifier;
    }

    fn isAtEnd(self: *const TokenStream) bool {
        return self.pos >= self.source.len;
    }

    fn isIdentifierChar(_: *const TokenStream, char: u8) bool {
        return (std.ascii.isAlphanumeric(char) or char == '_' or !std.ascii.isAscii(char));
    }
};

const std = @import("std");

const as = @import("as");
const ErrorReporter = as.common.reporting.ErrorReporter;
const Token = as.frontend.Token;
const TokenType = as.frontend.TokenType;

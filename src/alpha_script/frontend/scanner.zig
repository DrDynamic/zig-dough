pub const Scanner = struct {
    pub const Error = error{
        UnexpectedCharacter,
        UnterminatedString,
    };
    error_reporter: *const ErrorReporter,

    source: []const u8,
    pos: usize,
    window: [3]Token,
    window_index: usize,

    pub fn init(source: []const u8, error_reporter: *const ErrorReporter) Error!Scanner {
        var scanner = Scanner{
            .error_reporter = error_reporter,
            .source = source,
            .pos = 0,
            .window = .{
                .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
                .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
                .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
            },
            .window_index = 0,
        };

        // initialize the scanner
        try scanner.advance(); // fill peek()
        try scanner.advance(); // fill current()

        return scanner;
    }

    pub fn reset(self: *Scanner) Error!void {
        self.pos = 0;
        self.window = .{
            .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
            .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
            .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
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
        //const token: Token = while (true) {
        //    const token = self.nextToken() catch continue;
        //    break token;
        //} else unreachable;

        const token = try self.nextToken();

        self.window_index = (self.window_index + 1) % 3;
        self.window[(self.window_index + 2) % 3] = token;
    }

    pub fn getLexeme(self: *const Scanner, token: Token) []const u8 {
        return self.source[token.location.start..token.location.end];
    }

    fn nextToken(self: *Scanner) Error!Token {
        self.skipWhitespaceAndComments();

        if (self.isAtEnd()) {
            return .{
                .tag = .eof,
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
            '(' => .{ .tag = .left_paren, .location = .{ .start = start, .end = start + 1 } },
            ')' => .{ .tag = .right_paren, .location = .{ .start = start, .end = start + 1 } },
            '{' => .{ .tag = .left_brace, .location = .{ .start = start, .end = start + 1 } },
            '}' => .{ .tag = .right_brace, .location = .{ .start = start, .end = start + 1 } },
            '[' => .{ .tag = .left_bracket, .location = .{ .start = start, .end = start + 1 } },
            ']' => .{ .tag = .right_bracket, .location = .{ .start = start, .end = start + 1 } },
            ':' => .{ .tag = .colon, .location = .{ .start = start, .end = start + 1 } },
            ',' => .{ .tag = .comma, .location = .{ .start = start, .end = start + 1 } },
            '.' => .{ .tag = .dot, .location = .{ .start = start, .end = start + 1 } },
            '-' => .{ .tag = .minus, .location = .{ .start = start, .end = start + 1 } },
            '+' => .{ .tag = .plus, .location = .{ .start = start, .end = start + 1 } },
            '?' => .{ .tag = .question_mark, .location = .{ .start = start, .end = start + 1 } },
            ';' => .{ .tag = .semicolon, .location = .{ .start = start, .end = start + 1 } },
            '/' => .{ .tag = .slash, .location = .{ .start = start, .end = start + 1 } },
            '*' => .{ .tag = .star, .location = .{ .start = start, .end = start + 1 } },
            '|' => .{ .tag = .vertical_line, .location = .{ .start = start, .end = start + 1 } },

            // One or two character tokens.
            '!' => if (self.matchChar('='))
                .{ .tag = .bang_equal, .location = .{ .start = start, .end = start + 2 } }
            else
                .{ .tag = .bang, .location = .{ .start = start, .end = start + 1 } },

            '=' => if (self.matchChar('='))
                .{ .tag = .equal_equal, .location = .{ .start = start, .end = start + 2 } }
            else
                .{ .tag = .equal, .location = .{ .start = start, .end = start + 1 } },

            '>' => if (self.matchChar('='))
                .{ .tag = .greater_equal, .location = .{ .start = start, .end = start + 2 } }
            else
                .{ .tag = .greater, .location = .{ .start = start, .end = start + 1 } },
            '<' => if (self.matchChar('='))
                .{ .tag = .less_equal, .location = .{ .start = start, .end = start + 2 } }
            else
                .{ .tag = .less, .location = .{ .start = start, .end = start + 1 } },

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

                    self.error_reporter.reportScannerError(Error.UnexpectedCharacter, start, self.pos);

                    // TODO collect character to the next whitespace
                    return Error.UnexpectedCharacter;
                }
            },
        };
    }

    fn makeString(self: *Scanner, stringChar: u8) !Token {
        const token_start = self.pos;
        while (!self.matchChar(stringChar) and !self.isAtEnd()) {
            self.pos += 1;
        }

        if (self.isAtEnd() and self.source[self.pos - 1] != stringChar) {
            self.error_reporter.reportScannerError(Error.UnterminatedString, token_start, self.pos - 1);
            return Error.UnterminatedString;
        }

        return .{
            .tag = .string,
            .location = .{
                .start = token_start,
                .end = self.pos - 1,
            },
        };
    }

    fn makeNumber(self: *Scanner) Token {
        const token_start = self.pos - 1;
        while (!self.isAtEnd()) {
            if (std.ascii.isDigit(self.source[self.pos]) or (self.source[self.pos] == '.' and std.ascii.isDigit(self.source[self.pos + 1]))) {
                self.pos += 1;
            } else {
                break;
            }
        }

        return .{
            .tag = .number,
            .location = .{
                .start = token_start,
                .end = self.pos,
            },
        };
    }

    fn makeIdentifier(self: *Scanner) Token {
        const token_start = self.pos - 1;
        while (self.isIdentifierChar(self.source[self.pos])) {
            self.pos += 1;
        }
        const token_end = self.pos;

        const tokenType = switch (self.source[token_start]) {
            'a' => self.matchIdentifier("nd", 1, 2, token_start, token_end, .logical_and),
            'c' => self.matchIdentifier("onst", 1, 4, token_start, token_end, .const_),
            'e' => |_| e_case: {
                if (token_end - token_start > 1) {
                    break :e_case switch (self.source[token_start + 1]) {
                        'l' => self.matchIdentifier("se", 2, 2, token_start, token_end, .else_),
                        'r' => self.matchIdentifier("ror", 2, 3, token_start, token_end, .error_),
                        else => .identifier,
                    };
                }
                break :e_case .identifier;
            },
            'f' => |_| f_case: {
                if (token_end - token_start > 1) {
                    break :f_case switch (self.source[token_start + 1]) {
                        'a' => self.matchIdentifier("lse", 2, 3, token_start, token_end, .false_),
                        'o' => self.matchIdentifier("r", 2, 1, token_start, token_end, .for_),
                        'u' => self.matchIdentifier("nction", 2, 6, token_start, token_end, .function_),
                        else => .identifier,
                    };
                }
                break :f_case .identifier;
            },
            'i' => self.matchIdentifier("f", 1, 1, token_start, token_end, .if_),
            'n' => self.matchIdentifier("ull", 1, 3, token_start, token_end, .null_),
            'o' => self.matchIdentifier("r", 1, 1, token_start, token_end, .logical_or),
            'r' => self.matchIdentifier("eturn", 1, 5, token_start, token_end, .return_),
            't' => |_| t_case: {
                if (token_end - token_start > 1) {
                    break :t_case switch (self.source[token_start + 1]) {
                        'r' => self.matchIdentifier("ue", 2, 2, token_start, token_end, .true_),
                        'y' => self.matchIdentifier("pe", 2, 2, token_start, token_end, .type_),
                        else => .identifier,
                    };
                }
                break :t_case .identifier;
            },

            'v' => self.matchIdentifier("ar", 1, 2, token_start, token_end, .var_),
            'w' => self.matchIdentifier("hile", 1, 4, token_start, token_end, .while_),
            else => .identifier,
        };
        return .{
            .tag = tokenType,
            .location = .{
                .start = token_start,
                .end = token_end,
            },
        };
    }

    fn skipWhitespaceAndComments(self: *Scanner) void {
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

    fn matchChar(self: *Scanner, char: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.pos] != char) return false;
        self.pos += 1;
        return true;
    }

    /// checks if the last part of a token matches a given string
    fn matchIdentifier(self: *const Scanner, rest: []const u8, offset: usize, length: usize, token_start: usize, token_end: usize, guessedTag: TokenType) TokenType {
        if (offset + length == token_end - token_start and std.mem.eql(u8, self.source[token_start + offset .. token_end], rest)) {
            return guessedTag;
        }
        return .identifier;
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self.pos >= self.source.len;
    }

    fn isIdentifierChar(_: *const Scanner, char: u8) bool {
        return (std.ascii.isAlphanumeric(char) or char == '_' or !std.ascii.isAscii(char));
    }
};

const std = @import("std");

const as = @import("as");
const ErrorReporter = as.frontend.ErrorReporter;
const Token = as.frontend.Token;
const TokenType = as.frontend.TokenType;

test "Scanns all tokens" {
    var scanner = Scanner.init(
        \\ (
        \\ )
        \\ {
        \\ }
        \\ [
        \\ ]
        \\ ,
        \\ .
        \\ -
        \\ +
        \\ ;
        \\ /
        \\ *
        \\ !
        \\ !=
        \\ =
        \\ ==
        \\ >
        \\ >=
        \\ <
        \\ <=
        \\ &&
        \\ ||
        \\ this_is_a_identifier
        \\ "i read double quotes"
        \\ 123
        \\ 13.37
        \\ const
        \\ else
        \\ false
        \\ for
        \\ function
        \\ if
        \\ null
        \\ return
        \\ true
        \\ var
        \\ while
        \\
    );

    const tokenTypes = [_]TokenType{
        TokenType.left_paren,
        TokenType.right_paren,
        TokenType.left_brace,
        TokenType.right_brace,
        TokenType.left_bracket,
        TokenType.right_bracket,
        TokenType.comma,
        TokenType.dot,
        TokenType.minus,
        TokenType.plus,
        TokenType.semicolon,
        TokenType.slash,
        TokenType.star,
        // One or two character tokens.
        TokenType.bang,
        TokenType.bang_equal,
        TokenType.equal,
        TokenType.equal_equal,
        TokenType.greater,
        TokenType.greater_equal,
        TokenType.less,
        TokenType.less_equal,
        TokenType.logical_and,
        TokenType.logical_or,
        // Literals.
        TokenType.identifier,
        TokenType.string,
        TokenType.number,
        // Keywords.
        TokenType.const_,
        TokenType.else_,
        TokenType.false_,
        TokenType.for_,
        TokenType.function_,
        TokenType.if_,
        TokenType.null_,
        TokenType.return_,
        TokenType.true_,
        TokenType.var_,
        TokenType.while_,
        TokenType.eof,
    };

    for (tokenTypes) |tokenType| {
        scanner.advance();
        //        std.debug.print("Expect {d}:{?s} but got ", .{ line, std.enums.tagName(TokenType, tokenType) });
        //        scanner.current.debugPrint();
        try std.testing.expectEqual(tokenType, scanner.current().tag);
    }
}

test "supports everything above ascii as identifiers" {
    var scanner = Scanner.init(
        \\ 🥟
        \\ "🍕"
        \\ 🍩
    );

    scanner.scanToken();
    try std.testing.expectEqual(scanner.current.tag, TokenType.identifier);
    try std.testing.expectEqualStrings("🥟", scanner.current.lexeme.?);

    scanner.scanToken();
    try std.testing.expectEqual(scanner.current.tag, TokenType.string);
    try std.testing.expectEqualStrings("🍕", scanner.current.lexeme.?);

    scanner.scanToken();
    try std.testing.expect(scanner.current.tag == TokenType.identifier);
    try std.testing.expectEqualStrings(scanner.current.lexeme.?, &std.unicode.utf8EncodeComptime('🍩'));
}

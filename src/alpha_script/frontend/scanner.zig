const std = @import("std");

const as = @import("as");
const Token = as.frontend.Token;
const TokenType = as.frontend.TokenType;
//    refactoring note:
//     change to tokenstorage
//     const TokenStorage = struct {
//       tags: []TokenType,
//       line_numbers: []u32,
//       starts: []u32,
//       lengths: []u32,
//     };
//
//
// iterator pattern for tokens:
//  (peek /neyxt / etc)

pub const Scanner = struct {
    source: []const u8,
    pos: usize,
    window: [3]Token,
    window_index: usize,

    pub fn init(source: []const u8) Scanner {
        var scanner = Scanner{
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
        scanner.advance(); // fill peek()
        scanner.advance(); // fill current()

        return scanner;
    }

    pub fn reset(self: *Scanner) void {
        self.pos = 0;
        self.window = .{
            .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
            .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
            .{ .tag = .comptime_uninitialized, .location = .{ .start = 0, .end = 0 } },
        };
        self.window_index = 0;

        // initialize the scanner
        self.advance(); // fill peek()
        self.advance(); // fill current()
    }

    pub fn peek(self: *const Scanner) Token {
        return self.window[(self.window_index + 2) % 3];
    }

    pub fn current(self: *const Scanner) Token {
        return self.window[(self.window_index + 1) % 3];
    }

    pub fn previous(self: *const Scanner) Token {
        return self.window[self.window_index % 3];
    }

    pub fn advance(self: *Scanner) void {
        self.window_index = (self.window_index + 1) % 3;
        self.window[(self.window_index + 2) % 3] = self.nextToken();
    }

    pub fn getLexeme(self: *const Scanner, token: Token) []const u8 {
        return self.source[token.location.start..token.location.end];
    }

    fn nextToken(self: *Scanner) Token {
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
                    break :else_case .{
                        .tag = .error_,
                        .location = .{
                            .start = start,
                            .end = start + 1,
                        },
                    };
                }
            },
        };
    }

    fn makeString(self: *Scanner, stringChar: u8) Token {
        const token_start = self.pos;
        while (!self.matchChar(stringChar) and !self.isAtEnd()) {
            self.pos += 1;
        }

        if (self.isAtEnd() and self.source[self.pos - 1] != stringChar) {
            return .{
                .tag = .error_,
                .location = .{
                    .start = token_start,
                    .end = self.pos,
                },
            };
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
                    const next = self.source[self.pos + 1];
                    if (next == '/') {
                        // single line comment
                        self.pos += 2;

                        while (!self.isAtEnd()) {
                            if (self.source[self.pos] == '\n') break;
                            self.pos += 1;
                        }
                    } else if (next == '*') {
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
    previous: Token = .{
        .tag = null,
        .lexeme = null,
        .line = 0,
    },
    current: Token = .{
        .tag = null,
        .lexeme = null,
        .line = 0,
    },
    next: Token = .{
        .tag = null,
        .lexeme = null,
        .line = 0,
    },

    _source: []const u8 = undefined,
    _tokenStart: [*]const u8 = undefined,
    _currentChar: [*:0]const u8 = undefined,
    _line: usize = 0,

    pub fn init(source: []const u8) Scanner {
        var scanner = Scanner{
            ._source = source,
            ._tokenStart = @ptrCast(source),
            ._currentChar = @ptrCast(source),
            ._line = 1,
        };

        scanner.scanToken(); // into next
        scanner.scanToken(); // into current

        if (false) {
            scanner.debugPrint();
            scanner.reset();
        }
        return scanner;
    }

    pub fn reset(self: *Scanner) void {
        self._tokenStart = @ptrCast(self._source);
        self._currentChar = @ptrCast(self._source);
        self._line = 1;

        self.previous = .{
            .tag = null,
            .lexeme = null,
            .line = 0,
        };
        self.current = .{
            .tag = null,
            .lexeme = null,
            .line = 0,
        };
        self.next = .{
            .tag = null,
            .lexeme = null,
            .line = 0,
        };
        self.scanToken(); // into next
        self.scanToken(); // into current
    }

    pub fn debugPrint(self: *Scanner) void {
        var i: u32 = 0;
        while (self.current.tag != TokenType.eof) : (i += 1) {
            self.scanToken();
            self.current.debugPrint();
            if (i > 50) break;
        }
    }

    pub fn scanToken(self: *Scanner) void {
        self.previous = self.current;
        self.current = self.next;

        self.skipWhitespace();
        if (self.current.tag == TokenType.eof) return;
        if (self.isAtEnd()) {
            self.makeToken(TokenType.eof);
            self.next.lexeme = null;
            return;
        }

        self._tokenStart = self._currentChar;
        const c = self.advance();
        switch (c) {
            // Single-character tokens.
            '(' => self.makeToken(.left_paren),
            ')' => self.makeToken(.right_paren),
            '{' => self.makeToken(.left_brace),
            '}' => self.makeToken(.right_brace),
            '[' => self.makeToken(.left_bracket),
            ']' => self.makeToken(.right_bracket),
            ':' => self.makeToken(.colon),
            ',' => self.makeToken(.comma),
            '.' => self.makeToken(.dot),
            '-' => self.makeToken(.minus),
            '+' => self.makeToken(.plus),
            '?' => self.makeToken(.question_mark),
            ';' => self.makeToken(.semicolon),
            '/' => self.makeToken(.slash),
            '*' => self.makeToken(.star),
            '|' => self.makeToken(.vertical_line),

            // One or two character tokens.
            '!' => if (self.match('=')) self.makeToken(.bang_equal) else self.makeToken(.bang),
            '=' => if (self.match('=')) self.makeToken(.equal_equal) else self.makeToken(.equal),
            '>' => if (self.match('=')) self.makeToken(.greater_equal) else self.makeToken(.greater),
            '<' => if (self.match('=')) self.makeToken(.less_equal) else self.makeToken(.less),

            '"' => {
                self.makeString('"');
            },
            '0' => {
                self.makeNumber();
            },
            '1'...'9' => self.makeNumber(),
            else => |char| {
                if (self.isIdentifierChar(char)) {
                    self.makeIdentifier();
                } else {
                    self.makeError("Unexpected character.");
                }
            },
        }
    }

    fn makeToken(self: *Scanner, tokenType: TokenType) void {
        const tokenLen: usize = self._currentChar - self._tokenStart;

        self.next.tag = tokenType;
        self.next.lexeme = self._tokenStart[0..tokenLen];
        self.next.line = self._line;
    }

    fn makeError(self: *Scanner, message: []const u8) void {
        self.next.tag = TokenType.scanner_error;
        self.next.lexeme = message;
        self.next.line = self._line;
    }

    fn isAtEnd(self: Scanner) bool {
        return (self._currentChar[0] == 0);
    }

    fn peek(self: *Scanner) u8 {
        return self._currentChar[0];
    }

    fn peekNext(self: *Scanner) u8 {
        return self._currentChar[1];
    }

    fn match(self: *Scanner, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self._currentChar[0] != expected) return false;
        self._currentChar += 1;
        return true;
    }

    fn advance(self: *Scanner) u8 {
        const c = self._currentChar;
        self._currentChar += 1;
        return c[0];
    }

    fn skipWhitespace(self: *Scanner) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            switch (c) {
                ' ', '\t'...'\r' => {
                    if (c == '\n') {
                        self._line += 1;
                    }
                    _ = self.advance();
                },
                '/' => {
                    const next = self.peekNext();
                    if (next == '/') {
                        // single line comment

                        _ = self.advance();
                        _ = self.advance();

                        while (!self.isAtEnd()) {
                            if (self.peek() == '\n') break;
                            _ = self.advance();
                        }
                    } else if (next == '*') {
                        // multiline comment

                        _ = self.advance();
                        _ = self.advance();

                        while (!self.isAtEnd()) {
                            if (self.peek() == '*' and self.peekNext() == '/') {
                                _ = self.advance();
                                _ = self.advance();
                                break;
                            }
                            _ = self.advance();
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn makeString(self: *Scanner, stringChar: u8) void {
        while (!self.match(stringChar) and !self.isAtEnd()) {
            if (self.peek() == '\n') {
                self._line += 1;
            }
            _ = self.advance();
        }
        self.makeToken(TokenType.string);

        if (self.isAtEnd()) {
            self.makeError("Unterminated string.");
            return;
        }

        const tokenLen: usize = self._currentChar - self._tokenStart;
        self.next.lexeme = self._tokenStart[1 .. tokenLen - 1];
    }

    fn makeNumber(self: *Scanner) void {
        while (!self.isAtEnd()) {
            if (std.ascii.isDigit(self.peek()) or (self.peek() == '.' and std.ascii.isDigit(self.peekNext()))) {
                _ = self.advance();
            } else {
                break;
            }
        }
        self.makeToken(TokenType.number);
    }

    fn isIdentifierChar(_: Scanner, char: u8) bool {
        return (std.ascii.isAlphanumeric(char) or char == '_' or !std.ascii.isAscii(char));
    }

    fn makeIdentifier(self: *Scanner) void {
        while (self.isIdentifierChar(self.peek())) {
            _ = self.advance();
        }

        const tokenType = switch (self._tokenStart[0]) {
            'a' => self.matchIdentifier("nd", 1, 2, .logical_and),
            'c' => self.matchIdentifier("onst", 1, 4, .const_),
            'e' => |_| e_case: {
                if (self._currentChar - self._tokenStart > 1) {
                    break :e_case switch (self._tokenStart[1]) {
                        'l' => self.matchIdentifier("se", 2, 2, .else_),
                        'r' => self.matchIdentifier("ror", 2, 3, .error_),
                        else => .identifier,
                    };
                }
                break :e_case .identifier;
            },
            'f' => |_| f_case: {
                if (self._currentChar - self._tokenStart > 1) {
                    break :f_case switch (self._tokenStart[1]) {
                        'a' => self.matchIdentifier("lse", 2, 3, .false_),
                        'o' => self.matchIdentifier("r", 2, 1, .for_),
                        'u' => self.matchIdentifier("nction", 2, 6, .function_),
                        else => .identifier,
                    };
                }
                break :f_case .identifier;
            },
            'i' => self.matchIdentifier("f", 1, 1, .if_),
            'n' => self.matchIdentifier("ull", 1, 3, .null_),
            'o' => self.matchIdentifier("r", 1, 1, .logical_or),
            'r' => self.matchIdentifier("eturn", 1, 5, .return_),
            't' => |_| t_case: {
                if (self._currentChar - self._tokenStart > 1) {
                    break :t_case switch (self._tokenStart[1]) {
                        'r' => self.matchIdentifier("ue", 2, 2, .true_),
                        'y' => self.matchIdentifier("pe", 2, 2, .type_),
                        else => .identifier,
                    };
                }
                break :t_case .identifier;
            },

            'v' => self.matchIdentifier("ar", 1, 2, .var_),
            'w' => self.matchIdentifier("hile", 1, 4, .while_),
            else => .identifier,
        };
        self.makeToken(tokenType);
    }

    fn matchIdentifier(self: Scanner, rest: []const u8, start: u8, length: u8, tokenType: TokenType) TokenType {
        if (self._currentChar - self._tokenStart == start + length and std.mem.eql(u8, self._tokenStart[start..(start + length)], rest)) {
            return tokenType;
        }
        return .identifier;
    }
};

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

const std = @import("std");

const dough = @import("dough");
const config = dough.config;
const Token = dough.frontend.Token;
const TokenType = dough.frontend.TokenType;

pub const Scanner = struct {
    previous: Token = .{
        .token_type = null,
        .lexeme = null,
        .line = 0,
    },
    current: Token = .{
        .token_type = null,
        .lexeme = null,
        .line = 0,
    },
    next: Token = .{
        .token_type = null,
        .lexeme = null,
        .line = 0,
    },

    _tokenStart: [*]const u8 = undefined,
    _currentChar: [*:0]const u8 = undefined,
    _line: usize = 0,

    pub fn init(source: []const u8) Scanner {
        var scanner = Scanner{
            ._tokenStart = @ptrCast(source),
            ._currentChar = @ptrCast(source),
            ._line = 1,
        };

        scanner.scanToken();
        if (config.debug_print_tokens) {
            scanner.debugPrint();

            scanner._tokenStart = @ptrCast(source);
            scanner._currentChar = @ptrCast(source);
            scanner._line = 1;
        }
        return scanner;
    }

    pub fn debugPrint(self: *Scanner) void {
        var i: u32 = 0;
        while (self.current.token_type != TokenType.Eof) : (i += 1) {
            self.scanToken();
            self.current.debugPrint();
            if (i > 50) break;
        }
    }

    pub fn scanToken(self: *Scanner) void {
        self.previous = self.current;
        self.current = self.next;

        self.skipWhitespace();
        if (self.current.token_type == TokenType.Eof) return;
        if (self.isAtEnd()) {
            self.makeToken(TokenType.Eof);
            self.next.lexeme = null;
            return;
        }

        self._tokenStart = self._currentChar;
        const c = self.advance();
        switch (c) {
            // Single-character tokens.
            '(' => self.makeToken(.LeftParen),
            ')' => self.makeToken(.RightParen),
            '{' => self.makeToken(.LeftBrace),
            '}' => self.makeToken(.RightBrace),
            '[' => self.makeToken(.LeftBracket),
            ']' => self.makeToken(.RightBracket),
            ':' => self.makeToken(.Colon),
            ',' => self.makeToken(.Comma),
            '.' => self.makeToken(.Dot),
            '-' => self.makeToken(.Minus),
            '+' => self.makeToken(.Plus),
            '?' => self.makeToken(.QuestionMark),
            ';' => self.makeToken(.Semicolon),
            '/' => self.makeToken(.Slash),
            '*' => self.makeToken(.Star),

            // One or two character tokens.
            '!' => if (self.match('=')) self.makeToken(.BangEqual) else self.makeToken(.Bang),
            '=' => if (self.match('=')) self.makeToken(.EqualEqual) else self.makeToken(.Equal),
            '>' => if (self.match('=')) self.makeToken(.GreaterEqual) else self.makeToken(.Greater),
            '<' => if (self.match('=')) self.makeToken(.LessEqual) else self.makeToken(.Less),

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

        self.next.token_type = tokenType;
        self.next.lexeme = self._tokenStart[0..tokenLen];
        self.next.line = self._line;
    }

    fn makeError(self: *Scanner, message: []const u8) void {
        self.next.token_type = TokenType.Error;
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
        self.makeToken(TokenType.String);

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
        self.makeToken(TokenType.Number);
    }

    fn isIdentifierChar(_: Scanner, char: u8) bool {
        return (std.ascii.isAlphanumeric(char) or char == '_' or !std.ascii.isAscii(char));
    }

    fn makeIdentifier(self: *Scanner) void {
        while (self.isIdentifierChar(self.peek())) {
            _ = self.advance();
        }

        const tokenType = switch (self._tokenStart[0]) {
            'a' => self.matchIdentifier("nd", 1, 2, .LogicalAnd),
            'c' => self.matchIdentifier("onst", 1, 4, .Const),
            'e' => self.matchIdentifier("lse", 1, 3, .Else),
            'f' => |_| f_case: {
                if (self._currentChar - self._tokenStart > 1) {
                    break :f_case switch (self._tokenStart[1]) {
                        'a' => self.matchIdentifier("lse", 2, 3, .False),
                        'o' => self.matchIdentifier("r", 2, 1, .For),
                        'u' => self.matchIdentifier("nction", 2, 6, .Function),
                        else => .Identifier,
                    };
                }
                break :f_case .Identifier;
            },
            'i' => self.matchIdentifier("f", 1, 1, .If),
            'n' => self.matchIdentifier("ull", 1, 3, .Null),
            'o' => self.matchIdentifier("r", 1, 1, .LogicalOr),
            'r' => self.matchIdentifier("eturn", 1, 5, .Return),
            't' => |_| t_case: {
                if (self._currentChar - self._tokenStart > 1) {
                    break :t_case switch (self._tokenStart[1]) {
                        'r' => self.matchIdentifier("ue", 2, 2, .True),
                        'y' => self.matchIdentifier("pe", 2, 2, .Type),
                        else => .Identifier,
                    };
                }
                break :t_case .Identifier;
            },

            'v' => self.matchIdentifier("ar", 1, 2, .Var),
            'w' => self.matchIdentifier("hile", 1, 4, .While),
            else => .Identifier,
        };
        self.makeToken(tokenType);
    }

    fn matchIdentifier(self: Scanner, rest: []const u8, start: u8, length: u8, tokenType: TokenType) TokenType {
        if (self._currentChar - self._tokenStart == start + length and std.mem.eql(u8, self._tokenStart[start..(start + length)], rest)) {
            return tokenType;
        }
        return .Identifier;
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
        TokenType.LeftParen,
        TokenType.RightParen,
        TokenType.LeftBrace,
        TokenType.RightBrace,
        TokenType.LeftBracket,
        TokenType.RightBracket,
        TokenType.Comma,
        TokenType.Dot,
        TokenType.Minus,
        TokenType.Plus,
        TokenType.Semicolon,
        TokenType.Slash,
        TokenType.Star,
        // One or two character tokens.
        TokenType.Bang,
        TokenType.BangEqual,
        TokenType.Equal,
        TokenType.EqualEqual,
        TokenType.Greater,
        TokenType.GreaterEqual,
        TokenType.Less,
        TokenType.LessEqual,
        TokenType.LogicalAnd,
        TokenType.LogicalOr,
        // Literals.
        TokenType.Identifier,
        TokenType.String,
        TokenType.Number,
        // Keywords.
        TokenType.Const,
        TokenType.Else,
        TokenType.False,
        TokenType.For,
        TokenType.Function,
        TokenType.If,
        TokenType.Null,
        TokenType.Return,
        TokenType.True,
        TokenType.Var,
        TokenType.While,
        TokenType.Eof,
    };

    for (tokenTypes, 1..) |tokenType, line| {
        scanner.scanToken();
        //        std.debug.print("Expect {d}:{?s} but got ", .{ line, std.enums.tagName(TokenType, tokenType) });
        //        scanner.current.debugPrint();
        try std.testing.expectEqual(tokenType, scanner.current.token_type);
        try std.testing.expectEqual(line, scanner.current.line);
    }
}

test "supports everything above ascii as identifiers" {
    var scanner = Scanner.init(
        \\ 🥟
        \\ "🍕"
        \\ 🍩
    );

    scanner.scanToken();
    try std.testing.expectEqual(scanner.current.token_type, TokenType.Identifier);
    try std.testing.expectEqualStrings("🥟", scanner.current.lexeme.?);

    scanner.scanToken();
    try std.testing.expectEqual(scanner.current.token_type, TokenType.String);
    try std.testing.expectEqualStrings("🍕", scanner.current.lexeme.?);

    scanner.scanToken();
    try std.testing.expect(scanner.current.token_type == TokenType.Identifier);
    try std.testing.expectEqualStrings(scanner.current.lexeme.?, &std.unicode.utf8EncodeComptime('🍩'));
}

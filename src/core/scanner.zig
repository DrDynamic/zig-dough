const std = @import("std");

const token = @import("./token.zig");
const Token = token.Token;
const TokenType = token.TokenType;

pub const Scanner = struct {
    previous: Token = .{
        .type = null,
        .lexeme = null,
        .line = 0,
    },
    current: Token = .{
        .type = null,
        .lexeme = null,
        .line = 0,
    },
    next: Token = .{
        .type = null,
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
        return scanner;
    }

    pub fn debugPrint(self: *Scanner) void {
        var i: u32 = 0;
        while (self.current.type != TokenType.Eof) : (i += 1) {
            self.scanToken();
            self.current.debugPrint();
            if (i > 50) break;
        }
    }

    pub fn scanToken(self: *Scanner) void {
        self.previous = self.current;
        self.current = self.next;

        self.skipWhitespace();
        if (self.current.type == TokenType.Eof) return;
        if (self.isAtEnd()) {
            self.makeToken(TokenType.Eof);
            self.next.lexeme = null;
            return;
        }

        self._tokenStart = self._currentChar;
        const c = self.advance();
        switch (c) {
            // Single-character tokens.
            '(' => self.makeToken(TokenType.LeftParen),
            ')' => self.makeToken(TokenType.RightParen),
            '{' => self.makeToken(TokenType.LeftBrace),
            '}' => self.makeToken(TokenType.RightBrace),
            '[' => self.makeToken(TokenType.LeftBracket),
            ']' => self.makeToken(TokenType.RightBracket),
            ',' => self.makeToken(TokenType.Comma),
            '.' => self.makeToken(TokenType.Dot),
            '-' => self.makeToken(TokenType.Minus),
            '+' => self.makeToken(TokenType.Plus),
            ';' => self.makeToken(TokenType.Semicolon),
            '/' => self.makeToken(TokenType.Slash),
            '*' => self.makeToken(TokenType.Star),

            // One or two character tokens.
            '!' => if (self.match('=')) self.makeToken(TokenType.BangEqual) else self.makeToken(TokenType.Bang),
            '=' => if (self.match('=')) self.makeToken(TokenType.EqualEqual) else self.makeToken(TokenType.Equal),
            '>' => if (self.match('=')) self.makeToken(TokenType.GreaterEqual) else self.makeToken(TokenType.Greater),
            '<' => if (self.match('=')) self.makeToken(TokenType.LessEqual) else self.makeToken(TokenType.Less),
            '&' => if (self.match('&')) self.makeToken(TokenType.LogicalAnd) else self.makeError("Unexpected character."),
            '|' => if (self.match('|')) self.makeToken(TokenType.LogicalOr) else self.makeError("Unexpected character."),

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

        self.next.type = tokenType;
        self.next.lexeme = self._tokenStart[0..tokenLen];
        self.next.line = self._line;
    }

    fn makeError(self: *Scanner, message: []const u8) void {
        self.next.type = TokenType.Error;
        self.next.lexeme = message;
        self.next.line = self._line;
    }

    fn isAtEnd(self: Scanner) bool {
        return (self._currentChar[0] == 0);
    }

    fn peek(self: *Scanner) u8 {
        return self._currentChar[0];
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
                // TODO: add comments
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

        const tokenLen: usize = self._currentChar - self._tokenStart;
        self.next.lexeme = self._tokenStart[1 .. tokenLen - 1];
    }

    fn makeNumber(self: *Scanner) void {
        while (!self.isAtEnd()) {
            if (std.ascii.isDigit(self.peek())) {
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
            'c' => self.matchIdentifier("onst", 1, 4, TokenType.Const),
            'e' => self.matchIdentifier("lse", 1, 3, TokenType.Else),
            'f' => |_| f_case: {
                if (self._currentChar - self._tokenStart > 1) {
                    break :f_case switch (self._tokenStart[1]) {
                        'a' => self.matchIdentifier("lse", 2, 3, TokenType.False),
                        'o' => self.matchIdentifier("r", 2, 1, TokenType.For),
                        'u' => self.matchIdentifier("nction", 2, 6, TokenType.Function),
                        else => TokenType.Identifier,
                    };
                }
                break :f_case TokenType.Identifier;
            },
            'i' => self.matchIdentifier("f", 1, 1, TokenType.If),
            'n' => self.matchIdentifier("ull", 1, 3, TokenType.Null),
            'r' => self.matchIdentifier("eturn", 1, 5, TokenType.Return),
            't' => self.matchIdentifier("rue", 1, 3, TokenType.True),
            'v' => self.matchIdentifier("ar", 1, 2, TokenType.Var),
            'w' => self.matchIdentifier("hile", 1, 4, TokenType.While),
            else => TokenType.Identifier,
        };
        self.makeToken(tokenType);
    }

    fn matchIdentifier(self: Scanner, rest: []const u8, start: u8, length: u8, tokenType: TokenType) TokenType {
        if (self._currentChar - self._tokenStart == start + length and std.mem.eql(u8, self._tokenStart[start..(start + length)], rest)) {
            return tokenType;
        }
        return TokenType.Identifier;
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
        try std.testing.expectEqual(tokenType, scanner.current.type);
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
    try std.testing.expectEqual(scanner.current.type, TokenType.Identifier);
    try std.testing.expectEqualStrings("🥟", scanner.current.lexeme.?);

    scanner.scanToken();
    try std.testing.expectEqual(scanner.current.type, TokenType.String);
    try std.testing.expectEqualStrings("🍕", scanner.current.lexeme.?);

    scanner.scanToken();
    try std.testing.expect(scanner.current.type == TokenType.Identifier);
    try std.testing.expectEqualStrings(scanner.current.lexeme.?, &std.unicode.utf8EncodeComptime('🍩'));
}

const std = @import("std");

const token = @import("./token.zig");
const Token = token.Token;
const TokenType = token.TokenType;

pub const Scanner = struct {
    previous: Token = .{
        .type = TokenType.ERROR,
        .lexeme = null,
        .line = 0,
    },
    current: Token = .{
        .type = TokenType.ERROR,
        .lexeme = null,
        .line = 0,
    },
    next: Token = .{
        .type = TokenType.ERROR,
        .lexeme = null,
        .line = 0,
    },

    _tokenStart: [*]const u8 = undefined,
    _currentChar: [*:0]const u8 = undefined,
    _line: usize = 0,

    pub fn init(self: *Scanner, source: [:0]const u8) void {
        self._tokenStart = @ptrCast(source);
        self._currentChar = @ptrCast(source);
        self._line = 1;
    }

    pub fn debugPrint(self: *Scanner) void {
        var i: u32 = 0;
        while (self.current.type != TokenType.EOF) : (i += 1) {
            self.scanToken();
            self.current.debugPrint();
            if (i > 50) break;
        }
    }

    pub fn scanToken(self: *Scanner) void {
        self.previous = self.current;
        self.current = self.next;

        self.skipWhitespace();
        if (self.current.type == TokenType.EOF) return;
        if (self.isAtEnd()) {
            self.makeToken(TokenType.EOF);
            self.next.lexeme = null;
            return;
        }

        self._tokenStart = self._currentChar;
        const c = self.advance();
        switch (c) {
            // Single-character tokens.
            '(' => self.makeToken(TokenType.LEFT_PAREN),
            ')' => self.makeToken(TokenType.RIGHT_PAREN),
            '{' => self.makeToken(TokenType.LEFT_BRACE),
            '}' => self.makeToken(TokenType.RIGHT_BRACE),
            '[' => self.makeToken(TokenType.LEFT_BRACKET),
            ']' => self.makeToken(TokenType.RIGHT_BRACKET),
            ',' => self.makeToken(TokenType.COMMA),
            '.' => self.makeToken(TokenType.DOT),
            '-' => self.makeToken(TokenType.MINUS),
            '+' => self.makeToken(TokenType.PLUS),
            ';' => self.makeToken(TokenType.SEMICOLON),
            '/' => self.makeToken(TokenType.SLASH),
            '*' => self.makeToken(TokenType.STAR),

            // One or two character tokens.
            '!' => if (self.match('=')) self.makeToken(TokenType.BANG_EQUAL) else self.makeToken(TokenType.BANG),
            '=' => if (self.match('=')) self.makeToken(TokenType.EQUAL_EQUAL) else self.makeToken(TokenType.EQUAL),
            '>' => if (self.match('=')) self.makeToken(TokenType.GREATER_EQUAL) else self.makeToken(TokenType.GREATER),
            '<' => if (self.match('=')) self.makeToken(TokenType.LESS_EQUAL) else self.makeToken(TokenType.LESS),
            '&' => if (self.match('&')) self.makeToken(TokenType.LOGICAL_AND) else self.makeError("Unexpected character."),
            '|' => if (self.match('|')) self.makeToken(TokenType.LOGICAL_AND) else self.makeError("Unexpected character."),

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
        self.next.type = TokenType.ERROR;
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
        self.makeToken(TokenType.STRING);

        const tokenLen: usize = self._currentChar - self._tokenStart;
        self.next.lexeme = self._tokenStart[1 .. tokenLen - 2];
    }

    fn makeNumber(self: *Scanner) void {
        while (!self.isAtEnd()) {
            if (std.ascii.isDigit(self.peek())) {
                _ = self.advance();
            } else {
                break;
            }
        }
        self.makeToken(TokenType.NUMBER);
    }

    fn isIdentifierChar(_: Scanner, char: u8) bool {
        return (std.ascii.isAlphanumeric(char) or char == '_' or !std.ascii.isAscii(char));
    }

    fn makeIdentifier(self: *Scanner) void {
        while (self.isIdentifierChar(self.peek())) {
            _ = self.advance();
        }

        const tokenType = switch (self._tokenStart[0]) {
            'c' => self.matchIdentifier("onst", 1, 4, TokenType.CONST),
            'e' => self.matchIdentifier("lse", 1, 3, TokenType.ELSE),
            'f' => |_| f_case: {
                if (self._currentChar - self._tokenStart > 1) {
                    break :f_case switch (self._tokenStart[1]) {
                        'a' => self.matchIdentifier("lse", 2, 3, TokenType.FALSE),
                        'o' => self.matchIdentifier("r", 2, 1, TokenType.FOR),
                        'u' => self.matchIdentifier("nction", 2, 6, TokenType.FUNCTION),
                        else => TokenType.IDENTIFIER,
                    };
                }
                break :f_case TokenType.IDENTIFIER;
            },
            'i' => self.matchIdentifier("f", 1, 1, TokenType.IF),
            'n' => self.matchIdentifier("ull", 1, 3, TokenType.NULL),
            'r' => self.matchIdentifier("eturn", 1, 5, TokenType.RETURN),
            't' => self.matchIdentifier("rue", 1, 3, TokenType.TRUE),
            'v' => self.matchIdentifier("ar", 1, 3, TokenType.VAR),
            'w' => self.matchIdentifier("hile", 1, 4, TokenType.WHILE),
            else => TokenType.IDENTIFIER,
        };
        self.makeToken(tokenType);
    }

    fn matchIdentifier(self: Scanner, rest: []const u8, start: u8, length: u8, tokenType: TokenType) TokenType {
        if (self._currentChar - self._tokenStart == start + length and std.mem.eql(u8, self._tokenStart[start..length], rest)) {
            return tokenType;
        }
        return TokenType.IDENTIFIER;
    }
};

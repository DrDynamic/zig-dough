const dough = @import("dough");
const frontend = dough.frontend;

const Scanner = frontend.Scanner;
const Token = dough.frontend.Token;
const TokenType = dough.frontend.TokenType;

const ScannerReader = struct {
    scanner: Scanner,
    pub fn init(scanner: Scanner) ScannerReader {
        return .{ .scanner = scanner };
    }

    pub fn advance(self: *ScannerReader) void {
        var scanner = &self.scanner;

        while (true) {
            scanner.scanToken();
            if (scanner.current.token_type != TokenType.ScannerError) break;

            self.current_compiler.?.errAtCurrent("{?s}", .{scanner.current.lexeme});
        }
    }

    pub fn consume(self: *ScannerReader, token_type: TokenType, comptime message: []const u8, args: anytype) void {
        if (self.check(token_type)) {
            self.advance();
        } else {
            self.current_compiler.?.errAtCurrent(message, args);
        }
    }

    pub fn match(self: *ScannerReader, token_type: TokenType) bool {
        if (!self.check(token_type)) {
            return false;
        }
        self.advance();
        return true;
    }

    pub fn check(self: ScannerReader, token_type: TokenType) bool {
        return (self.scanner.current.token_type.? == token_type);
    }
};

pub const AstBuilder = struct {
    reader: ScannerReader = undefined,

    pub fn build(self: *AstBuilder, source: []const u8) !void {
        self.reader = ScannerReader.init(Scanner.init(source));

        while (!self.match(TokenType.Eof)) {
            self.declaration();
        }
    }

    fn declaration() void {}
};

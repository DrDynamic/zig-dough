pub const ErrorType = enum {
    // from Scanner
    unexpected_character,
    unterminated_string,

    // from Parser
    expected_identifier,

    // from SemanticAnalyzer
    incompatible_types,
};

const SourceLocation = struct {
    line: usize,
    column: usize,
    line_start: usize,
    line_end: usize,
};

pub const ErrorReporter = struct {
    source: []const u8,
    file_name: []const u8,

    pub fn init(source: []const u8, file_name: []const u8) ErrorReporter {
        return .{
            .source = source,
            .file_name = file_name,
        };
    }

    pub fn reportScannerError(self: *const ErrorReporter, err: Scanner.Error, token: Token) void {
        switch (err) {
            Scanner.Error.UnexpectedCharacter => self.reportByToken(token, .unexpected_character), // TODO token could not be parsed! Guess the token? or add a "undefined_token" type?
            Scanner.Error.UnterminatedString => self.reportByToken(token, .unterminated_string),
        }
    }

    pub fn reportByToken(self: *const ErrorReporter, token: Token, errorType: ErrorType) void {
        const location = self.calculateLocation(token.location.start);

        switch (errorType) {
            .unexpected_character => self.reportError(location, "unexpected character"),
            .unterminated_string => self.reportError(location, "unterminated string"),
            .expected_identifier => self.reportError(location, "expected an identifier"),
            .incompatible_types => self.reportError(location, "incompatiblwe types"),
        }
    }

    fn reportError(self: *const ErrorReporter, location: SourceLocation, message: []const u8) void {
        self.printError(location, message);
        self.printMarkedSource(location);
    }

    fn calculateLocation(self: *const ErrorReporter, token_position: usize) SourceLocation {
        var location = SourceLocation{
            .line = 1,
            .column = 1,
            .line_start = 0,
            .line_end = 0,
        };

        for (self.source, 0..) |char, index| {
            if (index == token_position) break;

            if (char == '\n') {
                location.line += 1;
                location.column = 1;
                location.line_start = index + 1;
            } else {
                location.column += 1;
            }
        }

        var end_index = token_position;
        while (end_index < self.source.len and self.source[end_index] != '\n' and self.source[end_index] != '\r') : (end_index += 1) {}
        location.line_end = end_index;

        return location;
    }

    fn printMarkedSource(self: *const ErrorReporter, location: SourceLocation) void {
        // print source
        const source_line = self.source[location.line_start..location.line_end];
        self.print("{s}\n", .{source_line});

        // print caret (^)
        for (0..location.column - 1) |_| self.print(" ", .{});
        self.print("{s}", .{"^"});
    }

    fn printError(self: *const ErrorReporter, location: SourceLocation, message: []const u8) void {
        self.print("{s}:{d}:{d}: {s}\n", .{ self.file_name, location.line, location.column, message });
    }

    fn print(_: *const ErrorReporter, comptime fmt: []const u8, args: anytype) void {
        // TODO switchout debug printer
        std.debug.print(fmt, args);
    }
};

const std = @import("std");
const as = @import("as");

const Scanner = as.frontend.Scanner;

const Token = as.frontend.Token;

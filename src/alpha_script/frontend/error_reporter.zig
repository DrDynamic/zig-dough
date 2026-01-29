pub const ErrorType = enum {
    // from Scanner
    unexpected_character,
    unterminated_string,

    // from Parser
    expected_identifier,

    // from SemanticAnalyzer
    incompatible_types,
};

const location_label_options: Terminal.PrintOptions = .{
    .styles = &.{Terminal.Style.bold},
};

const error_label_options: Terminal.PrintOptions = .{
    .color = .{ .ansi = .red },
    .styles = &.{.bold},
};

const marker_options: Terminal.PrintOptions = .{
    .color = .{ .ansi = .green },
};

const SourceLocation = struct {
    line: usize,
    column: usize,
    line_start: usize,
    line_end: usize,
};

pub const ErrorReporter = struct {
    terminal: *const Terminal,
    source: []const u8,
    file_name: []const u8,

    pub fn init(source: []const u8, file_name: []const u8, terminal: *const Terminal) ErrorReporter {
        return .{
            .terminal = terminal,
            .source = source,
            .file_name = file_name,
        };
    }

    pub fn reportScannerError(self: *const ErrorReporter, err: Scanner.Error, token_start: usize, token_end: usize) void {
        const location = self.calculateLocation(token_start);

        switch (err) {
            Scanner.Error.UnexpectedCharacter => self.printError(location, "unexpected character"),
            Scanner.Error.UnterminatedString => self.printError(location, "unterminated string"),
        }
        self.printMarkedSource(location, token_end - token_start);
    }

    pub fn reportByToken(self: *const ErrorReporter, token: Token, errorType: ErrorType) void {
        const location = self.calculateLocation(token.location.start);
        const width = token.location.end - token.location.start;
        switch (errorType) {
            .unexpected_character => self.reportError(location, width, "unexpected character"),
            .unterminated_string => self.reportError(location, width, "unterminated string"),
            .expected_identifier => self.reportError(location, width, "expected an identifier"),
            .incompatible_types => self.reportError(location, width, "incompatiblwe types"),
        }
    }

    fn reportError(self: *const ErrorReporter, location: SourceLocation, width: usize, message: []const u8) void {
        self.printError(location, message);
        self.printMarkedSource(location, width);
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

    fn printMarkedSource(self: *const ErrorReporter, location: SourceLocation, width: usize) void {
        // print source
        const source_line = self.source[location.line_start..location.line_end];
        self.print("{s}\n", .{source_line});

        // print marker (^~~~)
        self.terminal.setStyle(marker_options);
        for (0..location.column - 1) |_| self.print(" ", .{});
        self.print("{s}", .{"^"});
        for (0..width - 1) |_| self.print("~", .{});
        self.print("\n", .{});
        self.terminal.setStyle(Terminal.reset_options);
    }

    fn printError(self: *const ErrorReporter, location: SourceLocation, message: []const u8) void {
        self.terminal.setStyle(location_label_options);
        self.print("{s}:{d}:{d} ", .{ self.file_name, location.line, location.column });
        self.terminal.setStyle(error_label_options);
        self.print("error: ", .{});
        self.terminal.setStyle(location_label_options);
        self.print("{s}\n", .{message});
        self.terminal.setStyle(Terminal.reset_options);
    }

    fn print(self: *const ErrorReporter, comptime fmt: []const u8, args: anytype) void {
        self.terminal.print(fmt, args);
    }
};

const std = @import("std");
const as = @import("as");

const Terminal = as.common.Terminal;

const Scanner = as.frontend.Scanner;
const Token = as.frontend.Token;
const Node = as.frontend.Node;

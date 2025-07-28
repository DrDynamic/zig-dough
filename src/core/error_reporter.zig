const std = @import("std");

const core = @import("./core.zig");
const Token = core.token.Token;
const TokenType = core.token.TokenType;

pub fn compileError(token: *const Token, comptime message: []const u8, args: anytype) void {
    // TODO: find a more gracefull handling than 'catch return;' when error printing failes!

    if (token.token_type == TokenType.Error) {
        _printError(token, "Error", message, args) catch return;
    } else if (token.token_type == TokenType.Eof) {
        _printError(token, "Error at end", message, args) catch return;
    } else {
        const config = @import("../config.zig");
        const label = std.fmt.allocPrint(config.allocator, "Error at '{?s}' ", .{token.lexeme}) catch |allocErr| @errorName(allocErr);
        defer config.allocator.free(label);

        _printError(token, label, message, args) catch return;
    }
}

pub fn runtimeError() void {}

fn _printError(token: *const Token, label: []const u8, comptime message: []const u8, args: anytype) !void {
    const stdout_file = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stderr = bw.writer();

    try stderr.print("[line {d: >4}] {s}", .{ token.line, label });
    try stderr.print(message, args);
    try stderr.print("\n", .{});

    try bw.flush(); // Don't forget to flush!
}

const std = @import("std");

const core = @import("./core.zig");
const Token = core.token.Token;
const TokenType = core.token.TokenType;

const stdout_file = std.io.getStdErr().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stderr = bw.writer();

pub fn compileError(token: *const Token, comptime message: []const u8, args: anytype) void {
    // TODO: find a more gracefull handling than 'catch unreachable;' when error printing failes!

    if (token.token_type == TokenType.Error) {
        _printCompileError(token, "Error", message, args) catch unreachable;
    } else if (token.token_type == TokenType.Eof) {
        _printCompileError(token, "Error at end", message, args) catch unreachable;
    } else {
        const config = @import("../config.zig");
        const label = std.fmt.allocPrint(config.allocator, "Error at '{?s}' ", .{token.lexeme}) catch |allocErr| @errorName(allocErr);
        defer config.allocator.free(label);

        _printCompileError(token, label, message, args) catch unreachable;
    }
}

fn _printCompileError(token: *const Token, label: []const u8, comptime message: []const u8, args: anytype) !void {
    try stderr.print("[line {d: >4}] {s}", .{ token.line, label });
    try stderr.print(message, args);
    try stderr.print("\n", .{});

    try bw.flush(); // Don't forget to flush!
}

pub fn runtimeError(comptime format: []const u8, args: anytype, frames: []core.vm.CallFrame, frameCount: usize) void {
    stderr.print(format, args) catch unreachable;
    stderr.print("\n", .{}) catch unreachable;

    _printStacktrace(frames, frameCount);

    bw.flush() catch unreachable;
}

fn _printStacktrace(frames: []core.vm.CallFrame, frameCount: usize) void {
    var i = frameCount;

    while (i > 0) {
        i -= 1;

        const frame = frames[i];
        const function = frame.closure.function;
        const instruction = @intFromPtr(frame.ip) - @intFromPtr(function.chunk.code.items.ptr);

        stderr.print("[line {}] in ", .{function.chunk.lines.items[instruction]}) catch unreachable;

        if (function.name) |name| {
            stderr.print("{s}()\n", .{name}) catch unreachable;
        } else {
            stderr.print("script\n", .{}) catch unreachable;
        }
    }
}

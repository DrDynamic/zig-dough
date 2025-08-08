pub fn compileError(token: *const Token, comptime message: []const u8, args: anytype) void {
    console.outMutex.lock();
    defer console.outMutex.unlock();

    if (token.token_type == TokenType.Error) {
        console.printErrorUnflushed("[line {d}] Error: ", .{token.line});
        console.printErrorUnflushed(message, args);
        console.printErrorUnflushed("\n", .{});
    } else if (token.token_type == TokenType.Eof) {
        console.printErrorUnflushed("[line {d}] Error at end: ", .{token.line});
        console.printErrorUnflushed(message, args);
        console.printErrorUnflushed("\n", .{});
    } else {
        console.printErrorUnflushed("[line {d}] Error at '{?s}': ", .{ token.line, token.lexeme });
        console.printErrorUnflushed(message, args);
        console.printErrorUnflushed("\n", .{});
    }

    console.flushError();
}

pub fn runtimeError(comptime format: []const u8, args: anytype, frames: []dough.backend.CallFrame, frameCount: usize) void {
    console.printErrorUnflushed(format, args);
    console.printErrorUnflushed("\n", .{});

    // print stacktrace
    var i = frameCount;

    while (i > 0) {
        i -= 1;

        const frame = frames[i];
        const function = frame.closure.function;
        const instruction = @intFromPtr(frame.ip) - @intFromPtr(function.chunk.code.items.ptr);

        console.printErrorUnflushed("[line {}] in ", .{function.chunk.lines.items[instruction]});

        if (function.name) |name| {
            console.printErrorUnflushed("{s}()\n", .{name});
        } else {
            console.printErrorUnflushed("script\n", .{});
        }
    }

    console.flushError();
}

const console = @import("./console.zig");

const dough = @import("dough");

const Token = dough.frontend.Token;
const TokenType = dough.frontend.TokenType;

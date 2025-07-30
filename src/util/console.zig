const io = @import("std").io;

var outBuffer = io.bufferedWriter(io.getStdOut().writer());
var outWriter = outBuffer.writer();
pub var outMutex = @import("std").Thread.Mutex{};

var errBuffer = io.bufferedWriter(io.getStdErr().writer());
var errWriter = errBuffer.writer();
pub var errMutex = @import("std").Thread.Mutex{};

pub fn print(comptime format: []const u8, args: anytype) void {
    outMutex.lock();
    defer outMutex.unlock();

    outWriter.print(format, args) catch @panic("failed to write stdout!");
    outBuffer.flush() catch @panic("failed to flush stdout!");
}

pub fn println(comptime format: []const u8, args: anytype) void {
    outMutex.lock();
    defer outMutex.unlock();

    outWriter.print(format, args) catch @panic("failed to write stdout!");
    outWriter.print("\n", .{}) catch @panic("failed to write stdout!");

    outBuffer.flush() catch @panic("failed to flush stdout!");
}

pub fn printError(comptime format: []const u8, args: anytype) void {
    errMutex.lock();
    defer errMutex.unlock();

    errWriter.print(format, args) catch @panic("failed to write stderr!");
    errWriter.print("\n", .{}) catch @panic("failed to write stderr!");

    errBuffer.flush() catch @panic("failed to flush stderr!");
}

pub fn printErrorUnflushed(comptime format: []const u8, args: anytype) void {
    errWriter.print(format, args) catch @panic("failed to write stderr!");
}

pub fn flushError() void {
    errBuffer.flush() catch @panic("failed to flush stderr!");
}

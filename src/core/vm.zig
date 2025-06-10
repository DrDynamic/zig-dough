const std = @import("std");

const config = @import("../config.zig");
const core = @import("./core.zig");

const values = @import("../values/values.zig");
const Value = values.Value;
const DoughClosure = values.objects.DoughClosure;
const DoughExecutable = values.objects.DoughExecutable;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

pub const VirtualMachine = struct {
    executable: *DoughExecutable = undefined,

    pub fn init(_: *VirtualMachine) void {}

    pub fn deinit(_: *VirtualMachine) void {}

    pub fn execute(self: *VirtualMachine, executable: *DoughExecutable) void {
        self.executable = executable;
    }
    pub fn interpret(self: *VirtualMachine, source: []const u8) !void {
        var compiler = core.compiler.ModuleCompiler.init(source);
        var module = try compiler.compile();

        self.push(Value.fromObject(module.function.?.asObject()));
    }

    fn run(_: *VirtualMachine) void {}

    fn call(self: *VirtualMachine, closure: *DoughClosure, arg_count: u8) InterpretError!void {
        if (arg_count < closure.function.arity) {
            self.runtime_error("Expected {d} arguments but got {d}", .{ closure.function.arity, arg_count });
            return InterpretError.RuntimeError;
        }
    }

    fn runtime_error(self: *VirtualMachine, comptime format: []const u8, args: anytype) void {
        // TODO: put error printin (logging in general) else where and use it from here and from FunctionCompiler._print
        const stdout_file = std.io.getStdErr().writer();
        var bw = std.io.bufferedWriter(stdout_file);
        const stderr = bw.writer();

        stderr.print(format, args) catch unreachable;
        stderr.print("\n", .{}) catch unreachable;

        // TODO: Print stack trace

        bw.flush() catch unreachable;

        self.resetStack();
    }
};

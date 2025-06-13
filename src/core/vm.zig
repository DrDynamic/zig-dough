const std = @import("std");

const config = @import("../config.zig");
const core = @import("./core.zig");

const values = @import("../values/values.zig");
const Value = values.Value;
const DoughClosure = values.objects.DoughClosure;
const DoughExecutable = values.objects.DoughExecutable;
const DoughModule = values.objects.DoughModule;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

pub const VirtualMachine = struct {
    executable: *DoughModule = undefined,

    stack: [255]Value = undefined,
    stack_top: [*]Value = undefined,

    pub fn init(_: *VirtualMachine) void {}

    pub fn deinit(_: *VirtualMachine) void {}

    pub fn execute(self: *VirtualMachine, executable: *DoughModule) void {
        self.executable = executable;
    }
    pub fn interpret(self: *VirtualMachine, source: []const u8) !void {
        var compiler = core.compiler.ModuleCompiler.init(source);
        var module = try compiler.compile();

        self.push(Value.fromObject(module.function.?.asObject()));
    }

    pub fn push(self: *VirtualMachine, value: Value) void {
        self.stack_top[0] = value;
        self.stack_top += 1;
    }

    pub fn pop(self: *VirtualMachine) Value {
        self.stack_top -= 1;
        return self.stack_top[0];
    }

    fn resetStack(self: *DoughExecutable) void {
        self.stack_top = self.stack[0..];
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

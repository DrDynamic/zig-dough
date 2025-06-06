const std = @import("std");

const config = @import("../config.zig");
const core = @import("./core.zig");

const values = @import("../values/values.zig");
const Value = values.Value;
const DoughClosure = values.objects.DoughClosure;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

const CallFrame = struct {
    closure: *DoughClosure = undefined,
    ip: [*]u8 = undefined,
    slots: [*]Value = undefined,
};

pub const VirtualMachine = struct {
    // TODO: move execution (vars) to DoughModule (or even DoughAsync?)
    frames: []

    stack: [config.MAX_STACK_SIZE]Value = undefined,
    stack_top: [*]Value = undefined,

    pub fn init(self: *VirtualMachine) void {
        self.resetStack();
    }

    pub fn deinit(_: *VirtualMachine) void {}

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

    fn run(_: *VirtualMachine) void {}

    fn call(self: *VirtualMachine, closure: *DoughClosure, arg_count: u8) InterpretError!void {
        if (arg_count < closure.function.arity) {
            self.runtime_error("Expected {d} arguments but got {d}", .{ closure.function.arity, arg_count });
            return InterpretError.RuntimeError;
        }
    }

    fn resetStack(self: *VirtualMachine) void {
        self.stack_top = self.stack[0..];
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

const std = @import("std");

const config = @import("../config.zig");
const core = @import("./core.zig");

const values = @import("../values/values.zig");
const Value = values.Value;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

pub const VirtualMachine = struct {
    stack: [config.MAX_STACK_SIZE]Value = undefined,
    stack_top: [*]Value = undefined,
    pub fn init() VirtualMachine {
        return .{};
    }

    pub fn deinit(_: *VirtualMachine) void {}

    pub fn interpret(self: *VirtualMachine, source: []const u8) !void {
        var compiler = core.compiler.ModuleCompiler.init(source);
        var module = try compiler.compile();
    }

    pub fn push(self: *VirtualMachine, value: Value) void {
        self.stack_top[0] = value;
        self.stack_top += 1;
    }

    pub fn pop(self: *VirtualMachine) Value {
        self.stack_top -= 1;
        return self.stack_top[0];
    }

    fn resetStack(self: *VirtualMachine) void {
        self.stack_top = self.stack[0..];
    }
};

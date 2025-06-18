const std = @import("std");

const types = @import("../types.zig");
const config = @import("../config.zig");
const core = @import("./core.zig");

const SlotAddress = types.SlotAddress;
const OpCode = core.chunk.OpCode;

const values = @import("../values/values.zig");
const Value = values.Value;
const DoughClosure = values.objects.DoughClosure;
const DoughExecutable = values.objects.DoughExecutable;
const DoughModule = values.objects.DoughModule;

const FRAMES_MAX = 255;

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
    executable: *DoughModule = undefined,

    frames: []CallFrame = undefined,
    frame_count: usize = undefined,

    stack: []Value = undefined,
    stack_top: [*]Value = undefined,

    pub fn init(self: *VirtualMachine) !void {
        // TODO: make this more dynamic (maybe estimate size while compilation on fiunction level or someting)
        self.frames = try config.allocator.alloc(CallFrame, FRAMES_MAX);
        self.frame_count = 0;
        self.stack = try config.allocator.alloc(Value, 255);
        self.resetStack();
    }

    pub fn deinit(self: *VirtualMachine) void {
        config.allocator.free(self.frames);
        config.allocator.free(self.stack);
    }

    pub fn execute(self: *VirtualMachine, executable: *DoughModule) InterpretError!void {
        self.executable = executable;

        self.push(Value.fromObject(executable.function.asObject()));
        const closure = DoughClosure.init(executable.function) catch |err| {
            self.runtimeError("{s}", .{@errorName(err)});
            return InterpretError.RuntimeError;
        };
        _ = self.pop();

        self.push(Value.fromObject(closure.asObject()));

        try self.call(closure, 0);
        try self.run();
    }
    pub fn interpret(self: *VirtualMachine, source: []const u8) !void {
        var compiler = core.compiler.ModuleCompiler.init(source);
        var module = try compiler.compile();

        self.push(Value.fromObject(module.function.?.asObject()));
    }

    fn peek(self: *VirtualMachine, distance: usize) Value {
        return (self.stack_top - 1 - distance)[0];
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
        self.stack_top = self.stack[0..].ptr;
        self.frame_count = 0;
    }

    inline fn readByte(_: *VirtualMachine, frame: *CallFrame) u8 {
        const value: u8 = frame.ip[0];
        frame.ip += 1;
        return value;
    }

    inline fn readSlotAddress(_: *VirtualMachine, frame: *CallFrame) SlotAddress {
        const bytes: [3]u8 = frame.ip[1..4].*;
        frame.ip += 3;
        return @bitCast(bytes);
    }

    fn run(self: *VirtualMachine) !void {
        if (config.debug_trace_execution) {
            std.debug.print("\n", .{});
        }

        var frame: *CallFrame = &self.frames[self.frame_count];

        while (true) {
            if (config.debug_trace_execution) {
                std.debug.print("          ", .{});

                var val_ptr = self.stack[0..].ptr;
                if (@intFromPtr(val_ptr) >= @intFromPtr(self.stack_top)) {
                    std.debug.print("[]", .{});
                }
                while (@intFromPtr(val_ptr) < @intFromPtr(self.stack_top)) : (val_ptr += 1) {
                    std.debug.print("[ ", .{});
                    val_ptr[0].print();
                    std.debug.print(" ]", .{});
                }

                std.debug.print("\n", .{});

                const offset: usize = @intFromPtr(frame.ip) - @intFromPtr(frame.closure.function.chunk.code.items.ptr);
                _ = @import("debug.zig").disassemble_instruction(&frame.closure.function.chunk, &frame.closure.function.slots, offset);
            }

            const instruction: OpCode = @enumFromInt(self.readByte(frame));

            switch (instruction) {
                // Slot actions
                // is this even needed? DefineSlot,
                .GetSlot => {
                    const address = self.readSlotAddress(frame);
                    self.push(frame.slots[address]);
                },
                .SetSlot => {
                    // TODO: read an Address (u24)
                    const slot: usize = self.readSlotAddress(frame);
                    frame.slots[slot] = self.peek(0);
                },

                // Value interaction
                .Call => {
                    const argCount = self.readByte(frame);
                    try self.callValue(self.peek(argCount), argCount);
                },
                else => {},

                // Stack Actions
                //// Values
                //              PushNull, // push the value <null>
                //              PushUninitialized, // push the value <uninitialized>
                //               Pop, // pop a value

                //                Return

            }
        }
    }

    fn callValue(self: *VirtualMachine, callee: Value, argCount: u8) InterpretError!void {
        if (callee.isObject()) {
            const object = callee.toObject();
            switch (object.obj_type) {
                .Closure => {
                    try self.call(object.as(DoughClosure), argCount);
                },
                else => {
                    self.runtimeError("Can not call {?s}", .{std.enums.tagName(values.objects.ObjType, callee.toObject().obj_type)});
                    return InterpretError.RuntimeError;
                },
            }
        } else {
            self.runtimeError("Can not call Value", .{});
            return InterpretError.RuntimeError;
        }
    }

    fn call(self: *VirtualMachine, closure: *DoughClosure, arg_count: u8) InterpretError!void {
        if (arg_count < closure.function.arity) {
            self.runtimeError("Expected {d} arguments but got {d}", .{ closure.function.arity, arg_count });
            return InterpretError.RuntimeError;
        }

        if (self.frame_count >= FRAMES_MAX) {
            self.runtimeError("Stack overflow.", .{});
            return InterpretError.RuntimeError;
        }

        var frame: *CallFrame = &self.frames[self.frame_count];
        self.frame_count += 1;

        frame.closure = closure;
        frame.ip = closure.function.chunk.code.items.ptr;
        frame.slots = self.stack_top - arg_count - 1;
    }

    fn runtimeError(self: *VirtualMachine, comptime format: []const u8, args: anytype) void {
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

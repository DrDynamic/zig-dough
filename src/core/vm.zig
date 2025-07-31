const std = @import("std");

const types = @import("../types.zig");
const globals = @import("../globals.zig");
const config = @import("../config.zig");
const util = @import("../util/util.zig");
const core = @import("./core.zig");

const SlotAddress = types.SlotAddress;
const ConstantAddress = types.ConstantAddress;
const OpCode = core.chunk.OpCode;

const values = @import("../values/values.zig");
const Value = values.Value;

const objects = values.objects;
const DoughClosure = objects.DoughClosure;
const DoughExecutable = objects.DoughExecutable;
const DoughModule = objects.DoughModule;

const FRAMES_MAX = 255;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

pub const CallFrame = struct {
    closure: *DoughClosure = undefined,
    ip: [*]u8 = undefined,
    slots: [*]Value = undefined,
};

pub const VirtualMachine = struct {
    strings: std.StringHashMap(*objects.DoughString) = undefined,

    executable: *DoughModule = undefined,

    frames: []CallFrame = undefined,
    frame_count: usize = undefined,

    stack: []Value = undefined,
    stack_top: [*]Value = undefined,

    slots: std.ArrayList(Value) = undefined,

    pub fn init(self: *VirtualMachine) !void {
        self.strings = std.StringHashMap(*objects.DoughString).init(globals.allocator);

        // TODO: make this more dynamic (maybe estimate size while compilation on function level or someting)
        self.frames = try globals.allocator.alloc(CallFrame, FRAMES_MAX);
        self.frame_count = 0;
        self.stack = try globals.allocator.alloc(Value, 255);
        self.slots = std.ArrayList(Value).init(globals.allocator);

        self.resetStack();
    }

    pub fn deinit(self: *VirtualMachine) void {
        self.strings.deinit();

        globals.allocator.free(self.frames);
        globals.allocator.free(self.stack);
    }

    pub fn execute(self: *VirtualMachine, executable: *DoughModule) !void {
        self.executable = executable;

        self.push(Value.fromObject(executable.function.asObject()));
        const closure = DoughClosure.init(executable.function);
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
        self.slots.clearAndFree();
    }

    inline fn readByte(_: *VirtualMachine, frame: *CallFrame) u8 {
        const value: u8 = frame.ip[0];
        frame.ip += 1;
        return value;
    }
    inline fn readConstantAddress(_: *VirtualMachine, frame: *CallFrame) ConstantAddress {
        const bytes: [3]u8 = frame.ip[0..3].*;
        frame.ip += 3;
        return @bitCast(bytes);
    }
    inline fn readSlotAddress(_: *VirtualMachine, frame: *CallFrame) SlotAddress {
        const bytes: [3]u8 = frame.ip[0..3].*;
        frame.ip += 3;
        return @bitCast(bytes);
    }

    fn run(self: *VirtualMachine) !void {
        if (config.debug_trace_execution) {
            std.debug.print("\n", .{});
        }

        var frame: *CallFrame = &self.frames[self.frame_count - 1];

        while (true) {
            if (config.debug_trace_execution) {
                std.debug.print("          ", .{});

                var val_ptr = self.stack[0..].ptr;
                if (@intFromPtr(val_ptr) >= @intFromPtr(self.stack_top)) {
                    std.debug.print("[]", .{});
                }
                while (@intFromPtr(val_ptr) < @intFromPtr(self.stack_top)) : (val_ptr += 1) {
                    if (val_ptr == frame.slots) {
                        std.debug.print("|", .{});
                    }
                    const string = val_ptr[0].toString();
                    std.debug.print("[{s}] ", .{string.bytes});
                }

                std.debug.print("\n", .{});

                const offset: usize = @intFromPtr(frame.ip) - @intFromPtr(frame.closure.function.chunk.code.items.ptr);
                _ = @import("debug.zig").disassemble_instruction(&frame.closure.function.chunk, &frame.closure.function.slots, offset);
            }

            const instruction: OpCode = @enumFromInt(self.readByte(frame));

            switch (instruction) {
                // Slot actions
                .DefineSlot => {
                    const address = self.readSlotAddress(frame);
                    while (address >= self.slots.items.len) {
                        try self.slots.append(Value.makeUninitialized());
                    }
                    self.slots.items[address] = self.peek(0);
                    _ = self.pop();
                },
                .GetSlot => {
                    const address = self.readSlotAddress(frame);

                    if (Value.isUninitialized(frame.slots[address])) {
                        self.runtimeError("cannot access uninitialized variable", .{});
                        return InterpretError.RuntimeError;
                    }

                    self.push(frame.slots[address]);
                },
                .SetSlot => {
                    const slot = self.readSlotAddress(frame);
                    frame.slots[slot] = self.peek(0);
                },
                .GetConstant => {
                    const address = self.readConstantAddress(frame);
                    const val = frame.closure.function.chunk.constants.items[address];
                    self.push(val);
                },
                // Value interaction
                .Call => {
                    const argCount = self.readByte(frame);
                    try self.callValue(self.peek(argCount), argCount);
                },

                // Math
                .Add => {
                    if (self.peek(0).isString() and self.peek(1).isString()) {
                        // don't let the garbage collector grab this stings!
                        const str2 = self.peek(0).toObject().as(objects.DoughString).bytes;
                        const str1 = self.peek(1).toObject().as(objects.DoughString).bytes;

                        var result = globals.allocator.alloc(u8, str1.len + str2.len) catch {
                            @panic("failed to concatinate strings!");
                        };

                        @memcpy(result[0..str1.len], str1);
                        @memcpy(result[str1.len..], str2);

                        // now the gabage collect can have them...
                        _ = self.pop();
                        _ = self.pop();

                        const dstring = objects.DoughString.init(result);
                        self.push(Value.fromObject(dstring.asObject()));
                    } else if (self.peek(0).isNumber() and self.peek(1).isNumber()) {
                        const num2 = self.pop().toNumber();
                        const num1 = self.pop().toNumber();

                        self.push(Value.fromNumber(num1 + num2));
                    } else {
                        // TODO: show types instead of values (e.g. 13 + "37" leads to iretating error)
                        self.runtimeError("Unsupported operand types: {s} + {s} (must both be numbers of strings)", .{ self.peek(1).toString().bytes, self.peek(0).toString().bytes });
                        return InterpretError.RuntimeError;
                    }
                },
                .Subtract => {
                    if (self.peek(0).isNumber() and self.peek(1).isNumber()) {
                        const num2 = self.pop().toNumber();
                        const num1 = self.pop().toNumber();

                        self.push(Value.fromNumber(num1 - num2));
                    } else {
                        // TODO: show types instead of values (e.g. 13 - "37" leads to iretating error)
                        self.runtimeError("Unsupported operand types: {s} - {s} (must be numbers)", .{ self.peek(1).toString().bytes, self.peek(0).toString().bytes });
                        return InterpretError.RuntimeError;
                    }
                },
                .Multiply => {
                    if (self.peek(0).isNumber() and self.peek(1).isNumber()) {
                        const num2 = self.pop().toNumber();
                        const num1 = self.pop().toNumber();

                        self.push(Value.fromNumber(num1 * num2));
                    } else {
                        // TODO: show types instead of values (e.g. 13 * "37" leads to iretating error)
                        self.runtimeError("Unsupported operand types: {s} * {s} (must be numbers)", .{ self.peek(1).toString().bytes, self.peek(0).toString().bytes });
                        return InterpretError.RuntimeError;
                    }
                },
                .Divide => {
                    if (self.peek(0).isNumber() and self.peek(1).isNumber()) {
                        const num2 = self.pop().toNumber();
                        const num1 = self.pop().toNumber();

                        self.push(Value.fromNumber(num1 / num2));
                    } else {
                        // TODO: show types instead of values (e.g. 13 / "37" leads to iretating error)
                        self.runtimeError("Unsupported operand types: {s} / {s} (must be numbers)", .{ self.peek(1).toString().bytes, self.peek(0).toString().bytes });
                        return InterpretError.RuntimeError;
                    }
                },

                // Stack Actions
                //// Values
                .PushNull => {
                    self.push(Value.makeNull());
                },
                .PushUninitialized => {
                    //self.push(Value.fromNumber(13.37));
                    self.push(Value.makeUninitialized());
                },
                .Pop => {
                    _ = self.pop();
                },

                .Return => {
                    if (self.frame_count == 1) {
                        _ = self.pop();
                        return;
                    }
                    return InterpretError.RuntimeError;
                },
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
                .NativeFunction => {
                    const native = object.as(objects.DoughNativeFunction);

                    const args_start = self.stack_top - argCount;
                    const result: Value = native.function(argCount, args_start[0..argCount]);
                    self.stack_top -= argCount + 1;
                    self.push(result);
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
        util.errorReporter.runtimeError(format, args, self.frames, self.frame_count);
        self.resetStack();
    }
};

const std = @import("std");

const types = @import("../types.zig");

const dough = @import("dough");

const config = dough.config;

const SlotAddress = types.SlotAddress;
const ConstantAddress = types.ConstantAddress;
const OpCode = dough.backend.OpCode;

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
    executable: *DoughModule = undefined,

    frames: []CallFrame = undefined,
    frame_count: usize = undefined,

    stack: []Value = undefined,
    stack_top: [*]Value = undefined,

    slots: std.ArrayList(Value) = undefined,

    pub fn init(self: *VirtualMachine) !void {
        // TODO: make this more dynamic (maybe estimate size while compilation on function level or someting)
        self.frames = try dough.allocator.alloc(CallFrame, FRAMES_MAX);
        self.frame_count = 0;
        self.stack = try dough.allocator.alloc(Value, 255);
        self.slots = std.ArrayList(Value).init(dough.allocator);

        self.resetStack();
    }

    pub fn deinit(self: *VirtualMachine) void {
        dough.allocator.free(self.frames);
        dough.allocator.free(self.stack);

        self.slots.deinit();
    }

    pub fn execute(self: *VirtualMachine, executable: *DoughModule) !void {
        self.executable = executable;

        self.push(Value.fromObject(executable.function.asObject()));
        const closure = DoughClosure.init(executable.function);
        _ = self.pop();

        self.push(Value.fromObject(closure.asObject()));

        try self.call(closure, 0);
        try self.run();

        _ = self.pop();
    }
    pub fn interpret(self: *VirtualMachine, source: []const u8) !void {
        var compiler = dough.frontend.compiler.ModuleCompiler.init(source);
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

    inline fn readJumpOffset(_: *VirtualMachine, frame: *CallFrame) u16 {
        const bytes: [2]u8 = frame.ip[0..2].*;
        frame.ip += 2;
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
                    std.debug.print("[{}] ", .{val_ptr[0]});
                }

                std.debug.print("\n", .{});

                const offset: usize = @intFromPtr(frame.ip) - @intFromPtr(frame.closure.function.chunk.code.items.ptr);
                _ = @import("debug.zig").disassemble_instruction(&frame.closure.function.chunk, offset);
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

                .LogicalNot => self.push(Value.fromBoolean(self.pop().isFalsey())),
                .Negate => {
                    const negated = -self.pop().toNumber();
                    self.push(Value.fromNumber(negated));
                },

                .Equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.fromBoolean(a.equals(b)));
                },
                .NotEqual => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.fromBoolean(!a.equals(b)));
                },
                .Greater => {
                    const num2 = self.pop().toNumber();
                    const num1 = self.pop().toNumber();

                    self.push(Value.fromBoolean(num1 > num2));
                },
                .GreaterEqual => {
                    const num2 = self.pop().toNumber();
                    const num1 = self.pop().toNumber();

                    self.push(Value.fromBoolean(num1 >= num2));
                },
                .Less => {
                    const num2 = self.pop().toNumber();
                    const num1 = self.pop().toNumber();

                    self.push(Value.fromBoolean(num1 < num2));
                },
                .LessEqual => {
                    const num2 = self.pop().toNumber();
                    const num1 = self.pop().toNumber();

                    self.push(Value.fromBoolean(num1 <= num2));
                },

                .Add => {
                    // TODO: put string concat in separate opcode
                    if (self.peek(0).isString() and self.peek(1).isString()) {
                        // don't let the garbage collector grab this stings!
                        const str2 = self.peek(0).toObject().as(objects.DoughString).bytes;
                        const str1 = self.peek(1).toObject().as(objects.DoughString).bytes;

                        var result = dough.allocator.alloc(u8, str1.len + str2.len) catch {
                            @panic("failed to concatinate strings!");
                        };

                        @memcpy(result[0..str1.len], str1);
                        @memcpy(result[str1.len..], str2);

                        // now the gabage collect can have them...
                        _ = self.pop();
                        _ = self.pop();

                        const dstring = objects.DoughString.init(result);
                        self.push(Value.fromObject(dstring.asObject()));
                    } else {
                        const num2 = self.pop().toNumber();
                        const num1 = self.pop().toNumber();

                        self.push(Value.fromNumber(num1 + num2));
                    }
                },
                .Subtract => {
                    const num2 = self.pop().toNumber();
                    const num1 = self.pop().toNumber();

                    self.push(Value.fromNumber(num1 - num2));
                },
                .Multiply => {
                    const num2 = self.pop().toNumber();
                    const num1 = self.pop().toNumber();

                    self.push(Value.fromNumber(num1 * num2));
                },
                .Divide => {
                    const num2 = self.pop().toNumber();
                    const num1 = self.pop().toNumber();

                    self.push(Value.fromNumber(num1 / num2));
                },

                // Jumps
                .Jump => {
                    const offset = self.readJumpOffset(frame);
                    frame.ip += offset;
                },
                .JumpIfTrue => {
                    const offset = self.readJumpOffset(frame);
                    if (!self.peek(0).isFalsey()) {
                        frame.ip += offset;
                    }
                },
                .JumpIfFalse => {
                    const offset = self.readJumpOffset(frame);

                    if (self.peek(0).isFalsey()) {
                        frame.ip += offset;
                    }
                },

                // Stack Actions
                //// literals
                .PushNull => {
                    self.push(Value.makeNull());
                },
                .PushTrue => {
                    self.push(Value.fromBoolean(true));
                },
                .PushFalse => {
                    self.push(Value.fromBoolean(false));
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
                        self.frame_count = 0;
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
        // TODO: use DWARF standard for debugging informations (https://dwarfstd.org/)
        config.io_config.runtimeErrorReporter(format, args, self.frames, self.frame_count);
        self.resetStack();
    }
};

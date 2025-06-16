const std = @import("std");

const config = @import("../config.zig");
const core = @import("./core.zig");

const OpCode = core.chunk.OpCode;

const values = @import("../values/values.zig");
const Value = values.Value;
const DoughClosure = values.objects.DoughClosure;
const DoughExecutable = values.objects.DoughExecutable;
const DoughModule = values.objects.DoughModule;

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

const CallFrame = struct {
    closure: *Closure = undefined,
    ip: [*]u8 = undefined,
    slots: [*]Value = undefined,
};

pub const VirtualMachine = struct {
    executable: *DoughModule = undefined,

    frames: []CallFrame = undefined,
    frame_count: usize = undefined,

    stack: []Value = undefined,
    stack_top: [*]Value = undefined,

    pub fn init(self: *VirtualMachine) void {
        // TODO: make this more dynamic (maybe estimate size while compilation on fiunction level or someting)
        self.frames = config.allocator.create([255]CallFrame);
        self.frame_count = 0;
        self.stack = config.allocator.create([255]Value);
        self.resetStack();
    }

    pub fn deinit(_: *VirtualMachine) void {}

    pub fn execute(self: *VirtualMachine, executable: *DoughModule) void {
        self.executable = executable;

        self.push(Value.fromObject(executable.function.asObject()));
        const closure = DoughClosure.init(executable.function);
        _ = self.pop();

        self.push(Value.fromObject(closure.asObject()));

        self.call(closure, 0);
        self.run();
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

    fn resetStack(self: *VirtualMachine) void {
        self.stack_top = self.stack[0..];
        self.frame_count = 0;
    }

    inline fn read_byte(self: *VirtualMachine, frame: *CallFrame) u8 {
        _ = self;

        // ip is a many-item pointer.
        // The first element points to start of the slice.
        const value: u8 = frame.ip[0];
        // Pointer arithmetic below. We advance the ip to the pointer of the next
        // element in the slice.
        frame.ip += 1;
        return value;
    }

    fn run(self: *VirtualMachine) void {
        if (config.debug_trace_execution) {
            std.debug.print("\n", .{});
        }

        var frame: *CallFrame = &self.frames[self.frame_count];

        while (true) {
            if (config.debug_trace_execution) {
                std.debug.print("          ", .{});

                var val_ptr = self.stack[0..].ptr;
                while (@intFromPtr(val_ptr) < @intFromPtr(self.stack_top)) : (val_ptr += 1) {
                    std.debug.print("[ ", .{});
                    val_ptr[0].print();
                    std.debug.print(" ]", .{});
                }

                std.debug.print("\n", .{});

                const offset: usize = @intFromPtr(frame.ip) - @intFromPtr(frame.closure.function.chunk.code.items.ptr);
                _ = @import("debug.zig").disassemble_instruction(&frame.closure.function.chunk, &frame.closure.function.slots, offset);
            }

            const instruction: OpCode = @enumFromInt(self.read_byte());
            
            switch (instruction) {
                // Slot actions
                // is this even needed? DefineSlot,
                GetSlot => {


},
                
                SetSlot => {
    // TODO: read an Address (u24)
    const slot:usize = @intCast(self.readByte(frame));
    frame.slots[slot] = self.peek(0);
},
            
                // Value interaction
                Call,
            
                // Stack Actions
                //// Values
                PushNull, // push the value <null>
                PushUninitialized, // push the value <uninitialized>
                Pop, // pop a value
            
                Return,

            }
        }
    }

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

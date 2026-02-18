const FRAMES_MAX = 128;
const STACK_MAX = FRAMES_MAX * 256;

pub const CallFrame = struct {
    function: *ObjFunction,
    ip: usize,
    base_pointer: usize,
};

pub const VirtualMachine = struct {
    pub const Error = error{
        ArgumentCount,
        StackOverflow,
    };

    frames: [FRAMES_MAX]CallFrame,
    frame_count: usize,

    stack: [STACK_MAX]Value,
    stack_top: usize,

    allocator: std.mem.Allocator,
    garbage_collector: *GarbageCollector,
    error_reporter: *const ErrorReporter,

    current_chunk: *const Chunk,
    current_ip: usize,
    current_base: usize,

    pub fn init(error_reporter: *const ErrorReporter, garbage_collector: *GarbageCollector, allocator: std.mem.Allocator) VirtualMachine {
        return .{
            .frames = undefined,
            .frame_count = 0,
            .stack = undefined,
            .stack_top = 1,
            .allocator = allocator,
            .garbage_collector = garbage_collector,
            .error_reporter = error_reporter,
            .current_chunk = undefined,
            .current_ip = 0,
            .current_base = 0,
        };
    }

    pub fn execute(self: *VirtualMachine, module: *const ObjModule) !void {
        self.current_chunk = &module.function.chunk;
        self.current_ip = 0;
        self.current_base = 0;

        try self.call(module.function, 0);
        try self.run();
    }

    fn run(self: *VirtualMachine) !void {
        const debug = false;

        var ip = self.current_ip;
        const chunk = self.current_chunk;
        const code = chunk.code.items;
        var stack = &self.stack;
        const base = self.current_base;

        const terminal = as.common.Terminal.init(std.io.getStdOut());
        const disassambler = as.frontend.debug.Disassambler.init(&terminal);
        if (debug) {
            for (1..255) |index| {
                stack[index] = Value.makeUninitialized();
            }
            terminal.print("== EXEC == \n", .{});
        }

        while (true) {
            if (ip >= code.len) return;
            const instruction = code[ip];
            ip += 1;

            if (debug) {
                for (stack, 0..) |register, index| {
                    terminal.printWithOptions("[{d:0>2} ", .{index}, .{});
                    terminal.printWithOptions("{} ", .{register}, .{ .styles = &.{.faint} });
                    terminal.printWithOptions("] ", .{}, .{});
                    if (index > 8) break;
                }
                terminal.print("\n", .{});
                disassambler.disassambleInstruction(chunk, instruction, ip);
            }

            switch (instruction.abc.opcode) {
                .load_const => {
                    const reg_dest = base + instruction.ab.a;
                    const constant_id = instruction.ab.b;
                    stack[reg_dest] = chunk.constants.items[constant_id];
                },
                .move => {
                    const reg_dest = base + instruction.abc.a;
                    const reg_src = base + instruction.abc.b;
                    stack[reg_dest] = stack[reg_src];
                },
                // math
                .add => try self.numericMath(instruction, MathOps.add),
                .sub => try self.numericMath(instruction, MathOps.sub),
                .multiply => try self.numericMath(instruction, MathOps.mul),
                .divide => {
                    const reg_a = base + instruction.abc.a;
                    const val_b = stack[base + instruction.abc.b];
                    const val_c = stack[base + instruction.abc.c];

                    const float_b = val_b.castToF64() catch 0;
                    const float_c = val_c.castToF64() catch 0;

                    const result = float_b / float_c;
                    if (val_b.isInteger() and val_c.isInteger() and result == @floor(result)) {
                        stack[reg_a] = Value.makeInteger(@intFromFloat(result));
                    } else {
                        stack[reg_a] = Value.makeFloat(result);
                    }
                },
                // compare
                .equal => {
                    const reg_a = base + instruction.abc.a;
                    const val_b = stack[base + instruction.abc.b];
                    const val_c = stack[base + instruction.abc.c];

                    stack[reg_a] = Value.makeBool(val_b.equals(val_c));
                },
                .not_equal => {
                    const reg_a = base + instruction.abc.a;
                    const val_b = stack[base + instruction.abc.b];
                    const val_c = stack[base + instruction.abc.c];

                    stack[reg_a] = Value.makeBool(!val_b.equals(val_c));
                },
                .greater => {
                    const reg_a = base + instruction.abc.a;
                    const float_b = try stack[base + instruction.abc.b].castToF64();
                    const float_c = try stack[base + instruction.abc.c].castToF64();

                    stack[reg_a] = Value.makeBool(float_b > float_c);
                },
                .greater_equal => {
                    const reg_a = base + instruction.abc.a;
                    const float_b = try stack[base + instruction.abc.b].castToF64();
                    const float_c = try stack[base + instruction.abc.c].castToF64();

                    stack[reg_a] = Value.makeBool(float_b >= float_c);
                },
                .less => {
                    const reg_a = base + instruction.abc.a;
                    const float_b = try stack[base + instruction.abc.b].castToF64();
                    const float_c = try stack[base + instruction.abc.c].castToF64();

                    stack[reg_a] = Value.makeBool(float_b < float_c);
                },
                .less_equal => {
                    const reg_a = base + instruction.abc.a;
                    const float_b = try stack[base + instruction.abc.b].castToF64();
                    const float_c = try stack[base + instruction.abc.c].castToF64();

                    stack[reg_a] = Value.makeBool(float_b <= float_c);
                },
                // interaction
                .call => {
                    const reg_dest = base + instruction.abc.a;
                    const reg_callee = base + instruction.abc.b;
                    const arg_count = instruction.abc.c;

                    const callee = stack[reg_callee];

                    if (callee.isObject()) {
                        switch (callee.object.tag) {
                            .native_function => {
                                const native = callee.object.as(values.ObjNative);

                                const reg_args_start = reg_callee + 1;
                                const args = stack[reg_args_start .. reg_args_start + arg_count];

                                const result = native.function(args);
                                stack[reg_dest] = result;
                            },

                            else => unreachable,
                        }
                    }
                },

                .call_return => {
                    if (self.frame_count == 1) {
                        // return from main module
                        self.stack_top = 0;
                        self.frame_count = 0;
                        return;
                    }
                    // TODO return from a function -> restore stack top, decrement frame_count, etc.
                    unreachable;
                },
            }
        }
    }

    inline fn call(self: *VirtualMachine, function: *ObjFunction, arg_count: u8) Error!void {
        if (arg_count < function.arity) {
            const error_string = std.fmt.allocPrint(self.allocator, "Expected {d} arguments but got {d}", .{ function.arity, arg_count }) catch {
                @panic("Allocation failed!");
            };
            defer self.allocator.free(error_string);
            self.error_reporter.virtualMachineError(self, Error.ArgumentCount, error_string);

            return Error.ArgumentCount;
        }

        if (self.frame_count >= FRAMES_MAX) {
            self.error_reporter.virtualMachineError(self, Error.StackOverflow, "Stack overflow");
            return Error.StackOverflow;
        }

        var frame: *CallFrame = &self.frames[self.frame_count];
        self.frame_count += 1;

        frame.function = function;
        frame.ip = 0;
        frame.base_pointer = self.stack_top - arg_count - 1;

        var index = self.stack_top;
        while (index < self.stack_top + function.max_registers) : (index += 1) {
            self.stack[index] = Value.makeUninitialized();
        }

        self.stack_top = self.stack_top + function.max_registers;
    }

    const MathOps = struct {
        fn add(comptime T: type, a: T, b: T) T {
            return a + b;
        }
        fn sub(comptime T: type, a: T, b: T) T {
            return a - b;
        }
        fn mul(comptime T: type, a: T, b: T) T {
            return a * b;
        }
    };

    inline fn numericMath(self: *VirtualMachine, instruction: Instruction, comptime op: anytype) !void {
        const base = self.current_base;
        const reg_a = base + instruction.abc.a;
        const val_b = self.stack[base + instruction.abc.b];
        const val_c = self.stack[base + instruction.abc.c];

        if (val_b.isInteger() and val_c.isInteger()) {
            const res = op(i64, val_b.toI64(), val_c.toI64());
            self.stack[reg_a] = Value.makeInteger(res);
        } else {
            const float_b = try val_b.castToF64();
            const float_c = try val_c.castToF64();
            const res = op(f64, float_b, float_c);
            self.stack[reg_a] = Value.makeFloat(res);
        }
    }
};

const std = @import("std");
const as = @import("as");
const values = as.runtime.values;

const Chunk = as.compiler.Chunk;
const ErrorReporter = as.common.reporting.ErrorReporter;
const GarbageCollector = as.common.memory.GarbageCollector;
const Instruction = as.compiler.Instruction;
const ObjFunction = as.runtime.values.ObjFunction;
const ObjModule = as.runtime.values.ObjModule;
const Value = as.runtime.values.Value;

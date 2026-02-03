const FRAMES_MAX = 128;
const STACK_MAX = FRAMES_MAX * 1024;

pub const CallFrame = struct {
    chunk: *const Chunk,
    ip: usize,
    base_pointer: usize,
};

pub const VirtualMachine = struct {
    frames: [FRAMES_MAX]CallFrame,
    frame_count: usize,

    stack: [STACK_MAX]Value,

    allocator: std.mem.Allocator,

    current_chunk: *const Chunk,
    current_ip: usize,
    current_base: usize,

    pub fn init(allocator: std.mem.Allocator) VirtualMachine {
        return .{
            .frames = undefined,
            .frame_count = 0,
            .stack = undefined,
            .allocator = allocator,
            .current_chunk = undefined,
            .current_ip = 0,
            .current_base = 0,
        };
    }

    pub fn execute(self: *VirtualMachine, chunk: *const Chunk) !void {
        self.current_chunk = chunk;
        self.current_ip = 0;
        self.current_base = 0;

        try self.run();
    }

    fn run(self: *VirtualMachine) !void {
        var ip = self.current_ip;
        const chunk = self.current_chunk;
        const code = chunk.code.items;
        var stack = &self.stack;
        const base = self.current_base;

        while (true) {
            if (ip >= code.len) return;
            const instruction = code[ip];
            ip += 1;

            switch (instruction.abc.opcode) {
                .load_const => {
                    const reg_dest = base + instruction.ab.a;
                    const constant_id = instruction.ab.b;
                    stack[reg_dest] = chunk.constants.items[constant_id];
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

                //debug
                .stack_return => {
                    const val_a = self.stack[base + instruction.ab.a];
                    std.debug.print("debug: {}\n", .{val_a});
                },
            }
        }
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
const Instruction = as.compiler.Instruction;
const Value = as.runtime.values.Value;

const value_options: Terminal.PrintOptions = .{
    .styles = &.{.faint},
};

pub const InstructionType = enum {
    ab,
    abc,
};

pub const ParameterType = enum {
    mutate_register_id,
    register_id,
    constant_id,
    argument_id,
    upvalue_id,
    code_offset,
    number,
    unused,
};

pub const InstructionDescription = struct {
    instruction_type: InstructionType,

    parameter_type_a: ParameterType,
    parameter_type_b: ParameterType,
    parameter_type_c: ParameterType,
};

pub const Disassambler = struct {
    terminal: *Terminal,

    pub fn init(terminal: *Terminal) Disassambler {
        return .{
            .terminal = terminal,
        };
    }

    pub fn disassambleChunk(self: *Disassambler, chunk: *const Chunk, name: []const u8) void {
        self.terminal.print("===== {s} =====\n", .{name});
        for (chunk.code.items, 0..) |instruction, index| {
            _ = self.disassambleInstruction(chunk, instruction, index);
        }
    }

    pub fn disassambleInstruction(self: *Disassambler, chunk: *const Chunk, instruction: Instruction, offset: usize) InstructionDescription {
        self.terminal.print("{d:0>4} ", .{offset});

        const op = instruction.abc.opcode;

        switch (op) {
            .load_const => {
                const dest_reg = instruction.ab.a;
                const constant_id = instruction.ab.b;
                const value = chunk.constants.items[constant_id];

                self.terminal.print("{s:<16} R{d:<2}, C{d:<3}    ; ", .{ @tagName(op), dest_reg, constant_id });
                self.terminal.printWithOptions("{f}", .{value}, value_options);
                self.terminal.print("\n", .{});

                return .{
                    .instruction_type = .ab,
                    .parameter_type_a = .mutate_register_id,
                    .parameter_type_b = .constant_id,
                    .parameter_type_c = .unused,
                };
            },
            .move => {
                self.terminal.print("{s:<16} R{d:<2}, R{d:<2}     ;\n", .{
                    @tagName(instruction.abc.opcode),
                    instruction.abc.a,
                    instruction.abc.b,
                });

                return .{
                    .instruction_type = .abc,
                    .parameter_type_a = .mutate_register_id,
                    .parameter_type_b = .register_id,
                    .parameter_type_c = .unused,
                };
            },
            // math
            .add,
            .sub,
            .multiply,
            .divide,
            .negate,
            // compare
            .equal,
            .not_equal,
            .greater,
            .greater_equal,
            .less,
            .less_equal,
            .logical_not,
            //string
            .string_concat,
            => return self.printABCMutate(instruction),
            // interaction
            .load_upvalue => {
                self.terminal.print("{s:<16} R{d:<2}, U{d:<2},    ;\n", .{
                    @tagName(instruction.abc.opcode),
                    instruction.abc.a,
                    instruction.abc.b,
                });

                return .{
                    .instruction_type = .abc,
                    .parameter_type_a = .mutate_register_id,
                    .parameter_type_b = .upvalue_id,
                    .parameter_type_c = .unused,
                };
            },
            .store_upvalue => {
                self.terminal.print("{s:<16} U{d:<2}, R{d:<2},   ;\n", .{
                    @tagName(instruction.abc.opcode),
                    instruction.abc.a,
                    instruction.abc.b,
                });

                return .{
                    .instruction_type = .abc,
                    .parameter_type_a = .upvalue_id,
                    .parameter_type_b = .register_id,
                    .parameter_type_c = .unused,
                };
            },
            .create_closure => {
                self.terminal.print("{s:<16} R{d:<2}, C{d:<2},    ;\n", .{
                    @tagName(instruction.abc.opcode),
                    instruction.ab.a,
                    instruction.ab.b,
                });

                return .{
                    .instruction_type = .ab,
                    .parameter_type_a = .mutate_register_id,
                    .parameter_type_b = .constant_id,
                    .parameter_type_c = .unused,
                };
            },
            .close_upvalue => {
                self.terminal.print("{s:<16}    , R{d:<2},    ;\n", .{
                    @tagName(instruction.abc.opcode),
                    instruction.abc.b,
                });

                return .{
                    .instruction_type = .abc,
                    .parameter_type_a = .unused,
                    .parameter_type_b = .register_id,
                    .parameter_type_c = .unused,
                };
            },
            .op_call => return self.printCall(instruction),
            .op_call_args => {
                self.terminal.print("{s:<16}  {d:<2}, A{d:<3}    ; ", .{
                    @tagName(op),
                    instruction.ab.a,
                    instruction.ab.b,
                });

                self.terminal.printWithOptions("ARGS_COUNT ARGS_START", .{}, value_options);
                self.terminal.print("\n", .{});

                return .{
                    .instruction_type = .ab,
                    .parameter_type_a = .number,
                    .parameter_type_b = .argument_id,
                    .parameter_type_c = .unused,
                };
            },
            .call_return => {
                self.terminal.print("{s:<16}    , R{d:<2}\n", .{
                    @tagName(instruction.abc.opcode),
                    instruction.abc.b,
                });

                return .{
                    .instruction_type = .abc,
                    .parameter_type_a = .unused,
                    .parameter_type_b = .register_id,
                    .parameter_type_c = .unused,
                };
            },
            // controlflow
            .jump => {
                self.terminal.print(
                    "{s:<16}    , +{d:<3}    ; ",
                    .{
                        @tagName(instruction.ab.opcode),
                        instruction.ab.b,
                    },
                );
                self.terminal.printWithOptions("#{d:0>4}", .{instruction.ab.b + offset}, value_options);
                self.terminal.print("\n", .{});

                return .{
                    .instruction_type = .ab,
                    .parameter_type_a = .unused,
                    .parameter_type_b = .code_offset,
                    .parameter_type_c = .unused,
                };
            },
            .jump_if_false,
            .jump_if_true,
            => {
                self.terminal.print(
                    "{s:<16} R{d:<2}, +{d:<3}    ; ",
                    .{
                        @tagName(instruction.ab.opcode),
                        instruction.ab.a,
                        instruction.ab.b,
                    },
                );
                self.terminal.printWithOptions("#{d:0>4}", .{instruction.ab.b + offset}, value_options);
                self.terminal.print("\n", .{});

                return .{
                    .instruction_type = .ab,
                    .parameter_type_a = .register_id,
                    .parameter_type_b = .code_offset,
                    .parameter_type_c = .unused,
                };
            },
        }
    }

    fn printCall(self: *const Disassambler, instruction: Instruction) InstructionDescription {
        self.terminal.print("{s:<16} R{d:<2}, R{d:<2}, {d:<3}; ", .{
            @tagName(instruction.abc.opcode),
            instruction.abc.a,
            instruction.abc.b,
            instruction.abc.c,
        });
        self.terminal.printWithOptions("REG_RETURN REG_CALLEE ARG_COUNT", .{}, value_options);
        self.terminal.print("\n", .{});

        return .{
            .instruction_type = .abc,
            .parameter_type_a = .mutate_register_id,
            .parameter_type_b = .register_id,
            .parameter_type_c = .number,
        };
    }

    fn printABCMutate(self: *const Disassambler, instruction: Instruction) InstructionDescription {
        self.terminal.print("{s:<16} R{d:<2}, R{d:<2}, R{d:<2};\n", .{
            @tagName(instruction.abc.opcode),
            instruction.abc.a,
            instruction.abc.b,
            instruction.abc.c,
        });

        return .{
            .instruction_type = .abc,
            .parameter_type_a = .mutate_register_id,
            .parameter_type_b = .register_id,
            .parameter_type_c = .register_id,
        };
    }
};

const std = @import("std");
const as = @import("as");

const Terminal = as.common.Terminal;
const Chunk = as.compiler.Chunk;
const Instruction = as.compiler.Instruction;

const OpCode = as.compiler.OpCode;

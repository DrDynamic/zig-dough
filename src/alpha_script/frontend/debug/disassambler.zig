const value_options: Terminal.PrintOptions = .{
    .styles = &.{.faint},
};
pub const Disassambler = struct {
    terminal: *const Terminal,

    pub fn init(terminal: *const Terminal) Disassambler {
        return .{
            .terminal = terminal,
        };
    }

    pub fn disassambleChunk(self: *const Disassambler, chunk: *const Chunk, name: []const u8) void {
        self.terminal.print("===== {s} =====\n", .{name});
        for (chunk.code.items, 0..) |instruction, index| {
            self.disassambleInstruction(chunk, instruction, index);
        }
    }

    pub fn disassambleInstruction(self: *const Disassambler, chunk: *const Chunk, instruction: Instruction, offset: usize) void {
        self.terminal.print("{d:0>4} ", .{offset});

        const op = instruction.abc.opcode;

        switch (op) {
            .load_const => {
                const dest_reg = instruction.ab.a;
                const constant_id = instruction.ab.b;
                const value = chunk.constants.items[constant_id];

                self.terminal.print("{s:<16} R{d:<2}, K{d:<3}    ; ", .{ @tagName(op), dest_reg, constant_id });
                self.terminal.printWithOptions("{}", .{value}, value_options);
                self.terminal.print("\n", .{});
            },
            .move => self.printABCTwoAgrs(instruction),
            // math
            .add,
            .sub,
            .multiply,
            .divide,
            // compare
            .equal,
            .not_equal,
            .greater,
            .greater_equal,
            .less,
            .less_equal,
            //string
            .string_concat,
            => self.printABC(instruction),
            // interaction
            .call => self.printCall(instruction),
            .call_return => self.printA(instruction),
        }
    }

    fn printCall(self: *const Disassambler, instruction: Instruction) void {
        self.terminal.print("{s:<16} R{d:<2}, R{d:<2}, {d:<3}; ", .{
            @tagName(instruction.abc.opcode),
            instruction.abc.a,
            instruction.abc.b,
            instruction.abc.c,
        });
        self.terminal.printWithOptions("REG_RETURN REG_CALLEE ARG_COUNT", .{}, value_options);
        self.terminal.print("\n", .{});
    }

    fn printABCTwoAgrs(self: *const Disassambler, instruction: Instruction) void {
        self.terminal.print("{s:<16} R{d:<2}, R{d:<2}     ;\n", .{
            @tagName(instruction.abc.opcode),
            instruction.abc.a,
            instruction.abc.b,
        });
    }

    fn printABC(self: *const Disassambler, instruction: Instruction) void {
        self.terminal.print("{s:<16} R{d:<2}, R{d:<2}, R{d:<2};\n", .{
            @tagName(instruction.abc.opcode),
            instruction.abc.a,
            instruction.abc.b,
            instruction.abc.c,
        });
    }

    fn printA(self: *const Disassambler, instruction: Instruction) void {
        self.terminal.print("{s:<16} R{d:<2}\n", .{
            @tagName(instruction.abc.opcode),
            instruction.abc.a,
        });
    }
};

const std = @import("std");
const as = @import("as");

const Terminal = as.common.Terminal;
const Chunk = as.compiler.Chunk;
const Instruction = as.compiler.Instruction;

const OpCode = as.compiler.OpCode;

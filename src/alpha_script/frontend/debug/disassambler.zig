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
            self.disassambleInstruction(chunk, &instruction, index);
        }
    }

    pub fn disassambleInstruction(self: *const Disassambler, chunk: *const Chunk, instruction: *const Instruction, offset: usize) void {
        self.terminal.print("{d:0>4} ", .{offset});

        const op = instruction.opcode;

        switch (op) {
            .load_const => {
                const dest_reg = instruction.data.doublet.a;
                const constant_id = instruction.data.doublet.b;
                const value = chunk.constants.items[constant_id];

                self.terminal.print("{s:<16} R{d:<2}, K{d:<3}    ; ", .{ @tagName(op), dest_reg, constant_id });
                self.terminal.printWithOptions("{}", .{value}, value_options);
                self.terminal.print("\n", .{});
            },
            .move, // moves values from one register into another
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
            => self.printBinaryOp(instruction),
        }
    }

    fn printBinaryOp(self: *const Disassambler, instruction: *const Instruction) void {
        self.terminal.print("{s:<16} R{d:<2}, R{d:<2}, R{d:<2};\n", .{
            @tagName(instruction.opcode),
            instruction.data.triplet.a,
            instruction.data.triplet.b,
            instruction.data.triplet.c,
        });
    }
};

const std = @import("std");
const as = @import("as");

const Terminal = as.common.Terminal;
const Chunk = as.compiler.Chunk;
const Instruction = as.compiler.Instruction;

const OpCode = as.compiler.OpCode;

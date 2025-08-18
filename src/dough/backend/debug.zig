const std = @import("std");

const dough = @import("dough");
const Chunk = dough.values.Chunk;
const OpCode = dough.backend.OpCode;

const DoughFunction = @import("../values/objects.zig").DoughFunction;

const OPCODE_NAME_FROMAT = "{s: >20}";

pub fn disassemble_function(function: *DoughFunction) void {
    std.debug.print("== <script> ==\n", .{}); // TODO: read name from function

    const chunk = &function.chunk;

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassemble_instruction(chunk, offset);
    }
}

pub fn disassemble_instruction(chunk: *Chunk, offset: usize) usize {
    std.debug.print("[{d:0>4}] ", .{offset});

    if (offset > 0 and chunk.getLinenumber(offset) == chunk.getLinenumber(offset - 1)) {
        std.debug.print("{s: <4}|", .{""});
    } else {
        std.debug.print("{?d: >4}:", .{chunk.getLinenumber(offset)});
    }

    const instruction: OpCode = @enumFromInt(chunk.code.items[offset]);
    return switch (instruction) {
        // Slot actions
        .DefineSlot => slotAddressInstruction("DEFINE_SLOT", chunk, offset),
        .GetSlot => slotAddressInstruction("GET_SLOT", chunk, offset),
        .SetSlot => slotAddressInstruction("SET_SLOT", chunk, offset),

        // Constants
        .GetConstant => constantAddressInstruction("GET_CONSTANT", chunk, offset),

        // Value interaction
        .Call => byteDecimalInstruction("CALL", chunk, offset),

        .ConcatString => simpleInstruction("CONCAT_STRING", offset),

        .LogicalNot => simpleInstruction("LOGICAL_NOT", offset),
        .Negate => simpleInstruction("NEGATE", offset),

        .NotEqual => simpleInstruction("NOT_EQUAL", offset),
        .Equal => simpleInstruction("EQUAL", offset),
        .Greater => simpleInstruction("GREATER", offset),
        .GreaterEqual => simpleInstruction("GREATER_EQUAL", offset),
        .Less => simpleInstruction("LESS", offset),
        .LessEqual => simpleInstruction("LESS_EQUAL", offset),

        .Add => simpleInstruction("ADD", offset),
        .Subtract => simpleInstruction("SUBTRACT", offset),
        .Multiply => simpleInstruction("MULTIPLY", offset),
        .Divide => simpleInstruction("DIVIDE", offset),

        // Jumps
        .Jump => jumpInstruction("JUMP", chunk, offset),
        .JumpIfTrue => jumpInstruction("JUMP_IF_TRUE", chunk, offset),
        .JumpIfFalse => jumpInstruction("JUMP_IF_FALSE", chunk, offset),

        // Stack Actions
        .PushNull => simpleInstruction("PUSH_NULL", offset),
        .PushTrue => simpleInstruction("PUSH_TRUE", offset),
        .PushFalse => simpleInstruction("PUSH_FALSE", offset),
        .PushUninitialized => simpleInstruction("PUSH_UNINITIALIZED", offset),

        .Pop => simpleInstruction("POP", offset),

        .Return => simpleInstruction("RETURN", offset),
    };
}

fn byteDecimalInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    std.debug.print(OPCODE_NAME_FROMAT ++ " {d}\n", .{ name, chunk.code.items[offset + 1] });
    return offset + 2;
}

fn jumpInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const bytes = chunk.code.items[offset..][1..3].*;
    const jump: u16 = @bitCast(bytes);
    std.debug.print(OPCODE_NAME_FROMAT ++ " +{d}\n", .{ name, jump });

    return offset + 3;
}

fn slotAddressInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const bytes: [3]u8 = chunk.code.items[offset..][1..4].*;
    const address: u24 = @bitCast(bytes);

    std.debug.print(OPCODE_NAME_FROMAT ++ " 0x{X:0>6}\n", .{ name, address });

    return offset + 4;
}

fn constantAddressInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const bytes: [3]u8 = chunk.code.items[offset..][1..4].*;
    const address: u24 = @bitCast(bytes);

    const value = chunk.constants.items[address];
    const string = value.toString();

    std.debug.print(OPCODE_NAME_FROMAT ++ " 0x{X:0>6} '{s}'\n", .{ name, address, string.bytes });

    return offset + 4;
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print(OPCODE_NAME_FROMAT ++ "\n", .{name});
    return offset + 1;
}

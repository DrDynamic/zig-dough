const std = @import("std");

const core = @import("./core.zig");
const Chunk = core.chunk.Chunk;
const OpCode = core.chunk.OpCode;

const SlotStack = @import("../values/slot_stack.zig").SlotStack;
const DoughFunction = @import("../values/objects.zig").DoughFunction;

const OPCODE_NAME_FROMAT = "{s: >20}";

pub fn disassemble_function(function: *DoughFunction) void {
    std.debug.print("== <script> ==\n", .{}); // TODO: read name from function

    const chunk = &function.chunk;
    const slots = &function.slots;

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassemble_instruction(chunk, slots, offset);
    }
}

pub fn disassemble_instruction(chunk: *Chunk, slots: *SlotStack, offset: usize) usize {
    std.debug.print("[{d:0>4}] ", .{offset});

    if (offset > 0 and chunk.getLinenumber(offset) == chunk.getLinenumber(offset - 1)) {
        std.debug.print("{s: <4}|", .{""});
    } else {
        std.debug.print("{?d: >4}:", .{chunk.getLinenumber(offset)});
    }

    const instruction: OpCode = @enumFromInt(chunk.code.items[offset]);
    return switch (instruction) {
        // Slot actions
        .DefineSlot => slotAddressInstruction("DEFINE_SLOT", chunk, slots, offset),
        .GetSlot => slotAddressInstruction("GET_SLOT", chunk, slots, offset),
        .SetSlot => slotAddressInstruction("SET_SLOT", chunk, slots, offset),

        // Constants
        .GetConstant => constantAddressInstruction("GET_CONSTANT", chunk, offset),

        // Value interaction
        .Call => byteDecimalInstruction("CALL", chunk, offset),

        // Math
        .Add => simpleInstruction("ADD", offset),
        .Subtract => simpleInstruction("SUBTRACT", offset),
        .Multiply => simpleInstruction("MULTIPLY", offset),
        .Divide => simpleInstruction("DIVIDE", offset),

        // Stack Actions
        .PushNull => simpleInstruction("PUSH_NULL", offset),
        .PushUninitialized => simpleInstruction("PUSH_UNINITIALIZED", offset),
        .Pop => simpleInstruction("POP", offset),

        .Return => simpleInstruction("RETURN", offset),
    };
}

fn byteDecimalInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    std.debug.print(OPCODE_NAME_FROMAT ++ " {d}\n", .{ name, chunk.code.items[offset + 1] });
    return offset + 2;
}

fn slotAddressInstruction(name: []const u8, chunk: *Chunk, slots: *SlotStack, offset: usize) usize {
    const bytes: [3]u8 = chunk.code.items[offset..][1..4].*;
    const address: u24 = @bitCast(bytes);

    if (address > slots.properties.items.len - 1) {
        std.debug.print(OPCODE_NAME_FROMAT ++ " 0x{X:0>6} !INVALID ADDRESS!\n", .{ name, address });
    } else {
        const identifier = slots.properties.items[address].identifier orelse "null";
        std.debug.print(OPCODE_NAME_FROMAT ++ " 0x{X:0>6} '{s}'\n", .{ name, address, identifier });
    }

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

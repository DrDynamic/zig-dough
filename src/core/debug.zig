const std = @import("std");

const core = @import("./core.zig");
const Chunk = core.chunk.Chunk;
const OpCode = core.chunk.OpCode;

pub fn disassemble_chunk(chunk: *Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

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
        .Null => simpleInstruction("NULL", offset),
        .Pop => simpleInstruction("POP", offset),
        .Return => simpleInstruction("RETURN", offset),
    };
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

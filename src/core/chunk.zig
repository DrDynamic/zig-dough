const std = @import("std");
const types = @import("../types.zig");
const values = @import("../values/values.zig");

pub const OpCode = enum(u8) {
    // Slot actions
    DefineSlot,
    GetSlot,
    SetSlot,

    // Constants
    GetConstant,

    // Value interaction
    Call,

    LogicalNot,
    Negate,

    NotEqual,
    Equal,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,

    Add,
    Subtract,
    Multiply,
    Divide,

    // Jumps
    Jump,
    JumpIfTrue,
    JumpIfFalse,

    // Stack Actions
    //// Listerals
    PushNull, // push the value <null>
    PushTrue, // push the value <true>
    PushFalse, // push the value <false>
    PushUninitialized, // push the value <uninitialized>

    Pop, // pop a value

    Return,
};

// TODO: optimize debug info
pub const Chunk = struct {
    code: std.ArrayList(u8),
    constants: std.ArrayList(values.Value),
    lines: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = std.ArrayList(u8).init(allocator),
            .constants = std.ArrayList(values.Value).init(allocator),
            .lines = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: Chunk) void {
        self.code.deinit();
    }

    pub fn getLinenumber(self: *Chunk, code_index: usize) ?usize {
        if (self.lines.items.len <= code_index) return null;

        return self.lines.items[code_index];
    }

    pub fn writeByte(self: *Chunk, byte: u8, line: usize) !void {
        try self.code.append(byte);
        try self.lines.append(line);
    }

    pub fn writeConstant(self: *Chunk, value: values.Value) !types.ConstantAddress {
        try self.constants.append(value);
        return @intCast(self.constants.items.len - 1);
    }
};

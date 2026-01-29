pub const OpCode = enum(u8) {
    load_const, // load a constant into a register
    move, // moves values from one register into another
    // math
    add,
    sub,
    multiply,
    divide,
    // compare
    equal,
    not_equal,
    greater,
    greater_equal,
    less,
    less_equal,
};

pub const Instruction = struct {
    opcode: OpCode,
    data: packed union {
        triplet: struct {
            a: u8,
            b: u8,
            c: u8,
        },
        doublet: struct {
            a: u8,
            b: u16,
        },
    },
};

pub const ConstantId = u16;

pub const Chunk = struct {
    code: std.ArrayList(Instruction),
    constants: std.ArrayList(Value),

    pub fn emitTriplet(self: *Chunk, op_code: OpCode, a: u8, b: u8, c: u8) !void {
        try self.code.append(.{
            .op_code = op_code,
            .triplet = .{ .a = a, .b = b, .c = c },
        });
    }

    pub fn emitDoublet(self: *Chunk, op_code: OpCode, a: u8, b: u16) !void {
        try self.code.append(.{
            .op_code = op_code,
            .double = .{ .a = a, .b = b },
        });
    }

    pub fn addConstant(self: *Chunk, value: Value) !ConstantId {
        try self.constants.append(value);
        const index = self.constants.items.len - 1;
        if (index > std.math.maxInt(u16)) {
            return error.ConstantOverflow;
        }

        return @intCast(self.constants.items.len - 1);
    }
};

const std = @import("std");
const as = @import("as");
const Value = as.runtime.values.Value;

pub const OpCode = enum(u8) {
    load_const, // load a constant into a register
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
    // stack,
    stack_return,
};

pub const Instruction = packed union {
    raw: u32,
    abc: packed struct {
        opcode: OpCode,
        a: u8,
        b: u8,
        c: u8,
    },
    ab: packed struct {
        opcode: OpCode,
        a: u8,
        b: u16,
    },

    pub inline fn fromABC(opcode: OpCode, a: u8, b: u8, c: u8) Instruction {
        return .{ .abc = .{
            .opcode = opcode,
            .a = a,
            .b = b,
            .c = c,
        } };
    }

    pub inline fn fromAB(opcode: OpCode, a: u8, b: u16) Instruction {
        return .{ .ab = .{
            .opcode = opcode,
            .a = a,
            .b = b,
        } };
    }
};

pub const ConstantId = u16;

pub const Chunk = struct {
    code: std.ArrayList(Instruction),
    constants: std.ArrayList(Value),

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .code = std.ArrayList(Instruction).init(allocator),
            .constants = std.ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.constants.deinit();
    }

    pub fn emit(self: *Chunk, instruction: Instruction) !void {
        try self.code.append(instruction);
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

pub const OpCode = enum(u8) {
    load_const, // REG_DEST CONST_ADDR // load a constant (CONST_ADDR) into a register (REG_DEST)
    move, // REG_DEST REG_SRC // copy the Value from REG_SRC to REG_DEST
    // math
    add, // REG_DEST REG_A REG_B // add REG_A and REG_B and save the result in REG_DEST
    sub, // REG_DEST REG_A REG_B // subtract REG_A and REG_B and save the result in REG_DEST
    multiply, // REG_DEST REG_A REG_B // multiply REG_A and REG_B and save the result in REG_DEST
    divide, // REG_DEST REG_A REG_B // devide REG_A and REG_B and save the result in REG_DEST
    // compare
    equal, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when equal, false otherwise)
    not_equal, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (false when equal, true otherwise)
    greater, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when REG_A > REG_B, false otherwise)
    greater_equal, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when REG_A >= REG_B, false otherwise)
    less, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when REG_A < REG_B, false otherwise)
    less_equal, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when REG_A <= REG_B, false otherwise)
    // interaction
    call, // REG_DEST REG_CALLEE ARGS_COUNT // call REG_CALLEE and store the return Value in REG_DEST (ARG_COUNT registers after REG_CALLEE are reserved for call arguments)
    call_return,
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
        // TODO don't add the same Value multiple times. return the ConstantId of the Vialue that already exists in constants
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

pub const OpCode = enum(u8) {
    load_const, // REG_DEST CONST_ADDR // load a constant (CONST_ADDR) into a register (REG_DEST)
    move, // REG_DEST REG_SRC // copy the Value from REG_SRC to REG_DEST
    // math
    add, // REG_DEST REG_A REG_B // add REG_A and REG_B and save the result in REG_DEST
    sub, // REG_DEST REG_A REG_B // subtract REG_A and REG_B and save the result in REG_DEST
    multiply, // REG_DEST REG_A REG_B // multiply REG_A and REG_B and save the result in REG_DEST
    divide, // REG_DEST REG_A REG_B // devide REG_A and REG_B and save the result in REG_DEST
    negate, // REG_DEST REG_A // negate the number in REG_A and save the result to REG_DEST

    // compare
    equal, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when equal, false otherwise)
    not_equal, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (false when equal, true otherwise)
    greater, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when REG_A > REG_B, false otherwise)
    greater_equal, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when REG_A >= REG_B, false otherwise)
    less, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when REG_A < REG_B, false otherwise)
    less_equal, // REG_DEST REG_A REG_B // compare REG_A and REG_B and save the result in REG_DEST (true when REG_A <= REG_B, false otherwise)
    logical_not, // REG_DEST REG_A // negate the bool value in REG_A and save the result to REG_DEST
    // strings
    string_concat, // REG_DEST REG_A REG_B // Adds the string at REG_B to the end of the string at REG_A and saves the result in REG_DEST

    // upvalues
    load_upvalue, // REG_DEST INDEX_UPVALUE // load the Value from the UpValue at INDEX_UPVALUE in REG_DEST
    store_upvalue, // INDEX_DEST REG_SOURCE // store the Value from REG_SOURCE in the UpValue at INDEX_UPVALUE

    // interaction
    // TODO: refactor call arguments. Should get REG_DEST REG_CALLEE REG_ARGS_START so the function doesn't need to be copied every time
    op_call_setup, // ARG_COUNT ARG_INDEX // must be followed by op_call_exec -  read ARG_COUNT registers starting from ARG_INDEX and and copy the cresponding values into a new callframe
    op_call_exec, // REG_DEST REG_CALLEE 0 // must be preceded by op_call_setup - call the function in REG_CALLEE with the arguments set up by the preceding op_call_setup and save the return value in REG_DEST
    call_return, // 0 REG_FIRST_VALUE VALUE_COUNT  // return from a call and put all return values (start_value + count) into the REG_DEST of the call instruction
    create_closure, // REG_DEST CONST_ADDR // create a closure from a function at CONST_ADDR and save it in REG_DEST
    close_upvalue, // 0 REG_TO_THIS_VALUE // close the UpValue of a given register and all above

    // controlflow
    jump, // 0 OFFSET // jump to the instruction at the current instruction index + OFFSET
    jump_if_false, // REG_CONDITION OFFSET // jump to instruction index + OFFSET if the value in REG_CONDITION is false
    jump_if_true, // REG_CONDITION OFFSET // jump to instruction index + OFFSET if the value in REG_CONDITION is true

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
    allocator: std.mem.Allocator,
    code: std.ArrayList(Instruction),
    constants: std.ArrayList(Value),
    arguments: std.ArrayList(RegisterId), // maps argument register indices to their names for better error messages

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .allocator = allocator,
            .code = .{},
            .constants = .{},
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
    }

    pub fn emit(self: *Chunk, instruction: Instruction) !void {
        try self.code.append(self.allocator, instruction);
    }

    pub fn addConstant(self: *Chunk, value: Value) !ConstantId {
        // TODO don't add the same Value multiple times. return the ConstantId of the Vialue that already exists in constants
        try self.constants.append(self.allocator, value);
        const index = self.constants.items.len - 1;
        if (index > std.math.maxInt(u16)) {
            return error.ConstantOverflow;
        }

        return @intCast(self.constants.items.len - 1);
    }

    pub fn addArgument(self: *Chunk, reg: RegisterId) !usize {
        try self.arguments.append(self.allocator, reg);
        return self.arguments.items.len - 1;
    }
};

const std = @import("std");
const as = @import("as");
const Value = as.runtime.values.Value;
const RegisterId = as.runtime.RegisterId;

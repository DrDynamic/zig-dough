const RegisterId = u8;

/// a variable bound to a register
pub const Local = struct {
    name_id: StringId,
    depth: i32,
    reg_slot: RegisterId,
    is_captured: bool,
    is_initialized: bool,
};

pub const Compiler = struct {
    pub const Error = error{
        LocalNotFound,
        UnexpectedComptime,
        UnexpectedVoid,
        ConstantOverflow,
        OutOfMemory,
        NotImplemented,
    };

    allocator: std.mem.Allocator,

    ast: *AST,
    chunk: *Chunk,
    locals: std.ArrayList(Local),
    scope_depth: i32,
    next_free_reg: RegisterId,

    pub fn init(ast: *AST, chunk: *Chunk, allocator: std.mem.Allocator) Compiler {
        return .{
            .allocator = allocator,
            .ast = ast,
            .chunk = chunk,
            .locals = std.ArrayList(Local).init(allocator),
            .scope_depth = 0,
            .next_free_reg = 0,
        };
    }

    pub fn compile(self: *Compiler) !void {
        for (self.ast.getRoots()) |node_id| {
            _ = try self.compileNode(node_id);
        }
    }

    fn compileNode(self: *Compiler, node_id: NodeId) Error!u8 {
        const node = self.ast.nodes.items[node_id];

        return switch (node.tag) {
            // nodes needed ad compiletime (should not bleed into runtime!)
            .comptime_uninitialized => return error.UnexpectedComptime,

            // literals
            .literal_void => return error.UnexpectedVoid,
            .literal_null => {
                const register = self.next_free_reg;
                self.next_free_reg += 1;

                try self.emitLoadConstant(.load_const, register, .{
                    .tag = .null,
                    .data = undefined,
                });
                return register;
            },
            .literal_bool => {
                const register = self.next_free_reg;
                self.next_free_reg += 1;

                try self.emitLoadConstant(.load_const, register, .{
                    .tag = .bool,
                    .data = .{ .boolean = node.data.bool_value },
                });
                return register;
            },
            .literal_int => {
                const register = self.next_free_reg;
                self.next_free_reg += 1;

                try self.emitLoadConstant(.load_const, register, .{
                    .tag = .integer,
                    .data = .{ .integer = node.data.int_value },
                });
                return register;
            },
            .literal_float => {
                const register = self.next_free_reg;
                self.next_free_reg += 1;

                try self.emitLoadConstant(.load_const, register, .{
                    .tag = .float,
                    .data = .{ .float = node.data.float_value },
                });
                return register;
            },

            // objects
            .object_string => error.NotImplemented,

            // declarations
            .declaration_var => {
                const data = self.ast.getExtra(node.data.extra_id, VarDeclarationExtra);
                const init_node = self.ast.nodes.items[data.init_value];

                var init_reg: RegisterId = undefined;
                if (init_node.tag == .comptime_uninitialized) {
                    init_reg = self.next_free_reg;
                    self.next_free_reg += 1;
                    try self.emitLoadConstant(.load_const, init_reg, .{
                        .tag = .null,
                        .data = undefined,
                    });
                    try self.addLocal(data.name_id, init_reg, true);
                } else {
                    // create a temporary local, so compileNode can reference the variable
                    const local_index = self.locals.items.len;
                    try self.addLocal(data.name_id, self.next_free_reg, false);

                    init_reg = try self.compileNode(data.init_value);
                    self.locals.items[local_index].is_initialized = true;
                    self.locals.items[local_index].reg_slot = init_reg;
                }

                return init_reg;
            },

            // access
            .identifier_expr => {
                return try self.resolveLocal(node.data.string_id);
            },

            // binary operations
            .binary_add => {
                return self.emitBinaryOp(.add, &node);
            },
            .binary_sub => {
                return self.emitBinaryOp(.sub, &node);
            },
            .binary_mul => {
                return self.emitBinaryOp(.multiply, &node);
            },
            .binary_div => {
                return self.emitBinaryOp(.divide, &node);
            },
            .binary_equal => {
                return self.emitBinaryOp(.equal, &node);
            },
            .binary_not_equal => {
                return self.emitBinaryOp(.not_equal, &node);
            },
            .binary_less => {
                return self.emitBinaryOp(.less, &node);
            },
            .binary_less_equal => {
                return self.emitBinaryOp(.less_equal, &node);
            },
            .binary_greater => {
                return self.emitBinaryOp(.greater, &node);
            },
            .binary_greater_equal => {
                return self.emitBinaryOp(.greater_equal, &node);
            },
        };
    }

    fn emitBinaryOp(self: *Compiler, op_code: OpCode, node: *const Node) !RegisterId {
        const extra = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);
        const lhs_reg = try self.compileNode(extra.lhs);
        const rhs_reg = try self.compileNode(extra.rhs);

        try self.chunk.emitTriplet(op_code, lhs_reg, lhs_reg, rhs_reg);

        // free rhs_reg
        self.next_free_reg -= 1;
        return lhs_reg;
    }

    fn emitLoadConstant(self: *Compiler, op_code: OpCode, register: RegisterId, constant: Value) !void {
        const constant_id = try self.chunk.addConstant(constant);
        try self.chunk.emitDoublet(op_code, register, constant_id);
    }

    /// bind a variable to a register
    fn addLocal(self: *Compiler, name_id: StringId, register: RegisterId, is_initialized: bool) !void {
        try self.locals.append(.{
            .name_id = name_id,
            .depth = self.scope_depth,
            .reg_slot = register,
            .is_captured = false,
            .is_initialized = is_initialized,
        });
    }

    /// searches for the register of a variable
    fn resolveLocal(self: *const Compiler, name_id: StringId) !RegisterId {
        var local_index: isize = @as(isize, @intCast(self.locals.items.len)) - 1;
        while (local_index >= 0) : (local_index -= 1) {
            const local = self.locals.items[@intCast(local_index)];
            if (local.name_id == name_id) return local.reg_slot;
        }

        return error.LocalNotFound;
    }

    fn enterScope(self: *Compiler) void {
        self.scope_depth += 1;
        // TODO error handling (overflow of scopes?)
    }

    fn exitScope(self: *Compiler) void {
        self.scope_depth -= 1;
        // TODO error handlich (underflow of scopes?)
        while (self.locals.items.len > 0 and self.locals.items[self.locals.items.len - 1].depth > self.scope_depth) {
            _ = self.locals.pop();
            self.next_free_reg -= 1;
            // TODO free register in the vm?
        }
    }
};

const instructions = @import("instruction.zig");
pub const Instruction = instructions.Instruction;
pub const Chunk = instructions.Chunk;

pub const ConstantId = instructions.ConstantId;
pub const OpCode = instructions.OpCode;

const std = @import("std");
const as = @import("as");

const AST = as.frontend.AST;
const TypePool = as.frontend.TypePool;
const Value = as.runtime.values.Value;
const VarDeclarationExtra = as.frontend.ast.VarDeclarationExtra;
const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;
const Node = as.frontend.ast.Node;

const NodeId = as.frontend.ast.NodeId;
const StringId = as.common.StringId;

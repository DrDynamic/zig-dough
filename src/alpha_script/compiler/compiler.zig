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

    pub fn init(_ast: *AST, chunk: *Chunk, allocator: std.mem.Allocator) Compiler {
        return .{
            .allocator = allocator,
            .ast = _ast,
            .chunk = chunk,
            .locals = std.ArrayList(Local).init(allocator),
            .scope_depth = 0,
            .next_free_reg = 0,
        };
    }

    pub fn compile(self: *Compiler) !void {
        for (self.ast.getRoots()) |node_id| {
            _ = try self.compileExpression(node_id);
        }
    }

    fn compileExpression(self: *Compiler, node_id: NodeId) Error!u8 {
        const node = self.ast.nodes.items[node_id];

        return switch (node.tag) {
            // nodes needed ad compiletime (should not bleed into runtime!)
            .comptime_uninitialized => return error.UnexpectedComptime,
            .node_list => unreachable,

            // literals
            .literal_void => return error.UnexpectedVoid,
            .literal_null => {
                const register = self.next_free_reg;
                self.next_free_reg += 1;

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeNull(),
                );
                return register;
            },
            .literal_bool => {
                const register = self.next_free_reg;
                self.next_free_reg += 1;

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeBool(node.data.bool_value),
                );
                return register;
            },
            .literal_int => {
                const register = self.next_free_reg;
                self.next_free_reg += 1;

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeInteger(node.data.int_value),
                );
                return register;
            },
            .literal_float => {
                const register = self.next_free_reg;
                self.next_free_reg += 1;

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeFloat(node.data.float_value),
                );
                return register;
            },

            // objects
            .object_string => error.NotImplemented,

            // declarations
            .declaration_var => {
                const data = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationExtra);
                const init_node = self.ast.nodes.items[data.init_value];

                var init_reg: RegisterId = undefined;
                if (init_node.tag == .comptime_uninitialized) {
                    init_reg = self.next_free_reg;
                    self.next_free_reg += 1;
                    try self.emitLoadConstant(
                        .load_const,
                        init_reg,
                        Value.makeNull(),
                    );
                    try self.addLocal(data.name_id, init_reg, true);
                } else {
                    // create a temporary local, so compileExpression can reference the variable
                    const local_index = self.locals.items.len;
                    try self.addLocal(data.name_id, self.next_free_reg, false);

                    init_reg = try self.compileExpression(data.init_value);
                    self.locals.items[local_index].is_initialized = true;
                    self.locals.items[local_index].reg_slot = init_reg;
                }

                return init_reg;
            },

            // access
            .identifier_expr => {
                return try self.resolveLocal(node.data.string_id);
            },
            .call => {
                const data = self.ast.getExtra(node.data.extra_id, ast.CallExtra);

                const reg_callee = self.next_free_reg;
                self.next_free_reg += 1;

                try self.compileExpressionEnsureRegister(data.callee, reg_callee);

                var reg_arg = self.next_free_reg;
                var arg_list = data.args_start;
                for (0..data.args_count) |_| {
                    const list_node = self.ast.nodes.items[arg_list];
                    const list_extra = self.ast.getExtra(list_node.data.extra_id, ast.NodeListExtra);

                    try self.compileExpressionEnsureRegister(list_extra.node_id, reg_arg);
                    reg_arg += 1;
                    arg_list = list_extra.next;
                }

                try self.chunk.emit(Instruction.fromABC(.call, reg_callee, reg_callee, data.args_count));
                return reg_callee;
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

            // stack_actions
            .stack_return => {
                const reg = try self.compileExpression(node.data.node_id);
                try self.chunk.emit(Instruction.fromAB(.stack_return, reg, 0));
                return 0;
            },
        };
    }

    inline fn compileExpressionEnsureRegister(self: *Compiler, node_id: ast.NodeId, register: RegisterId) !void {
        const result = try self.compileExpression(node_id);
        if (result != register) {
            try self.chunk.emit(Instruction.fromABC(.move, register, result, 0));
            if (register <= self.next_free_reg) {
                self.next_free_reg = register + 1;
            }
        }
    }

    fn emitBinaryOp(self: *Compiler, opcode: OpCode, node: *const Node) !RegisterId {
        const extra = self.ast.getExtra(node.data.extra_id, ast.BinaryOpExtra);
        const lhs_reg = try self.compileExpression(extra.lhs);
        const rhs_reg = try self.compileExpression(extra.rhs);

        try self.chunk.emit(Instruction.fromABC(opcode, lhs_reg, lhs_reg, rhs_reg));

        // free rhs_reg
        self.next_free_reg -= 1;
        return lhs_reg;
    }

    fn emitLoadConstant(self: *Compiler, opcode: OpCode, register: RegisterId, constant: Value) !void {
        const constant_id = try self.chunk.addConstant(constant);
        try self.chunk.emit(Instruction.fromAB(opcode, register, constant_id));
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
        const str = self.ast.string_table.get(name_id);

        _ = str;
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
const ast = as.frontend.ast;

const AST = as.frontend.AST;
const TypePool = as.frontend.TypePool;
const Value = as.runtime.values.Value;
const Node = as.frontend.ast.Node;

const NodeId = as.frontend.ast.NodeId;
const StringId = as.common.StringId;

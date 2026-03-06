const RegisterId = u8;

/// a variable bound to a register
pub const Local = struct {
    name_id: StringId,
    depth: i32,
    reg_slot: RegisterId,
    owns_register: bool,
    is_captured: bool,
    is_initialized: bool,
};

pub const Compiler = struct {
    pub const Error = error{
        UndefinedIdentifier,

        ConstantOverflow,
        OutOfMemory,
    };

    allocator: std.mem.Allocator,
    garbage_collector: *GarbageCollector,
    error_reporter: *const ErrorReporter,

    ast: *AST = undefined,
    max_registers: *u8 = undefined,
    chunk: *Chunk = undefined,
    locals: std.ArrayList(Local),
    scope_depth: i32,
    next_free_reg: RegisterId,

    pub fn init(error_reporter: *const ErrorReporter, garbage_collector: *GarbageCollector, allocator: std.mem.Allocator) Compiler {
        return .{
            .allocator = allocator,
            .garbage_collector = garbage_collector,
            .error_reporter = error_reporter,
            .locals = std.ArrayList(Local).init(allocator),
            .scope_depth = 0,
            .next_free_reg = 0,
        };
    }

    pub fn compile(self: *Compiler, _ast: *AST) !*ObjModule {
        self.ast = _ast;

        var function = ObjFunction.init(self.garbage_collector);
        self.max_registers = &function.max_registers;
        self.chunk = &function.chunk;

        for (self.ast.getRoots()) |node_id| {
            try self.compileStatement(node_id);
        }

        try self.chunk.emit(Instruction.fromABC(.call_return, 0, 0, 0));

        return ObjModule.init(function, self.garbage_collector);
    }

    fn compileStatement(self: *Compiler, node_id: NodeId) !void {
        const node = self.ast.nodes.items[node_id];

        switch (node.tag) {
            // declarations
            .declaration_type => {},
            .declaration_const,
            .declaration_var,
            => {
                const extra = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationExtra);

                if (extra.init_value) |init_value_id| {
                    // create the local before initializing it, so compileExpression can reference the variable
                    const local_index = self.locals.items.len;
                    try self.addLocal(extra.name_id, self.next_free_reg, false, true);

                    try self.compileExpressionEnsureRegister(init_value_id, self.next_free_reg);
                    _ = self.allocateRegister();

                    self.locals.items[local_index].is_initialized = true;
                } else {
                    const init_reg = self.next_free_reg;
                    self.next_free_reg += 1;
                    try self.emitLoadConstant(
                        .load_const,
                        init_reg,
                        Value.makeUninitialized(),
                    );
                    try self.addLocal(extra.name_id, init_reg, true, true);
                }
            },
            else => { // expression statements
                const snapshot = self.next_free_reg;

                _ = try self.compileExpression(node_id);

                self.next_free_reg = snapshot;
            },
        }
    }

    fn compileExpression(self: *Compiler, node_id: NodeId) Error!u8 {
        const node = self.ast.nodes.items[node_id];

        return switch (node.tag) {
            .node_list => unreachable,

            // statements
            .declaration_type,
            .declaration_const,
            .declaration_var,
            => unreachable,

            // literals
            .literal_null => {
                const register = self.next_free_reg;

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeNull(),
                );
                return register;
            },
            .literal_bool => {
                const register = self.next_free_reg;

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeBool(node.data.bool_value),
                );
                return register;
            },
            .literal_int => {
                const register = self.next_free_reg;

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeInteger(node.data.int_value),
                );
                return register;
            },
            .literal_float => {
                const register = self.next_free_reg;

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeFloat(node.data.float_value),
                );
                return register;
            },

            // objects
            .object_string => {
                const register = self.next_free_reg;
                const string_data = self.ast.string_table.get(node.data.string_id);
                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.fromObject(ObjString.copydata(string_data, self.garbage_collector).asObject()),
                );

                return register;
            },

            // expressions
            .expression_grouping => try self.compileExpression(node.data.node_id),
            .expression_block => {
                self.enterScope();

                var iterator = NodeListIterator.init(self.ast, node.data.node_id);
                while (iterator.next()) |child_node_id| {
                    _ = try self.compileStatement(child_node_id);
                }

                self.exitScope();

                return 0;
            },

            .expression_if => {
                const extra = self.ast.getExtra(node.data.extra_id, IfExtra);

                const reg_condition = try self.compileExpression(extra.condition);

                const pos_jump_else = self.chunk.code.items.len;

                // Error and null evaluate to false. Should we use a explicit implementation for this instead of relying on falseness?
                try self.chunk.emit(Instruction.fromAB(.jump_if_false, reg_condition, 0));

                self.enterScope();
                if (extra.then_capture) |then_capture_id| {
                    const node_capture = self.ast.nodes.items[then_capture_id];
                    assert(node_capture.tag == .declaration_const);

                    const capture_extra = self.ast.getExtra(node_capture.data.extra_id, VarDeclarationExtra);
                    const capture_name_id = capture_extra.name_id;
                    const void_identifier_id = try self.ast.string_table.add("_");

                    if (capture_name_id != void_identifier_id) {
                        try self.addLocal(capture_name_id, reg_condition, true, false);
                    }
                }

                const reg_then = self.next_free_reg;
                try self.compileExpressionEnsureRegister(extra.then_branch, self.next_free_reg);

                self.exitScope();

                const pos_jump_end = self.chunk.code.items.len;
                try self.chunk.emit(Instruction.fromAB(.jump, 0, 0));

                // patch jump_else to jump to else branch
                self.patchJump(pos_jump_else);

                if (extra.else_branch) |else_branch_id| {
                    self.enterScope();
                    if (extra.else_capture) |else_capture_id| {
                        const node_capture = self.ast.nodes.items[else_capture_id];
                        assert(node_capture.tag == .declaration_const);

                        const capture_extra = self.ast.getExtra(node_capture.data.extra_id, VarDeclarationExtra);
                        const capture_name_id = capture_extra.name_id;
                        const void_identifier_id = try self.ast.string_table.add("_");

                        if (capture_name_id != void_identifier_id) {
                            try self.addLocal(capture_name_id, reg_condition, true, false);
                        }
                    }

                    const reg_else = self.next_free_reg;
                    try self.compileExpressionEnsureRegister(else_branch_id, self.next_free_reg);
                    self.exitScope();

                    // both branches should produce the same register, since the result of the if expression is in that register
                    assert(reg_then == reg_else);
                }

                // patch jump at the end of then branch to jump to the end of else branch
                self.patchJump(pos_jump_end);

                return reg_then;
            },

            // access
            .assignment => {
                const extra = self.ast.getExtra(node.data.extra_id, AssignmentExtra);
                const target_node = self.ast.nodes.items[extra.target]; // semantic analyser assures that this is an identifier_expr
                const reg_target = self.resolveLocal(target_node.data.string_id) catch unreachable; // assured by semyntc analyser

                try self.compileExpressionEnsureRegister(extra.source, reg_target);
                return reg_target;
            },
            .identifier_expr => self.resolveLocal(node.data.string_id) catch unreachable, // assured by semyntc analyser
            .call => {
                const extra = self.ast.getExtra(node.data.extra_id, CallExtra);

                const snapshot = self.next_free_reg;

                const reg_callee = self.allocateRegister();

                try self.compileExpressionEnsureRegister(extra.callee, reg_callee);

                var iterator = NodeListIterator.init(self.ast, extra.args_start);
                const reg_start = self.next_free_reg;
                var arg_count: u8 = 0;
                while (iterator.next()) |arg_node_id| {
                    _ = try self.compileExpressionEnsureRegister(arg_node_id, reg_start + arg_count);
                    arg_count += 1;
                }

                try self.chunk.emit(Instruction.fromABC(.call, reg_callee, reg_callee, arg_count));
                self.next_free_reg = snapshot;
                return reg_callee;
            },

            //unary operations
            .negate => self.emitUnaryOp(.negate, &node),
            .logical_not => self.emitUnaryOp(.logical_not, &node),

            // binary operations
            .binary_add => {
                const extra = self.ast.getExtra(node.data.extra_id, ast.BinaryOpExtra);
                const node_lhs = self.ast.nodes.items[extra.lhs];
                const node_rhs = self.ast.nodes.items[extra.rhs];

                if (node_lhs.resolved_type_id == TypePool.STRING and node_rhs.resolved_type_id == TypePool.STRING) {
                    return self.emitBinaryOp(.string_concat, &node);
                }

                return self.emitBinaryOp(.add, &node);
            },
            .binary_sub => self.emitBinaryOp(.sub, &node),
            .binary_mul => self.emitBinaryOp(.multiply, &node),
            .binary_div => self.emitBinaryOp(.divide, &node),
            .binary_equal => self.emitBinaryOp(.equal, &node),
            .binary_not_equal => self.emitBinaryOp(.not_equal, &node),
            .binary_less => self.emitBinaryOp(.less, &node),
            .binary_less_equal => self.emitBinaryOp(.less_equal, &node),
            .binary_greater => self.emitBinaryOp(.greater, &node),
            .binary_greater_equal => self.emitBinaryOp(.greater_equal, &node),

            // stack_actions
            .call_return => {
                const reg = try self.compileExpression(node.data.node_id);
                try self.chunk.emit(Instruction.fromAB(.call_return, reg, 0));
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

    inline fn allocateRegister(self: *Compiler) RegisterId {
        const next_free = self.next_free_reg;
        self.next_free_reg += 1;
        self.max_registers.* = @max(self.next_free_reg, self.max_registers.*);
        return next_free;
    }

    fn emitUnaryOp(self: *Compiler, opcode: OpCode, node: *const Node) !RegisterId {
        const snapshot = self.next_free_reg;

        const reg_rhs = try self.compileExpression(node.data.node_id);
        const reg_dest = if (reg_rhs < snapshot) snapshot else reg_rhs;

        try self.chunk.emit(Instruction.fromABC(opcode, reg_dest, reg_rhs, 0));

        // free all regs
        self.next_free_reg = snapshot;
        return reg_dest;
    }

    fn emitBinaryOp(self: *Compiler, opcode: OpCode, node: *const Node) !RegisterId {
        const extra = self.ast.getExtra(node.data.extra_id, ast.BinaryOpExtra);

        const snapshot = self.next_free_reg;

        const reg_lhs = try self.compileExpression(extra.lhs);
        _ = self.allocateRegister();
        const reg_rhs = try self.compileExpression(extra.rhs);

        const reg_dest = if (reg_lhs < snapshot) snapshot else reg_lhs;

        try self.chunk.emit(Instruction.fromABC(opcode, reg_dest, reg_lhs, reg_rhs));

        // free all regs
        self.next_free_reg = snapshot;
        return reg_dest;
    }

    fn emitLoadConstant(self: *Compiler, opcode: OpCode, register: RegisterId, constant: Value) !void {
        const constant_id = try self.chunk.addConstant(constant);
        try self.chunk.emit(Instruction.fromAB(opcode, register, constant_id));
    }

    inline fn patchJump(self: *Compiler, jump_pos: usize) void {
        const jump_offset: i32 = @intCast(self.chunk.code.items.len - jump_pos);
        assert(jump_offset > 0);
        self.chunk.code.items[jump_pos].ab.b = @intCast(jump_offset);
    }

    /// bind a variable to a register
    fn addLocal(self: *Compiler, name_id: StringId, register: RegisterId, is_initialized: bool, owns_register: bool) !void {
        // std.debug.print("## addLocal {{\n", .{});
        // std.debug.print("##   name: {s}\n", .{self.ast.string_table.get(name_id)});
        // std.debug.print("##   depth: {d}\n", .{self.scope_depth});
        // std.debug.print("##   reg_slot: {d}\n", .{register});
        // std.debug.print("##   is_initialized: {}\n", .{is_initialized});
        // std.debug.print("## }}\n", .{});
        // std.debug.print("\n", .{});

        try self.locals.append(.{
            .name_id = name_id,
            .depth = self.scope_depth,
            .reg_slot = register,
            .owns_register = owns_register,
            .is_captured = false,
            .is_initialized = is_initialized,
        });
    }

    /// searches for the register of a variable
    fn resolveLocal(self: *const Compiler, name_id: StringId) Error!RegisterId {
        const str = self.ast.string_table.get(name_id);

        _ = str;
        var local_index: isize = @as(isize, @intCast(self.locals.items.len)) - 1;
        while (local_index >= 0) : (local_index -= 1) {
            const local = self.locals.items[@intCast(local_index)];
            if (local.name_id == name_id) return local.reg_slot;
        }

        return Error.UndefinedIdentifier;
    }

    fn enterScope(self: *Compiler) void {
        self.scope_depth += 1;
        // TODO error handling (overflow of scopes?)
    }

    fn exitScope(self: *Compiler) void {
        self.scope_depth -= 1;
        // TODO error handlich (underflow of scopes?)
        while (self.locals.items.len > 0 and self.locals.items[self.locals.items.len - 1].depth > self.scope_depth) {
            const local = self.locals.pop();

            // std.debug.print("## popLocal {{\n", .{});
            // std.debug.print("##   name: {s}\n", .{self.ast.string_table.get(local.?.name_id)});
            // std.debug.print("##   depth: {d}\n", .{local.?.depth});
            // std.debug.print("##   reg_slot: {d}\n", .{local.?.reg_slot});
            // std.debug.print("##   is_initialized: {}\n", .{local.?.is_initialized});
            // std.debug.print("## }}\n", .{});
            // std.debug.print("\n", .{});

            if (local.?.owns_register) {
                self.next_free_reg = local.?.reg_slot;
            }
        }
    }
};

const instructions = @import("instruction.zig");
pub const Instruction = instructions.Instruction;
pub const Chunk = instructions.Chunk;

pub const ConstantId = instructions.ConstantId;
pub const OpCode = instructions.OpCode;
//---------------
const std = @import("std");

const assert = std.debug.assert;

const as = @import("as");
const ast = as.frontend.ast;

const AST = as.frontend.AST;
const ErrorReporter = as.common.reporting.ErrorReporter;
const GarbageCollector = as.common.memory.GarbageCollector;
const Node = as.frontend.ast.Node;
const ObjFunction = as.runtime.values.ObjFunction;
const ObjModule = as.runtime.values.ObjModule;
const ObjString = as.runtime.values.ObjString;
const StringTable = as.common.StringTable;
const TypePool = as.frontend.TypePool;
const Value = as.runtime.values.Value;

const NodeId = as.frontend.ast.NodeId;
const StringId = as.common.StringId;

const NodeListExtra = as.frontend.ast.NodeListExtra;
const NodeListIterator = as.frontend.ast.NodeListIterator;
const IfExtra = as.frontend.ast.IfExtra;
const AssignmentExtra = as.frontend.ast.AssignmentExtra;
const VarDeclarationExtra = as.frontend.ast.VarDeclarationExtra;
const CallExtra = as.frontend.ast.CallExtra;

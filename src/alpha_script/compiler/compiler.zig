/// a variable bound to a register
pub const Local = struct {
    name_id: StringId,
    depth: i32,
    reg_slot: RegisterId,
    owns_register: bool,
    is_captured: bool,
    is_initialized: bool,
};

pub const CompilerContext = struct {
    parent_context: ?*CompilerContext = null,

    max_registers: *u8 = undefined,
    chunk: *Chunk = undefined,
    locals: std.ArrayList(Local),
    upvalues: std.ArrayList(ObjFunction.UpValueLocation),
    scope_depth: i32,
    next_free_reg: RegisterId,

    pub fn init(parent: ?*CompilerContext, max_registers: *u8, chunk: *Chunk, allocator: std.mem.Allocator) CompilerContext {
        return .{
            .parent_context = parent,

            .locals = std.ArrayList(Local).init(allocator),
            .upvalues = std.ArrayList(ObjFunction.UpValueLocation).init(allocator),
            .scope_depth = 0,
            .next_free_reg = 0,

            .max_registers = max_registers,
            .chunk = chunk,
        };
    }

    pub fn deinit(self: *CompilerContext) void {
        self.locals.deinit();
        //self.upvalues.deinit(); ownership moves into compiled function
    }
};

pub const Compiler = struct {
    pub const Error = error{
        UndefinedIdentifier,

        ConstantOverflow,
        UpValueOverflow,
        OutOfMemory,
    };

    allocator: std.mem.Allocator,
    garbage_collector: *GarbageCollector,
    error_reporter: *const ErrorReporter,

    // initialized in compile()
    is_compiling: bool = false, // used by MemoryManager, know if it needs to look at context.chunk.constants
    ast: *AST = undefined,
    context: CompilerContext = undefined,

    pub fn init(error_reporter: *const ErrorReporter, garbage_collector: *GarbageCollector, allocator: std.mem.Allocator) Compiler {
        return .{
            .allocator = allocator,
            .garbage_collector = garbage_collector,
            .error_reporter = error_reporter,
        };
    }

    pub fn deinit(self: *Compiler) void {
        _ = self;
        //        self.context.deinit();
    }

    pub fn compile(self: *Compiler, _ast: *AST, buildin_functions: []BuildinFunction) !*ObjModule {
        self.ast = _ast;

        var function = ObjFunction.init(self.garbage_collector);
        try self.garbage_collector.temp_objects.append(function.asObject());

        self.context = CompilerContext.init(
            null,
            &function.max_registers,
            &function.chunk,
            self.allocator,
        );
        defer self.context.deinit();

        for (buildin_functions) |buildin| {
            self.context.locals.append(.{
                .name_id = buildin.name_id,
                .depth = 0,
                .reg_slot = 0,
                .owns_register = true,
                .is_captured = false,
                .is_initialized = true,
            }) catch {
                @panic("failed to register natives");
            };

            _ = self.allocateRegister();
        }
        defer {
            for (buildin_functions) |_| {
                _ = self.context.locals.pop();
                self.freeRegister();
            }
        }

        self.is_compiling = true;
        defer self.is_compiling = false;

        const roots = self.ast.getRoots();
        try self.hoistScan(roots);

        for (roots) |node_id| {
            try self.compileStatement(node_id);
        }

        try self.emitInstruction(Instruction.fromABC(.call_return, 0, 0, 0));

        const module = ObjModule.init(function, self.garbage_collector);
        _ = self.garbage_collector.temp_objects.pop(); // pop compiled function
        return module;
    }

    /// allocatres register for hoisetd symbols
    fn hoistScan(self: *Compiler, node_ids: []const NodeId) !void {
        for (node_ids) |node_id| {
            const node = &self.ast.nodes.items[node_id];
            switch (node.tag) {
                .declaration_var, .declaration_const => {
                    const extra = self.ast.getExtra(node.data.extra_id, ast.DeclarationExtra);
                    _ = try self.addLocal(extra.name_id, self.context.next_free_reg, false, true);
                },
                .expression_function => {
                    const fn_extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);

                    if (fn_extra.name_id) |name_id| {
                        const result_reg: RegisterId = self.allocateRegister();
                        _ = try self.addLocal(name_id, result_reg, true, true);

                        const fn_obj = try self.compileFunction(node_id);
                        try self.garbage_collector.temp_objects.append(fn_obj.asObject());

                        const string_data = self.ast.string_table.get(name_id);
                        fn_obj.name = ObjString.copydata(string_data, self.garbage_collector);

                        _ = self.garbage_collector.temp_objects.pop();

                        try self.emitFunctionOrClosure(result_reg, fn_obj);
                    }
                },
                else => {},
            }
        }
    }

    fn compileFunction(self: *Compiler, node_id: NodeId) !*ObjFunction {
        const fn_node = self.ast.nodes.items[node_id];
        const fn_extra = self.ast.getExtra(fn_node.data.extra_id, FunctionExtra);

        var function = ObjFunction.init(self.garbage_collector);
        try self.garbage_collector.temp_objects.append(function.asObject());

        var parent_context = self.context;
        var fn_context = CompilerContext.init(
            &parent_context,
            &function.max_registers,
            &function.chunk,
            self.allocator,
        );
        defer fn_context.deinit();
        self.context = fn_context;

        self.enterScope();
        // define parameters
        if (fn_extra.parameters) |parameters| {
            for (parameters) |parameter_node_id| {
                const parameter_node = self.ast.nodes.items[parameter_node_id];
                const parameter_reg = self.allocateRegister();
                _ = try self.addLocal(parameter_node.data.string_id, parameter_reg, true, true);
            }
        }

        // compile function body
        try self.compileStatement(fn_extra.body);

        try self.exitScope();

        function.upvalue_locations = self.context.upvalues.items;

        self.context = parent_context;

        return function;
    }

    fn compileStatement(self: *Compiler, node_id: NodeId) !void {
        const node = self.ast.nodes.items[node_id];

        switch (node.tag) {
            // declarations
            .declaration_error_set => {},
            .declaration_type => {},
            .declaration_const,
            .declaration_var,
            => {
                const extra = self.ast.getExtra(node.data.extra_id, ast.DeclarationExtra);
                const register = self.resolveLocal(extra.name_id) catch unreachable; // should not fail, since its added while hoisting

                if (extra.init_value) |init_value_id| {
                    try self.compileExpressionEnsureRegister(init_value_id, register);
                    self.initializeLocal(extra.name_id) catch unreachable; // should not fail, since its added while hoisting
                }
            },
            // statements
            .statement_return => {
                const reg = try self.compileExpression(node.data.node_id);
                try self.emitInstruction(Instruction.fromABC(.call_return, 0, reg, 0));
            },
            else => { // expression statements
                const snapshot = self.context.next_free_reg;

                _ = try self.compileExpression(node_id);

                self.context.next_free_reg = snapshot;
            },
        }
    }

    fn compileExpression(self: *Compiler, node_id: NodeId) Error!u8 {
        const node = self.ast.nodes.items[node_id];

        return switch (node.tag) {
            .node_list => unreachable,

            // statements
            .declaration_error_set,
            .declaration_type,
            .declaration_const,
            .declaration_var,
            .declaration_parameter,
            .statement_return,
            => unreachable,

            // literals
            .literal_null => {
                const register = self.allocateRegister();
                self.freeRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeNull(),
                );
                return register;
            },
            .literal_bool => {
                const register = self.allocateRegister();
                self.freeRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeBool(node.data.bool_value),
                );
                return register;
            },
            .literal_int => {
                const register = self.allocateRegister();
                self.freeRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeInteger(node.data.int_value),
                );
                return register;
            },
            .literal_float => {
                const register = self.allocateRegister();
                self.freeRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeFloat(node.data.float_value),
                );
                return register;
            },
            .literal_error => {
                const register = self.allocateRegister();
                self.freeRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeErrorValue(node.data.error_value),
                );
                return register;
            },

            // objects
            .object_string => {
                const register = self.allocateRegister();
                self.freeRegister();

                const string_data = self.ast.string_table.get(node.data.string_id);
                const string_object = ObjString.copydata(string_data, self.garbage_collector).asObject();

                try self.garbage_collector.temp_objects.append(string_object);
                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.fromObject(string_object),
                );
                _ = self.garbage_collector.temp_objects.pop();

                return register;
            },

            // expressions
            .expression_assignment => {
                const extra = self.ast.getExtra(node.data.extra_id, AssignmentExtra);
                const target_node = self.ast.nodes.items[extra.target]; // semantic analyser assures that this is an identifier_expr

                if (self.resolveLocal(target_node.data.string_id)) |reg_target| {
                    try self.compileExpressionEnsureRegister(extra.source, reg_target);
                    return reg_target;
                } else |_| {
                    const reg_target = self.allocateRegister();
                    self.freeRegister();

                    const upvalue_index = self.resolveUpValue(target_node.data.string_id) catch unreachable; // identifier has to be somewhere (checked by semantic analyser)
                    try self.compileExpressionEnsureRegister(extra.source, reg_target);
                    try self.emitInstruction(Instruction.fromABC(.store_upvalue, upvalue_index, reg_target, 0));

                    return reg_target;
                }
            },
            .expression_function => {
                // only anonymous functions. Named functions are hoisted. See fn hoistScan()
                const fn_extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);

                if (fn_extra.name_id == null) {
                    const result_reg: RegisterId = self.allocateRegister();
                    self.freeRegister();

                    const fn_obj = try self.compileFunction(node_id);
                    try self.emitFunctionOrClosure(result_reg, fn_obj);

                    return result_reg;
                }
                return 0;
            },
            .expression_grouping => try self.compileExpression(node.data.node_id),
            .expression_block => {
                self.enterScope();

                const extra = self.ast.getExtra(node.data.extra_id, BlockExtra);

                if (extra.statements) |statements| {
                    try self.hoistScan(statements);
                    for (statements) |child_node_id| {
                        _ = try self.compileStatement(child_node_id);
                    }
                }

                try self.exitScope();

                return 0;
            },

            .expression_if => {
                const extra = self.ast.getExtra(node.data.extra_id, IfExtra);

                const reg_condition = try self.compileExpression(extra.condition);

                // Error and null evaluate to false. Should we use a explicit implementation for this instead of relying on falseness?
                const pos_jump_else = try self.emitJump(.jump_if_false, reg_condition);

                self.enterScope();
                if (extra.then_capture) |then_capture_id| {
                    const node_capture = self.ast.nodes.items[then_capture_id];
                    assert(node_capture.tag == .declaration_const);

                    const capture_extra = self.ast.getExtra(node_capture.data.extra_id, DeclarationExtra);
                    const capture_name_id = capture_extra.name_id;
                    const void_identifier_id = try self.ast.string_table.add("_");

                    if (capture_name_id != void_identifier_id) {
                        _ = try self.addLocal(capture_name_id, reg_condition, true, false);
                    }
                }

                const reg_result = self.context.next_free_reg;
                try self.compileExpressionEnsureRegister(extra.then_branch, reg_result);

                try self.exitScope();

                const pos_jump_end = try self.emitJump(.jump, 0);

                // patch jump_else to jump to else branch
                self.patchJump(pos_jump_else);

                if (extra.else_branch) |else_branch_id| {
                    self.enterScope();
                    if (extra.else_capture) |else_capture_id| {
                        const node_capture = self.ast.nodes.items[else_capture_id];
                        assert(node_capture.tag == .declaration_const);

                        const capture_extra = self.ast.getExtra(node_capture.data.extra_id, DeclarationExtra);
                        const capture_name_id = capture_extra.name_id;
                        const void_identifier_id = try self.ast.string_table.add("_");

                        if (capture_name_id != void_identifier_id) {
                            _ = try self.addLocal(capture_name_id, reg_condition, true, false);
                        }
                    }

                    try self.compileExpressionEnsureRegister(else_branch_id, reg_result);
                    try self.exitScope();
                }

                // patch jump at the end of then branch to jump to the end of else branch
                self.patchJump(pos_jump_end);

                return reg_result;
            },

            // access

            .identifier_expr => {
                if (self.resolveLocal(node.data.string_id)) |reg_identifier| {
                    return reg_identifier;
                } else |_| {
                    const reg_identifier = self.allocateRegister();
                    self.freeRegister();

                    const upvalue_index = self.resolveUpValue(node.data.string_id) catch unreachable; // identifier has to be somewhere (checked by semantic analyser)
                    try self.emitInstruction(Instruction.fromABC(.load_upvalue, reg_identifier, upvalue_index, 0));

                    return reg_identifier;
                }
            }, // assured by semyntc analyser
            .call => {
                const extra = self.ast.getExtra(node.data.extra_id, CallExtra);

                const snapshot = self.context.next_free_reg;

                const reg_callee = self.allocateRegister();

                try self.compileExpressionEnsureRegister(extra.callee, reg_callee);

                var arg_count: u8 = 0;
                if (extra.args_start) |args_start| {
                    var iterator = NodeListIterator.init(self.ast, args_start);
                    const reg_start = self.context.next_free_reg;

                    while (iterator.next()) |arg_node_id| {
                        _ = try self.compileExpressionEnsureRegister(arg_node_id, reg_start + arg_count);
                        _ = self.allocateRegister();
                        arg_count += 1;
                    }
                }

                try self.emitInstruction(Instruction.fromABC(.call, reg_callee, reg_callee, arg_count));
                self.context.next_free_reg = snapshot;
                return reg_callee;
            },

            //unary operations
            .negate => self.emitUnaryOp(.negate, &node),
            .logical_not => self.emitUnaryOp(.logical_not, &node),

            // binary operations
            .binary_add => {
                const extra = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);
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

            .logical_and => {
                const extra = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);
                const reg_result = self.allocateRegister();
                self.freeRegister();

                try self.compileExpressionEnsureRegister(extra.lhs, reg_result);
                const pos_end_jump = try self.emitJump(.jump_if_false, reg_result);
                try self.compileExpressionEnsureRegister(extra.rhs, reg_result);
                self.patchJump(pos_end_jump);

                return reg_result;
            },
            .logical_or => {
                const extra = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);
                const reg_result = self.allocateRegister();
                self.freeRegister();

                try self.compileExpressionEnsureRegister(extra.lhs, reg_result);
                const pos_end_jump = try self.emitJump(.jump_if_true, reg_result);
                try self.compileExpressionEnsureRegister(extra.rhs, reg_result);
                self.patchJump(pos_end_jump);

                return reg_result;
            },
        };
    }

    inline fn compileExpressionEnsureRegister(self: *Compiler, node_id: ast.NodeId, register: RegisterId) !void {
        const result = try self.compileExpression(node_id);
        if (result != register) {
            try self.emitInstruction(Instruction.fromABC(.move, register, result, 0));
            // if (register <= self.context.next_free_reg) {
            //     self.context.next_free_reg = register + 1;
            // }
        }
    }

    inline fn allocateRegister(self: *Compiler) RegisterId {
        const next_free = self.context.next_free_reg;
        self.context.next_free_reg += 1;
        self.context.max_registers.* = @max(self.context.next_free_reg, self.context.max_registers.*);
        return next_free;
    }

    inline fn freeRegister(self: *Compiler) void {
        self.context.next_free_reg -= 1;
    }

    inline fn emitInstruction(self: *Compiler, instruction: Instruction) !void {
        try self.context.chunk.emit(instruction);
    }

    fn emitUnaryOp(self: *Compiler, opcode: OpCode, node: *const Node) !RegisterId {
        const snapshot = self.context.next_free_reg;

        const reg_rhs = try self.compileExpression(node.data.node_id);
        const reg_dest = if (reg_rhs < snapshot) snapshot else reg_rhs;

        try self.emitInstruction(Instruction.fromABC(opcode, reg_dest, reg_rhs, 0));

        // free all regs
        self.context.next_free_reg = snapshot;
        return reg_dest;
    }

    fn emitBinaryOp(self: *Compiler, opcode: OpCode, node: *const Node) !RegisterId {
        const extra = self.ast.getExtra(node.data.extra_id, ast.BinaryOpExtra);

        const snapshot = self.context.next_free_reg;

        const reg_lhs = try self.compileExpression(extra.lhs);
        _ = self.allocateRegister();
        const reg_rhs = try self.compileExpression(extra.rhs);

        const reg_dest = if (reg_lhs < snapshot) snapshot else reg_lhs;

        try self.emitInstruction(Instruction.fromABC(opcode, reg_dest, reg_lhs, reg_rhs));

        // free all regs
        self.context.next_free_reg = snapshot;
        return reg_dest;
    }

    fn emitLoadConstant(self: *Compiler, opcode: OpCode, register: RegisterId, constant: Value) !void {
        const constant_id = try self.context.chunk.addConstant(constant);
        try self.emitInstruction(Instruction.fromAB(opcode, register, constant_id));
    }

    fn emitFunctionOrClosure(self: *Compiler, register: RegisterId, function: *ObjFunction) !void {
        const fn_value = Value.fromObject(function.asObject());

        if (function.upvalue_locations.len > 0) {
            const constant_id = try self.context.chunk.addConstant(fn_value);
            try self.emitInstruction(Instruction.fromAB(.create_closure, register, constant_id));
        } else {
            try self.emitLoadConstant(.load_const, register, fn_value);
        }
    }

    /// emits a InstructionAB with the given jump.
    /// Returns the position of the jump
    inline fn emitJump(self: *Compiler, opcode: OpCode, arg: u8) !usize {
        const pos = self.context.chunk.code.items.len;
        try self.emitInstruction(Instruction.fromAB(opcode, arg, 0));
        return pos;
    }

    inline fn patchJump(self: *Compiler, jump_pos: usize) void {
        const jump_offset: i32 = @intCast(self.context.chunk.code.items.len - jump_pos);
        assert(jump_offset > 0);
        self.context.chunk.code.items[jump_pos].ab.b = @intCast(jump_offset);
    }

    /// bind a variable to a register
    fn addLocal(self: *Compiler, name_id: StringId, register: RegisterId, is_initialized: bool, owns_register: bool) !usize {
        // std.debug.print("## addLocal {{\n", .{});
        // std.debug.print("##   name: {s}\n", .{self.ast.string_table.get(name_id)});
        // std.debug.print("##   depth: {d}\n", .{self.scope_depth});
        // std.debug.print("##   reg_slot: {d}\n", .{register});
        // std.debug.print("##   is_initialized: {}\n", .{is_initialized});
        // std.debug.print("## }}\n", .{});
        // std.debug.print("\n", .{});

        const index = self.context.locals.items.len;
        try self.context.locals.append(.{
            .name_id = name_id,
            .depth = self.context.scope_depth,
            .reg_slot = register,
            .owns_register = owns_register,
            .is_captured = false,
            .is_initialized = is_initialized,
        });
        return index;
    }

    fn initializeLocal(self: *Compiler, name_id: StringId) Error!void {
        for (self.context.locals.items) |*local| {
            if (local.name_id == name_id) {
                local.*.is_initialized = true;
                return;
            }
        }
        return Error.UndefinedIdentifier;
    }

    /// searches for the register of a variable in the current context
    inline fn resolveLocal(self: *const Compiler, name_id: StringId) Error!RegisterId {
        return try self.resolveLocalInContext(&self.context, name_id);
    }

    /// searches for the register of a variable in the given context
    inline fn resolveLocalInContext(_: *const Compiler, context: *const CompilerContext, name_id: StringId) Error!RegisterId {
        var local_index: isize = @as(isize, @intCast(context.locals.items.len)) - 1;
        while (local_index >= 0) : (local_index -= 1) {
            const local = context.locals.items[@intCast(local_index)];
            if (local.name_id == name_id) return local.reg_slot;
        }

        return Error.UndefinedIdentifier;
    }

    inline fn resolveUpValue(self: *Compiler, name_id: StringId) Error!RegisterId {
        return try self.resolveUpValueInContext(&self.context, name_id);
    }

    /// searches and/or creates an UpValue recursivly in all contexts
    inline fn resolveUpValueInContext(self: *Compiler, context: *CompilerContext, name_id: StringId) Error!u8 {
        if (context.parent_context) |parent_context| {
            // check if variable is local
            if (self.resolveLocalInContext(parent_context, name_id)) |reg_local| {
                parent_context.locals.items[reg_local].is_captured = true;
                return self.addUpValue(context, reg_local, true);
            } else |err| {
                return err;
            }

            // recursively check search the variable in outer scopes
            if (self.resolveUpValueInContext(parent_context, name_id)) |upvalue_index| {
                return try self.addUpValue(context, upvalue_index, false);
            } else |err| {
                return err;
            }
        }

        unreachable; // variable must be anywhere (checked by semantic analyser)
    }

    fn addUpValue(_: *Compiler, context: *CompilerContext, index: u8, is_local: bool) Error!u8 {
        for (context.upvalues.items, 0..) |upvalue, i| {
            if (upvalue.index == index and upvalue.is_local == is_local) {
                return @intCast(i);
            }
        }

        const upvalue_index = context.upvalues.items.len;
        if (upvalue_index >= std.math.maxInt(u8)) {
            return Error.UpValueOverflow;
        }

        try context.upvalues.append(.{
            .index = index,
            .is_local = is_local,
        });

        return @intCast(upvalue_index);
    }

    fn enterScope(self: *Compiler) void {
        self.context.scope_depth += 1;
        // TODO error handling (overflow of scopes?)
    }

    fn exitScope(self: *Compiler) Error!void {
        self.context.scope_depth -= 1;
        // TODO error handlich (underflow of scopes?)
        var any_captured = false;
        while (self.context.locals.items.len > 0 and self.context.locals.items[self.context.locals.items.len - 1].depth > self.context.scope_depth) {
            const local = self.context.locals.pop();

            // std.debug.print("## popLocal {{\n", .{});
            // std.debug.print("##   name: {s}\n", .{self.ast.string_table.get(local.?.name_id)});
            // std.debug.print("##   depth: {d}\n", .{local.?.depth});
            // std.debug.print("##   reg_slot: {d}\n", .{local.?.reg_slot});
            // std.debug.print("##   is_initialized: {}\n", .{local.?.is_initialized});
            // std.debug.print("## }}\n", .{});
            // std.debug.print("\n", .{});

            if (local.?.owns_register) {
                if (local.?.is_captured) {
                    any_captured = true;
                }
                self.context.next_free_reg = local.?.reg_slot;
            }
        }

        try self.emitInstruction(Instruction.fromABC(.close_upvalue, 0, self.context.next_free_reg, 0));
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

const BuildinFunction = as.BuildinFunction;
const NodeId = as.frontend.ast.NodeId;
const RegisterId = as.runtime.RegisterId;
const StringId = as.common.StringId;

const NodeListIterator = as.frontend.ast.NodeListIterator;
const AssignmentExtra = as.frontend.ast.AssignmentExtra;
const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;
const BlockExtra = as.frontend.ast.BlockExtra;
const CallExtra = as.frontend.ast.CallExtra;
const DeclarationExtra = as.frontend.ast.DeclarationExtra;
const FunctionExtra = as.frontend.ast.FunctionExtra;
const IfExtra = as.frontend.ast.IfExtra;

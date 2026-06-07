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
    allocator: std.mem.Allocator,
    parent_context: ?*CompilerContext = null,

    register_allocator: RegisterAllocator,
    chunk: *Chunk = undefined,
    locals: std.ArrayList(Local),
    upvalues: std.ArrayList(ObjFunction.UpValueLocation),
    scope_depth: i32,

    pub fn init(parent: ?*CompilerContext, chunk: *Chunk, allocator: std.mem.Allocator) CompilerContext {
        return .{
            .allocator = allocator,
            .parent_context = parent,

            .locals = .{},
            .upvalues = .{},
            .scope_depth = 0,

            .register_allocator = RegisterAllocator.init(),
            .chunk = chunk,
        };
    }

    pub fn deinit(self: *CompilerContext) void {
        self.locals.deinit(self.allocator);
        //self.upvalues.deinit(); ownership moves into compiled function
    }

    /// creates a snapshot of the register allocator
    pub fn snapshotRegisters(self: *CompilerContext) RegisterAllocator {
        return self.register_allocator.saveSnapshot();
    }

    /// restores a snapshot of the register allocator
    pub fn restoreRegisters(self: *CompilerContext, snapshot: RegisterAllocator) void {
        const current: RegisterAllocator = self.register_allocator.saveSnapshot();

        self.register_allocator.restoreSnapshot(snapshot);
        self.register_allocator.max_allocated = current.max_allocated;
        self.register_allocator.forced_next_reg = current.forced_next_reg;
    }

    /// a getter for the count of used registers
    pub fn getMaxRegisters(self: *const CompilerContext) RegisterId {
        return @intCast(self.register_allocator.getMaxAllocated());
    }

    pub fn ensureAllocated(self: *CompilerContext, register: RegisterId) void {
        self.register_allocator.ensureAllocated(register);
    }

    /// allocates a new register or returns a already released register
    pub fn getRegister(self: *CompilerContext) RegisterId {
        return self.register_allocator.allocate() catch unreachable; // when this fails, we don't have registers left and can not compile...
    }

    pub fn setNextRegister(self: *CompilerContext, register: RegisterId) void {
        self.register_allocator.forceNext(register) catch unreachable; // when this fails, the requested register is already allocated, which should not happen if the compiler is works correctly
    }

    /// allocates a new register
    pub fn allocateRegister(self: *CompilerContext) RegisterId {
        return self.register_allocator.allocate() catch unreachable; // when this fails, we don't have registers left and can not compile...
    }

    /// returns a freshly released register. So that it can be reused immediately
    pub fn getTmpRegister(self: *CompilerContext) RegisterId {
        return self.register_allocator.allocateTemporary() catch unreachable; // when this fails, we don't have registers left and can not compile...
    }

    /// releases a register for later use
    pub fn releaseRegister(self: *CompilerContext, reg: RegisterId) void {
        self.register_allocator.free(reg);
    }
};

pub const Compiler = struct {
    pub const Error = error{
        UndefinedIdentifier,
        UninitializedIdentifier,

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
        try self.garbage_collector.temp_objects.append(self.allocator, function.asObject());

        self.context = CompilerContext.init(
            null,
            &function.chunk,
            self.allocator,
        );
        defer self.context.deinit();

        for (buildin_functions) |buildin| {
            self.context.locals.append(self.allocator, .{
                .name_id = buildin.name_id,
                .depth = 0,
                .reg_slot = 0,
                .owns_register = true,
                .is_captured = false,
                .is_initialized = true,
            }) catch {
                @panic("failed to register natives");
            };
            _ = self.context.getRegister();
        }
        defer {
            for (buildin_functions) |_| {
                _ = self.context.locals.pop();
                //                self.context.releaseRegister(reg: u8);
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

        function.max_registers = self.context.getMaxRegisters();

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
                    const reg_var = self.context.getRegister();
                    _ = try self.addLocal(extra.name_id, reg_var, false, true);
                },
                .expression_function => {
                    const fn_extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);

                    if (fn_extra.name_id) |name_id| {
                        const result_reg: RegisterId = self.context.getRegister();
                        _ = try self.addLocal(name_id, result_reg, true, true);

                        const fn_obj = try self.compileFunction(node_id);
                        try self.garbage_collector.temp_objects.append(self.allocator, fn_obj.asObject());

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
        try self.garbage_collector.temp_objects.append(self.allocator, function.asObject());

        var parent_context = self.context;
        var fn_context = CompilerContext.init(
            &parent_context,
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
                const parameter_reg = self.context.getRegister();
                _ = try self.addLocal(parameter_node.data.string_id, parameter_reg, true, true);
            }
        }

        // compile function body
        try self.compileStatement(fn_extra.body);
        try self.emitInstruction(Instruction.fromABC(.call_return, 0, 0, 0));

        try self.exitScope();

        function.max_registers = self.context.getMaxRegisters();
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
                const register = self.resolveLocal(extra.name_id, false) catch unreachable; // should not fail, since its added while hoisting

                if (extra.init_value) |init_value_id| {
                    try self.compileExpressionEnsureRegister(init_value_id, register);
                    self.context.ensureAllocated(register);
                    self.initializeLocal(extra.name_id) catch unreachable; // should not fail, since its added while hoisting
                }
            },
            // statements
            .statement_return => {
                const reg = try self.compileExpression(node.data.node_id);
                try self.emitInstruction(Instruction.fromABC(.call_return, 0, reg, 1));
            },
            else => { // expression statements
                const snapshot = self.context.snapshotRegisters();
                _ = try self.compileExpression(node_id);
                self.context.restoreRegisters(snapshot);
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
                const register = self.context.getTmpRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeNull(),
                );
                return register;
            },
            .literal_bool => {
                const register = self.context.getTmpRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeBool(node.data.bool_value),
                );
                return register;
            },
            .literal_int => {
                const register = self.context.getTmpRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeInteger(node.data.int_value),
                );
                return register;
            },
            .literal_float => {
                const register = self.context.getTmpRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeFloat(node.data.float_value),
                );
                return register;
            },
            .literal_error => {
                const register = self.context.getTmpRegister();

                try self.emitLoadConstant(
                    .load_const,
                    register,
                    Value.makeErrorValue(node.data.error_value),
                );
                return register;
            },

            // objects
            .object_string => {
                const register = self.context.getTmpRegister();

                const string_data = self.ast.string_table.get(node.data.string_id);
                const string_object = ObjString.copydata(string_data, self.garbage_collector).asObject();

                try self.garbage_collector.temp_objects.append(self.allocator, string_object);
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
                const target_node = self.ast.nodes.items[extra.target]; // semantic analyser assures that this is an expression_identifier

                if (self.resolveLocal(target_node.data.string_id, false)) |reg_target| {
                    try self.compileExpressionEnsureRegister(extra.source, reg_target);
                    self.initializeLocal(target_node.data.string_id) catch unreachable; // identifier has to be somewhere (checked by semantic analyser)

                    return reg_target;
                } else |_| {
                    const reg_target = self.context.getTmpRegister();

                    const upvalue_index = self.resolveUpValue(target_node.data.string_id) catch unreachable; // identifier has to be somewhere (checked by semantic analyser)
                    try self.compileExpressionEnsureRegister(extra.source, reg_target);
                    try self.emitInstruction(Instruction.fromABC(.store_upvalue, upvalue_index, reg_target, 0));
                    self.initializeLocal(target_node.data.string_id) catch unreachable; // identifier has to be somewhere (checked by semantic analyser)

                    return reg_target;
                }
            },
            .expression_function => {
                // only anonymous functions. Named functions are hoisted. See fn hoistScan()
                const fn_extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);

                if (fn_extra.name_id == null) {
                    const result_reg: RegisterId = self.context.getTmpRegister();

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

                const reg_result = self.context.getTmpRegister();
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

            .expression_identifier => {
                if (self.resolveLocal(node.data.string_id, true)) |reg_identifier| {
                    return reg_identifier;
                } else |_| {
                    const reg_identifier = self.context.getTmpRegister();

                    const upvalue_index = self.resolveUpValue(node.data.string_id) catch unreachable; // identifier has to be somewhere (checked by semantic analyser)
                    try self.emitInstruction(Instruction.fromABC(.load_upvalue, reg_identifier, upvalue_index, 0));

                    return reg_identifier;
                }
            }, // assured by semyntc analyser
            .call => {
                const extra = self.ast.getExtra(node.data.extra_id, CallExtra);

                var reg_return: RegisterId = undefined;
                const reg_callee = try self.compileExpression(extra.callee);

                if (extra.args) |args| {
                    var args_start: ?usize = null;
                    for (args) |arg_node_id| {
                        const reg_arg = try self.compileExpression(arg_node_id);
                        const arg_index = self.context.chunk.addArgument(reg_arg) catch unreachable;
                        if (args_start == null) {
                            args_start = arg_index;
                        }
                    }
                    reg_return = self.context.getTmpRegister();
                    try self.emitInstruction(Instruction.fromABC(.op_call, reg_return, reg_callee, 0));
                    try self.emitInstruction(Instruction.fromAB(.op_call_args, @intCast(args.len), @intCast(args_start.?)));
                } else {
                    reg_return = self.context.getTmpRegister();
                    try self.emitInstruction(Instruction.fromABC(.op_call, reg_return, reg_callee, 0));
                }

                return reg_return;
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
                const reg_result = self.context.getTmpRegister();

                try self.compileExpressionEnsureRegister(extra.lhs, reg_result);
                const pos_end_jump = try self.emitJump(.jump_if_false, reg_result);
                try self.compileExpressionEnsureRegister(extra.rhs, reg_result);
                self.patchJump(pos_end_jump);

                return reg_result;
            },
            .logical_or => {
                const extra = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);
                const reg_result = self.context.getTmpRegister();

                try self.compileExpressionEnsureRegister(extra.lhs, reg_result);
                const pos_end_jump = try self.emitJump(.jump_if_true, reg_result);
                try self.compileExpressionEnsureRegister(extra.rhs, reg_result);
                self.patchJump(pos_end_jump);

                return reg_result;
            },
        };
    }

    inline fn compileExpressionEnsureRegister(self: *Compiler, node_id: ast.NodeId, register: RegisterId) !void {
        self.context.setNextRegister(register);
        const result = try self.compileExpression(node_id);

        // make sure the given register is used. (could happen when the compiled expressen uses context.allocateRegister() instead of getRegister())
        if (result != register) {
            try self.emitInstruction(Instruction.fromABC(.move, register, result, 0));
        }
    }

    inline fn emitInstruction(self: *Compiler, instruction: Instruction) !void {
        try self.context.chunk.emit(instruction);
    }

    fn emitUnaryOp(self: *Compiler, opcode: OpCode, node: *const Node) !RegisterId {
        const snapshot = self.context.snapshotRegisters();

        const reg_rhs = try self.compileExpression(node.data.node_id);
        const reg_dest = self.context.getTmpRegister();

        try self.emitInstruction(Instruction.fromABC(opcode, reg_dest, reg_rhs, 0));

        // free all regs
        self.context.restoreRegisters(snapshot);
        return reg_dest;
    }

    fn emitBinaryOp(self: *Compiler, opcode: OpCode, node: *const Node) !RegisterId {
        // TODO: optimizze, when evaluated into var - lhs is wrtten in var but result is written in tmp and moved to var
        const extra = self.ast.getExtra(node.data.extra_id, ast.BinaryOpExtra);

        // TODO: snapshots still needed?
        const snapshot = self.context.snapshotRegisters();

        const reg_lhs = try self.compileExpression(extra.lhs);
        self.context.ensureAllocated(reg_lhs);
        const reg_rhs = try self.compileExpression(extra.rhs);

        // when lhs is a variable, the register must not be reused!
        if (!snapshot.isAllocated(reg_lhs)) {
            self.context.releaseRegister(reg_lhs);
        }

        const reg_dest = self.context.getTmpRegister();

        try self.emitInstruction(Instruction.fromABC(opcode, reg_dest, reg_lhs, reg_rhs));

        // free all regs
        self.context.restoreRegisters(snapshot);
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
        try self.context.locals.append(self.allocator, .{
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
        const locals = self.context.locals.items;
        var i: usize = locals.len;
        while (i > 0) {
            i -= 1;
            var local = &locals[i];
            if (local.name_id == name_id) {
                local.is_initialized = true;
                return;
            }
        }

        return Error.UndefinedIdentifier;
    }

    /// searches for the register of a variable in the current context
    inline fn resolveLocal(self: *const Compiler, name_id: StringId, comptime assert_initialized: bool) Error!RegisterId {
        return try self.resolveLocalInContext(&self.context, name_id, assert_initialized);
    }

    /// searches for the register of a variable in the given context
    inline fn resolveLocalInContext(_: *const Compiler, context: *const CompilerContext, name_id: StringId, comptime assert_initialized: bool) Error!RegisterId {
        var local_index: isize = @as(isize, @intCast(context.locals.items.len)) - 1;
        while (local_index >= 0) : (local_index -= 1) {
            const local = context.locals.items[@intCast(local_index)];

            if (local.name_id == name_id) {
                if (assert_initialized and local.is_initialized == false) {
                    // if we are looking for an initialized local, it might be shadowed
                    continue;
                }
                if (!assert_initialized or local.is_initialized) {
                    return local.reg_slot;
                } else {
                    return Error.UninitializedIdentifier;
                }
            }
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
            if (self.resolveLocalInContext(parent_context, name_id, false)) |reg_local| {
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

    fn addUpValue(self: *Compiler, context: *CompilerContext, index: u8, is_local: bool) Error!u8 {
        for (context.upvalues.items, 0..) |upvalue, i| {
            if (upvalue.index == index and upvalue.is_local == is_local) {
                return @intCast(i);
            }
        }

        const upvalue_index = context.upvalues.items.len;
        if (upvalue_index >= std.math.maxInt(u8)) {
            return Error.UpValueOverflow;
        }

        try context.upvalues.append(self.allocator, .{
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
                self.context.releaseRegister(local.?.reg_slot);
            }
        }

        // TODO: closing upvalues is broken
        // try self.emitInstruction(Instruction.fromABC(.close_upvalue, 0, self.context.next_free_reg, 0));
    }
};

const instructions = @import("instruction.zig");
pub const Instruction = instructions.Instruction;
pub const Chunk = instructions.Chunk;

pub const ConstantId = instructions.ConstantId;
pub const OpCode = instructions.OpCode;

const register_allocator = @import("register_allocator.zig");
pub const RegisterAllocator = register_allocator.RegisterAllocator;
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

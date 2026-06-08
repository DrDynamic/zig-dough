const CurrentScope = enum {
    unknown,
    if_condition,
};

const BlockContext = struct {
    label: ?StringId,
    expected_type: TypeId,
    has_break: bool = false,
};

const FunctionContext = struct {
    node_id: NodeId,
    return_type: TypeId,
};

const SemanticAnalyserContext = struct {
    allocator: std.mem.Allocator,
    current_scope: CurrentScope = CurrentScope.unknown,

    block_stack: std.ArrayList(BlockContext),
    function_stack: std.ArrayList(FunctionContext),

    pub fn init(allocator: std.mem.Allocator) SemanticAnalyserContext {
        return .{
            .allocator = allocator,
            .current_scope = CurrentScope.unknown,
            .block_stack = .{},
            .function_stack = .{},
        };
    }

    pub fn deinit(self: *SemanticAnalyserContext) void {
        self.block_stack.deinit(self.allocator);
        self.function_stack.deinit(self.allocator);
    }

    pub fn pushFunction(self: *SemanticAnalyserContext, node_id: NodeId, fn_extra: FunctionExtra) !void {
        try self.function_stack.append(self.allocator, .{
            .node_id = node_id,
            .return_type = fn_extra.return_type,
        });
    }

    pub fn popFunction(self: *SemanticAnalyserContext) ?FunctionContext {
        return self.function_stack.pop();
    }

    pub fn currentFunction(self: *const SemanticAnalyserContext) ?FunctionContext {
        return self.function_stack.getLastOrNull();
    }
};

pub const SemanticAnalyser = struct {
    pub const Error = error{
        ArgumentMissmatch,
        OutOfMemory,
        UnhandledNodeType,
        TypeMismatch,
        TypeMissing,
        IncompatibleTypes,
        RedeclarationError,
        UndefinedIdentifier,
        UnsupportedOperand,
        PointlessCapture,
        MissingCapture,
        IllegalMutation,
        InvalidAssignmentTarget,
        IllegalAssignment,
        UnexpectedReturn,
        NotCallable,
        MissingReturn,
        //
        NotFound,
    };

    allocator: std.mem.Allocator,
    ast: *AST,
    error_reporter: *ErrorReporter,
    symbol_table: SymbolTable,
    context: SemanticAnalyserContext,

    pub fn init(error_reporter: *ErrorReporter, allocator: std.mem.Allocator) SemanticAnalyser {
        return .{
            .allocator = allocator,
            .ast = undefined,
            .error_reporter = error_reporter,
            .symbol_table = SymbolTable.init(allocator),
            .context = SemanticAnalyserContext.init(allocator),
        };
    }

    pub fn deinit(self: *SemanticAnalyser) void {
        self.symbol_table.deinit();
        self.context.deinit();
    }

    pub fn analyseAst(self: *SemanticAnalyser, ast: *AST, buildin_functions: []BuildinFunction) void {
        self.ast = ast;

        for (buildin_functions) |buildin| {
            // TODO: resolve temporary fix:
            const parameter_type_id = self.ast.type_pool.getOrCreateUnionType(&.{ TypePool.ANYERROR, TypePool.NULL, TypePool.ANY }) catch unreachable;

            const type_id = self.ast.type_pool.getOrCreateFunctionType(&.{parameter_type_id}, buildin.return_type_id) catch unreachable;

            self.symbol_table.declare(
                buildin.name_id,
                type_id,
                0,
                false,
            ) catch {
                @panic("failed to register buildin");
            };
            self.symbol_table.initialize(buildin.name_id) catch {
                @panic("failed to register buildin");
            };
        }
        defer {
            for (buildin_functions) |_| {
                _ = self.symbol_table.pop();
            }
        }

        const roots = self.ast.getRoots();
        self.hoistScan(roots) catch {
            ast.invalidate();
        };

        for (roots) |node_id| {
            _ = self.analyse(node_id) catch {
                ast.invalidate();
                break;
            };
        }
    }

    /// registers names and types of symbols that are hoisted
    fn hoistScan(self: *SemanticAnalyser, node_ids: []const NodeId) Error!void {
        for (node_ids) |node_id| {
            var node = &self.ast.nodes.items[node_id];
            const resolved_type = switch (node.tag) {
                .expression_function => try self.analyseFunctionDeclaration(node_id),
                else => node.resolved_type_id,
            };
            node.resolved_type_id = resolved_type;
        }
    }

    fn analyse(self: *SemanticAnalyser, node_id: NodeId) Error!TypeId {
        var node = &self.ast.nodes.items[node_id];

        const resolved_type: TypeId = switch (node.tag) {
            .node_list => unreachable,
            // literals
            .literal_null => TypePool.NULL,
            .literal_bool => TypePool.BOOL,
            .literal_int => TypePool.INT,
            .literal_float => TypePool.FLOAT,
            .literal_error => case: {
                const error_id = node.data.error_value;
                break :case self.ast.type_pool.getTypeByErrorId(error_id).?;
            },

            // objects
            .object_string => TypePool.STRING,

            // declarations
            .declaration_error_set => TypePool.VOID,
            .declaration_type => node.resolved_type_id,
            .declaration_var => try self.analyseDeclaration(node_id, true),
            .declaration_const => try self.analyseDeclaration(node_id, false),
            .declaration_parameter => unreachable, // analysed in .expression_function

            // statements
            .statement_return => |_| case: {
                if (self.context.currentFunction()) |fn_context| {
                    const returned_type = try self.analyse(node.data.node_id);

                    if (!self.ast.type_pool.isAssignable(fn_context.return_type, returned_type)) {
                        try self.reportTypeMissmatch(node.*, fn_context.return_type, returned_type, "can not return {[source_type]s} as {[target_type]s}");

                        const return_type_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, fn_context.return_type, self.ast.string_table);
                        defer self.allocator.free(return_type_name);

                        const hint_message = try std.fmt.allocPrint(self.allocator, "fn has return type {s}", .{return_type_name});
                        defer self.allocator.free(hint_message);

                        const fn_node = self.ast.nodes.items[fn_context.node_id];
                        self.error_reporter.semanticAnalyserHint(self, fn_node, hint_message);
                        return Error.TypeMismatch;
                    }
                } else {
                    self.error_reporter.semanticAnalyserError(self, Error.UnexpectedReturn, node.*, "return statement ourside of fn");
                    return Error.UnexpectedReturn;
                }
                break :case try self.analyse(node.data.node_id);
            },

            // expressions
            .expression_assignment => case: {
                if (self.context.current_scope == .if_condition) {
                    self.error_reporter.semanticAnalyserError(self, Error.IllegalAssignment, node.*, "assignments in if conditions are not allowed");
                    return Error.IllegalAssignment;
                }

                const extra = self.ast.getExtra(node.data.extra_id, AssignmentExtra);
                const target_node = self.ast.nodes.items[extra.target];

                if (target_node.tag != .expression_identifier) {
                    self.error_reporter.semanticAnalyserError(self, Error.InvalidAssignmentTarget, node.*, "invalid assignment target");
                    return Error.InvalidAssignmentTarget;
                }

                const maybe_symbol = self.symbol_table.lookup(target_node.data.string_id);

                if (maybe_symbol == null) {
                    self.error_reporter.semanticAnalyserError(self, Error.UndefinedIdentifier, target_node, "undefined identifier");
                    return Error.UndefinedIdentifier;
                }

                if (!maybe_symbol.?.is_mutable) {
                    self.error_reporter.semanticAnalyserError(self, Error.IllegalMutation, node.*, "mutation not allowd");
                    return Error.IllegalMutation;
                }

                const source_type = try self.analyse(extra.source);
                const symbol_name = self.ast.string_table.get(maybe_symbol.?.name_id);
                _ = symbol_name;
                if (!self.ast.type_pool.isAssignable(maybe_symbol.?.type_id, source_type)) {
                    const source_node = self.ast.nodes.items[extra.source];
                    try self.reportNotAssignable(source_node, maybe_symbol.?.type_id, source_type);

                    const declaration_node = self.ast.nodes.items[maybe_symbol.?.node_id];
                    self.error_reporter.semanticAnalyserHint(self, declaration_node, "declared here:");

                    return Error.TypeMismatch;
                }

                self.symbol_table.initialize(maybe_symbol.?.name_id) catch unreachable; // existence is checked above

                break :case source_type;
            },
            .expression_function => try self.analyseFunctionDefinition(node_id),
            .expression_grouping => try self.analyse(node.data.node_id),
            .expression_block => |_| case: {
                self.symbol_table.enterScope();
                const extra = self.ast.getExtra(node.data.extra_id, BlockExtra);

                if (extra.statements) |statements| {
                    try self.hoistScan(statements);

                    for (statements) |list_node_id| {
                        _ = self.analyse(list_node_id) catch {
                            self.ast.invalidate();
                            break;
                        };
                    }
                }

                self.symbol_table.exitScope();

                break :case TypePool.VOID;
            },
            .expression_if => |_| case: {
                var maybe_err: ?Error = null;
                const extra = self.ast.getExtra(node.data.extra_id, IfExtra);

                self.context.current_scope = .if_condition;
                const type_condition = try self.analyse(extra.condition);
                self.context.current_scope = .unknown;

                self.symbol_table.enterScope();

                if (type_condition == TypePool.BOOL) {
                    self.assertNodeIdIsNull(extra.then_capture, Error.PointlessCapture, "then capture is pointless (capture is always true)") catch |err| {
                        maybe_err = err;
                    };
                    self.assertNodeIdIsNull(extra.else_capture, Error.PointlessCapture, "else capture is pointless (capture is always false)") catch |err| {
                        maybe_err = err;
                    };

                    if (maybe_err) |err| {
                        return err;
                    }
                } else if (self.ast.type_pool.isErrorUnion(type_condition)) {
                    self.registerIfCaptureOrFail(
                        extra.then_branch,
                        extra.then_capture,
                        try self.ast.type_pool.getOrCreateNotErrorUnionType(type_condition),
                        "missing then capture for ErrorUnion condition",
                    ) catch |err| {
                        maybe_err = err;
                    };

                    if (extra.else_branch) |else_branch| {
                        self.registerIfCaptureOrFail(
                            else_branch,
                            extra.else_capture,
                            self.ast.type_pool.getErrorSetFromTypeUnion(type_condition) catch unreachable,
                            "missing else capture for ErrorUnion condition",
                        ) catch |err| {
                            maybe_err = err;
                        };
                    }
                } else if (self.ast.type_pool.isNullable(type_condition)) {
                    self.registerIfCaptureOrFail(
                        extra.then_branch,
                        extra.then_capture,
                        try self.ast.type_pool.getOrCreateNotNullableType(type_condition),
                        "capture is pointless for Nullable condition (it is always null)",
                    ) catch |err| {
                        maybe_err = err;
                    };

                    try self.assertNodeIdIsNull(
                        extra.else_capture,
                        Error.PointlessCapture,
                        "capture is pointless for Nullable condition (it is always null)",
                    );
                } else {
                    const condition = self.ast.nodes.items[extra.condition];
                    self.error_reporter.semanticAnalyserError(self, Error.IncompatibleTypes, condition, "condition needs to evaluate to Bool, Nullable type or ErrorUnion");

                    const type_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, type_condition, self.ast.string_table);
                    defer self.allocator.free(type_name);

                    const hint_message = try std.fmt.allocPrint(self.allocator, "condition evaluates to {s}", .{type_name});
                    defer self.allocator.free(hint_message);

                    self.error_reporter.semanticAnalyserHint(self, condition, hint_message);
                    maybe_err = Error.IncompatibleTypes;
                }

                const initial_scope = try self.symbol_table.clone();

                const type_then = try self.analyse(extra.then_branch);
                var type_else = type_then;

                var then_scope = try self.symbol_table.clone();
                defer then_scope.deinit();

                self.symbol_table.deinit();
                self.symbol_table = initial_scope;

                if (extra.else_branch) |else_branch_id| {
                    type_else = try self.analyse(else_branch_id);

                    try self.symbol_table.mergeInitialized(&then_scope);
                }

                self.symbol_table.exitScope();

                if (maybe_err) |err| {
                    return err;
                }

                if (type_then == type_else) {
                    break :case type_then;
                } else {
                    break :case try self.ast.type_pool.getOrCreateUnionType(&[_]u32{ type_then, type_else });
                }
            },

            // access
            .expression_identifier => |_| case: {
                if (self.symbol_table.lookup(node.data.string_id)) |symbol| {
                    if (symbol.state != .Initialized) {
                        self.error_reporter.semanticAnalyserError(self, Error.UndefinedIdentifier, node.*, "can not read uninitialized variable");

                        const symbol_node = self.ast.nodes.items[symbol.node_id];
                        self.error_reporter.semanticAnalyserHint(self, symbol_node, "variable is declared here:");
                        return Error.UndefinedIdentifier;
                    }
                    break :case symbol.type_id;
                }

                self.error_reporter.semanticAnalyserError(self, Error.UndefinedIdentifier, node.*, "undefined identifier");
                return Error.UndefinedIdentifier;
            },
            // unary operations
            .negate => |_| case: {
                const type_rhs = try self.analyse(node.data.node_id);

                if (type_rhs == TypePool.INT or type_rhs == TypePool.FLOAT) {
                    break :case type_rhs;
                }

                const node_rhs = self.ast.nodes.items[node.data.node_id];
                self.error_reporter.semanticAnalyserError(self, Error.UnsupportedOperand, node_rhs, "operand must be a number");
                return Error.UnsupportedOperand;
            },
            .logical_not => |_| case: {
                const type_rhs = try self.analyse(node.data.node_id);

                if (type_rhs == TypePool.BOOL) {
                    break :case type_rhs;
                }

                const node_rhs = self.ast.nodes.items[node.data.node_id];
                self.error_reporter.semanticAnalyserError(self, Error.UnsupportedOperand, node_rhs, "operand must be Bool");
                return Error.UnsupportedOperand;
            },

            // binary operations
            .binary_add,
            .binary_sub,
            .binary_mul,
            .binary_div,
            => try self.analyseBinaryMath(node_id),
            .binary_equal,
            .binary_not_equal,
            .binary_less,
            .binary_less_equal,
            .binary_greater,
            .binary_greater_equal,
            => try self.analyseBinaryCompare(node_id),

            .call => |_| case: {
                const extra = self.ast.getExtra(node.data.extra_id, CallExtra);
                const type_callee = try self.analyse(extra.callee);
                const callee = self.ast.nodes.items[extra.callee];

                if (!self.ast.type_pool.isCallable(type_callee)) {
                    self.error_reporter.semanticAnalyserError(self, Error.NotCallable, node.*, "called value is not callable");
                    return Error.NotCallable;
                }

                // match arg count
                const signature = self.ast.type_pool.getCallableSignature(type_callee) catch unreachable; // assured by isCalable() above

                var args_count: usize = 0;
                if (extra.args) |args| {
                    args_count = args.len;
                }

                if (signature.param_types.len != args_count) {
                    const message = try std.fmt.allocPrint(self.allocator, "expects {d} arguments but got {d}", .{ signature.param_types.len, args_count });
                    defer self.allocator.free(message);

                    self.error_reporter.semanticAnalyserError(self, Error.ArgumentMissmatch, node.*, message);
                    self.error_reporter.semanticAnalyserHint(self, callee, "declaration:");

                    return Error.ArgumentMissmatch;
                }

                var had_type_missmatch = false;
                if (extra.args) |args| {
                    for (signature.param_types, 0..) |type_param, index| {
                        const arg_node_id = args[index];
                        const type_arg = try self.analyse(arg_node_id);

                        if (!self.ast.type_pool.isAssignable(type_param, type_arg)) {
                            const arg_node = self.ast.nodes.items[arg_node_id];
                            had_type_missmatch = true;
                            try self.reportNotAssignable(arg_node, type_param, type_arg);
                        }
                    }
                }

                if (had_type_missmatch) {
                    self.error_reporter.semanticAnalyserHint(self, callee, "declaration:");
                    return Error.TypeMismatch;
                }

                break :case signature.return_type;
            },
            // logical operations
            .logical_or,
            .logical_and,
            => try self.analyseBinaryLogical(node_id),
        };

        node.resolved_type_id = resolved_type;
        return resolved_type;
    }

    fn analyseDeclaration(self: *SemanticAnalyser, node_id: NodeId, is_mutable: bool) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const extra = self.ast.getExtra(node.data.extra_id, DeclarationExtra);

        // add variable to symbol table
        self.symbol_table.declare(
            extra.name_id,
            TypePool.UNRESOLVED,
            node_id,
            is_mutable,
        ) catch {
            try self.reportRedeclarationError(node, extra.name_id);
            return Error.RedeclarationError;
        };

        // analyse the initializer
        var inferred_type: TypeId = TypePool.UNRESOLVED;
        if (extra.init_value) |init_value_id| {
            inferred_type = try self.analyse(init_value_id);
            self.symbol_table.initialize(extra.name_id) catch unreachable; // will always be found (declared directly above)
        }

        var type_id: TypeId = undefined;

        if (inferred_type != TypePool.UNRESOLVED and extra.explicit_type != TypePool.UNRESOLVED) {
            // both types are present

            if (!self.ast.type_pool.isAssignable(extra.explicit_type, inferred_type)) {
                const init_node = self.ast.nodes.items[extra.init_value.?];
                try self.reportNotAssignable(init_node, extra.explicit_type, inferred_type);
                return Error.TypeMismatch;
            }

            type_id = extra.explicit_type;
        } else if (inferred_type != TypePool.UNRESOLVED and extra.explicit_type == TypePool.UNRESOLVED) {
            // only inferred type is present (Variable has no explicit type set)
            type_id = inferred_type;
        } else if (inferred_type == TypePool.UNRESOLVED and extra.explicit_type != TypePool.UNRESOLVED) {
            // only explicit type is present (variable has no initializer)
            type_id = extra.explicit_type;
        } else {
            // no type is present (variable has no initializer but the explicit ty<pe isn't set either)

            self.error_reporter.semanticAnalyserError(self, Error.TypeMissing, node, "declaration must have a type");

            const hint_fmt = "either explicit: e.g. '{[keyword]s} {[name]s}:string;' or implicit by assignment: e.g.'{[keyword]s} {[name]s} = \"\";' ";
            const hint_message = if (is_mutable)
                try std.fmt.allocPrint(self.allocator, hint_fmt, .{ .keyword = "var", .name = self.ast.string_table.get(extra.name_id) })
            else
                try std.fmt.allocPrint(self.allocator, hint_fmt, .{ .keyword = "const", .name = self.ast.string_table.get(extra.name_id) });
            defer self.allocator.free(hint_message);

            self.error_reporter.semanticAnalyserHint(self, node, hint_message);
            return Error.TypeMissing;
        }

        self.symbol_table.setType(extra.name_id, type_id) catch unreachable; // declared above

        return TypePool.VOID;
    }

    fn analyseFunctionDeclaration(self: *SemanticAnalyser, node_id: NodeId) Error!TypeId {
        // declaration is hoisted
        const node = self.ast.nodes.items[node_id];
        const extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);

        if (extra.name_id) |name_id| {
            self.symbol_table.declare(
                name_id,
                TypePool.UNRESOLVED,
                node_id,
                false,
            ) catch {
                try self.reportRedeclarationError(node, name_id);
                return Error.RedeclarationError;
            };
        }

        const type_id = try self.makeFunctionSignature(node_id);

        if (extra.name_id) |name_id| {
            self.symbol_table.setType(name_id, type_id) catch unreachable; // Error.NotFound is unreachabe (declared above)
            self.symbol_table.initialize(name_id) catch unreachable; // Error.NotFound is unreachabe (declared above)
        }

        return type_id;
    }

    fn makeFunctionSignature(self: *SemanticAnalyser, node_id: NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);

        var signature_buffer: [32]TypeId = undefined;
        var signature: []TypeId = &[_]TypeId{};
        if (extra.parameters) |parameters| {
            for (parameters, 0..) |parameter_node_id, index| {
                const parameter_node = self.ast.nodes.items[parameter_node_id];
                const parameter_type_id = parameter_node.resolved_type_id;

                signature_buffer[index] = parameter_type_id;
            }
            signature = signature_buffer[0..parameters.len];
        }

        return try self.ast.type_pool.getOrCreateFunctionType(signature, extra.return_type);
    }

    fn analyseFunctionDefinition(self: *SemanticAnalyser, node_id: NodeId) Error!TypeId {
        var node = &self.ast.nodes.items[node_id];
        const extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);

        if (node.resolved_type_id == TypePool.UNRESOLVED) {
            node.resolved_type_id = try self.makeFunctionSignature(node_id);
        }

        try self.context.pushFunction(node_id, extra);

        if (extra.parameters) |parameters| {
            for (parameters) |parameter_node_id| {
                const parameter_node = self.ast.nodes.items[parameter_node_id];
                const parameter_name = parameter_node.data.string_id;

                self.symbol_table.declare(
                    parameter_name,
                    parameter_node.resolved_type_id,
                    parameter_node_id,
                    false,
                ) catch {
                    try self.reportRedeclarationError(parameter_node, parameter_name);
                    return Error.RedeclarationError;
                };
                self.symbol_table.initialize(parameter_name) catch unreachable; // Error.NotFound is unreachabe (declared above)
            }
        }

        _ = try self.analyse(extra.body);

        const signature = self.ast.type_pool.getCallableSignature(node.resolved_type_id) catch unreachable; // NotCallable: we are sure it is a callable
        if (signature.return_type != TypePool.VOID) {
            if (self.checkReturnsOnAllPaths(extra.body) == false) {
                const type_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, signature.return_type, self.ast.string_table);
                defer self.allocator.free(type_name);

                const error_message = try std.fmt.allocPrint(self.allocator, "function with non-void return type '{s}' implicitly returns", .{type_name});
                defer self.allocator.free(error_message);

                //TODO: add types als ast nodes
                self.error_reporter.semanticAnalyserError(self, Error.MissingReturn, node.*, error_message);

                // TODO: show hint: "control flow reaches end of body here" (marker at end of block node needed)

                return Error.MissingReturn;
            }
        }
        _ = self.context.popFunction();

        if (extra.name_id) |name_id| {
            self.symbol_table.initialize(name_id) catch unreachable; // Error.NotFound is unreachabe (declared while hoisting)
        }

        return node.resolved_type_id;
    }

    fn checkReturnsOnAllPaths(self: *SemanticAnalyser, node_id: NodeId) bool {
        const node = &self.ast.nodes.items[node_id];

        return switch (node.tag) {
            .statement_return => true,
            .expression_block => case: {
                const extra = self.ast.getExtra(node.data.extra_id, BlockExtra);
                if (extra.statements) |statements| {
                    for (statements) |statement_id| {
                        if (self.checkReturnsOnAllPaths(statement_id)) {
                            break :case true;
                        }
                    }
                }
                break :case false;
            },
            .expression_if => case: {
                const extra = self.ast.getExtra(node.data.extra_id, IfExtra);

                // we only check the branches if the else branch is present
                // otherwise we can not guaratee a return
                if (extra.else_branch) |else_branch| {
                    const if_returns = self.checkReturnsOnAllPaths(extra.then_branch);
                    const else_returns = self.checkReturnsOnAllPaths(else_branch);

                    if (if_returns and else_returns) {
                        break :case true;
                    }
                }
                break :case false;
            },
            else => false,
        };
    }

    fn analyseBinaryCompare(self: *SemanticAnalyser, node_id: NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);

        const left_type = try self.analyse(data.lhs);
        const right_type = try self.analyse(data.rhs);

        // TOD what can be compared to what?
        if (left_type == right_type) {
            return TypePool.BOOL;
        }

        if ((left_type == TypePool.INT and right_type == TypePool.FLOAT) or
            (left_type == TypePool.FLOAT and right_type == TypePool.INT))
        {
            // Implicitly promote int to float
            return TypePool.BOOL;
        }
        // For simplicity, assume binary operations return the same type as operands
        self.error_reporter.semanticAnalyserError(self, Error.IncompatibleTypes, node, "incompatible types");
        return error.IncompatibleTypes;
    }

    fn analyseBinaryMath(self: *SemanticAnalyser, node_id: NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);

        const left_type = try self.analyse(data.lhs);
        const right_type = try self.analyse(data.rhs);

        if (left_type == right_type) {
            return switch (left_type) {
                // TODO report rhs node
                TypePool.STRING => {
                    if (node.tag == .binary_add) {
                        // allow adding strings (concat)
                        return left_type;
                    }
                    self.error_reporter.semanticAnalyserError(self, Error.UnsupportedOperand, node, "unsupported operand types");
                    return Error.UnsupportedOperand;
                },
                TypePool.INT => left_type,
                TypePool.FLOAT => left_type,
                else => {
                    self.error_reporter.semanticAnalyserError(self, Error.UnsupportedOperand, node, "unsupported operand types");
                    return Error.UnsupportedOperand;
                },
            };
        }

        if ((left_type == TypePool.INT and right_type == TypePool.FLOAT) or
            (left_type == TypePool.FLOAT and right_type == TypePool.INT))
        {
            // Implicitly promote int to float
            return TypePool.FLOAT;
        }
        // For simplicity, assume binary operations return the same type as operands
        self.error_reporter.semanticAnalyserError(self, Error.IncompatibleTypes, node, "incompatible types");
        return error.IncompatibleTypes;
    }

    fn analyseBinaryLogical(self: *SemanticAnalyser, node_id: NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const extra = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);

        const lhs_type_id = try self.analyse(extra.lhs);
        const rhs_type_id = try self.analyse(extra.rhs);

        if (lhs_type_id != TypePool.BOOL or rhs_type_id != TypePool.BOOL) {
            self.error_reporter.semanticAnalyserError(self, Error.IncompatibleTypes, node, "incompatible types");
            return error.IncompatibleTypes;
        }
        return TypePool.BOOL;
    }

    inline fn registerIfCaptureOrFail(self: *SemanticAnalyser, branch_id: NodeId, maybe_capture_id: ?NodeId, capture_type_id: TypeId, message: []const u8) Error!void {
        if (maybe_capture_id) |capture_node_id| {
            const capture_node = &self.ast.nodes.items[capture_node_id];
            const capture_extra = self.ast.getExtra(capture_node.data.extra_id, DeclarationExtra);

            capture_node.resolved_type_id = capture_type_id;

            self.symbol_table.declare(
                capture_extra.name_id,
                capture_type_id,
                capture_node_id,
                false,
            ) catch {
                try self.reportRedeclarationError(capture_node.*, capture_node.data.string_id);
                return Error.RedeclarationError;
            };
            self.symbol_table.initialize(capture_extra.name_id) catch unreachable; // declared above
        } else {
            const branch_node = self.ast.nodes.items[branch_id];

            self.error_reporter.semanticAnalyserError(self, Error.MissingCapture, branch_node, message);
            return Error.MissingCapture;
        }
    }

    inline fn assertNodeIdIsNull(self: *SemanticAnalyser, node_id: ?NodeId, err: Error, message: []const u8) Error!void {
        if (node_id) |id| {
            const node = self.ast.nodes.items[id];
            self.error_reporter.semanticAnalyserError(self, err, node, message);
            return err;
        }
    }

    inline fn reportNotAssignable(self: *const SemanticAnalyser, node: Node, target_type_id: TypeId, source_type_id: TypeId) !void {
        try self.reportTypeMissmatch(node, target_type_id, source_type_id, "can not assign {[source_type]s} to {[target_type]s}");
    }

    inline fn reportTypeMissmatch(self: *const SemanticAnalyser, node: Node, target_type_id: TypeId, source_type_id: TypeId, comptime message: []const u8) !void {
        const target_type_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, target_type_id, self.ast.string_table);
        defer self.allocator.free(target_type_name);
        const source_type_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, source_type_id, self.ast.string_table);
        defer self.allocator.free(source_type_name);

        const error_message = try std.fmt.allocPrint(self.allocator, message, .{ .source_type = source_type_name, .target_type = target_type_name });
        defer self.allocator.free(error_message);

        self.error_reporter.semanticAnalyserError(self, Error.TypeMismatch, node, error_message);
    }

    inline fn reportRedeclarationError(self: *const SemanticAnalyser, node: Node, identifier_name: StringId) std.mem.Allocator.Error!void {
        const error_message = try std.fmt.allocPrint(self.allocator, "identifier '{s}' has already been declared", .{self.ast.string_table.get(identifier_name)});
        defer self.allocator.free(error_message);

        self.error_reporter.semanticAnalyserError(self, Error.RedeclarationError, node, error_message);

        const symbol_collision = self.symbol_table.lookup(identifier_name);
        const node_collision = self.ast.nodes.items[symbol_collision.?.node_id];
        self.error_reporter.semanticAnalyserHint(self, node_collision, "name is already declared here:");
    }
};

const std = @import("std");
const as = @import("as");

const ErrorReporter = as.common.reporting.ErrorReporter;

const AST = as.frontend.AST;
const SymbolTable = as.frontend.SymbolTable;
const TypePool = as.frontend.TypePool;

const BuildinFunction = as.BuildinFunction;
const NodeExtraId = as.frontend.ast.NodeExtraId;
const NodeId = as.frontend.ast.NodeId;
const Node = as.frontend.ast.Node;
const Symbol = as.frontend.Symbol;
const StringId = as.common.StringId;
const TypeId = as.frontend.TypeId;

const AssignmentExtra = as.frontend.ast.AssignmentExtra;
const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;
const BlockExtra = as.frontend.ast.BlockExtra;
const CallExtra = as.frontend.ast.CallExtra;
const DeclarationExtra = as.frontend.ast.DeclarationExtra;
const FunctionExtra = as.frontend.ast.FunctionExtra;
const IfExtra = as.frontend.ast.IfExtra;
const NodeListIterator = as.frontend.ast.NodeListIterator;

pub const SemanticAnalyser = struct {
    pub const Error = error{
        OutOfMemory,
        UnhandledNodeType,
        TypeMismatch,
        TypeMissing,
        IncompatibleTypes,
        RedeclarationError,
        UnknownIdentifier,
        UnsupportedOperand,
        PointlessCapture,
        MissingCapture,
        IllegalMutation,
        InvalidAssignmentTarget,
    };

    allocator: std.mem.Allocator,
    ast: *AST,
    error_reporter: *ErrorReporter,
    symbol_table: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, error_reporter: *ErrorReporter) !SemanticAnalyser {
        return .{
            .allocator = allocator,
            .ast = undefined,
            .error_reporter = error_reporter,
            .symbol_table = try SymbolTable.init(allocator),
        };
    }

    pub fn deinit(self: *SemanticAnalyser) void {
        self.symbol_table.deinit();
    }

    pub fn analyseAst(self: *SemanticAnalyser, ast: *AST) Error!void {
        self.ast = ast;

        for (ast.getRoots()) |node_id| {
            _ = self.analyse(node_id) catch |err| {
                ast.invalidate();
                return err;
            };
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

            // objects
            .object_string => TypePool.STRING,

            // declarations
            .declaration_var => try self.analyseDeclaration(node_id, true),
            .declaration_const => try self.analyseDeclaration(node_id, false),

            // statements
            .expression_grouping => try self.analyse(node.data.node_id),
            .expression_block => |_| case: {
                var iterator = NodeListIterator.init(self.ast, node.data.node_id);

                while (iterator.next()) |list_node_id| {
                    _ = try self.analyse(list_node_id);
                }

                break :case TypePool.VOID;
            },
            .expression_if => |_| case: {
                var maybe_err: ?Error = null;
                const extra = self.ast.getExtra(node.data.extra_id, IfExtra);

                const type_condition = try self.analyse(extra.condition);

                try self.symbol_table.enterScope();

                if (type_condition == TypePool.BOOL) {
                    if (extra.then_capture) |then_capture_id| {
                        const then_capture = self.ast.nodes.items[then_capture_id];
                        self.error_reporter.semanticAnalyserError(self, Error.PointlessCapture, then_capture, "then capture is pointless (capture is always true)");
                        maybe_err = Error.PointlessCapture;
                    }
                    if (extra.else_capture) |else_capture_id| {
                        const else_capture = self.ast.nodes.items[else_capture_id];
                        self.error_reporter.semanticAnalyserError(self, Error.PointlessCapture, else_capture, "else capture is pointless (it is always false)");
                        maybe_err = Error.PointlessCapture;
                    }
                } else if (self.ast.type_pool.isNullable(type_condition)) {
                    if (extra.then_capture) |then_capture| {
                        const capture_node = &self.ast.nodes.items[then_capture];
                        const capture_type = try self.ast.type_pool.getOrCreateNotNullableType(type_condition);
                        const capture_extra = self.ast.getExtra(capture_node.data.extra_id, VarDeclarationExtra);

                        capture_node.resolved_type_id = capture_type;

                        self.symbol_table.declare(capture_extra.name_id, .{
                            .name_id = capture_extra.name_id,
                            .type_id = capture_type,
                            .is_mutable = false,
                            .node_id = then_capture,
                        }) catch |err| switch (err) {
                            error.RedeclarationError => {
                                self.emitRedeclarationError(capture_node.*, capture_node.data.string_id);
                                return err;
                            },
                            else => return err,
                        };
                    } else {
                        const condition = self.ast.nodes.items[extra.condition];
                        self.error_reporter.semanticAnalyserError(self, Error.MissingCapture, condition, "missing then capture for nullable condition");
                        maybe_err = Error.MissingCapture;
                    }

                    if (extra.else_capture) |else_capture_id| {
                        const else_capture = self.ast.nodes.items[else_capture_id];
                        self.error_reporter.semanticAnalyserError(self, Error.PointlessCapture, else_capture, "capture is pointless for nullable condition (it is always null)");
                        maybe_err = Error.PointlessCapture;
                    }
                } else if (self.ast.type_pool.isErrorUnion(type_condition)) {
                    if (extra.then_capture) |then_capture| {
                        const capture_node = &self.ast.nodes.items[then_capture];
                        const capture_type = try self.ast.type_pool.getOrCreateNotErrorUnionType(type_condition);
                        const capture_extra = self.ast.getExtra(capture_node.data.extra_id, VarDeclarationExtra);

                        capture_node.resolved_type_id = capture_type;

                        self.symbol_table.declare(capture_extra.name_id, .{
                            .name_id = capture_extra.name_id,
                            .type_id = capture_type,
                            .is_mutable = false,
                            .node_id = then_capture,
                        }) catch |err| switch (err) {
                            error.RedeclarationError => {
                                self.emitRedeclarationError(capture_node.*, capture_node.data.string_id);
                                return err;
                            },
                            else => return err,
                        };
                    } else {
                        const condition = self.ast.nodes.items[extra.condition];
                        self.error_reporter.semanticAnalyserError(self, Error.MissingCapture, condition, "missing then capture for nullable condition");
                        maybe_err = Error.MissingCapture;
                    }

                    if (extra.else_branch != null) {
                        if (extra.else_capture) |else_capture| {
                            const capture_node = &self.ast.nodes.items[else_capture];
                            const capture_type = self.ast.type_pool.getErrorSetFromTypeUnion(type_condition) catch unreachable; // assured ErrorUnion by parent:  else if (self.ast.type_pool.isErrorUnion(type_condition))
                            const capture_extra = self.ast.getExtra(capture_node.data.extra_id, VarDeclarationExtra);

                            capture_node.resolved_type_id = capture_type;

                            self.symbol_table.declare(capture_extra.name_id, .{
                                .name_id = capture_node.data.string_id,
                                .type_id = capture_type,
                                .is_mutable = false,
                                .node_id = else_capture,
                            }) catch |err| switch (err) {
                                error.RedeclarationError => {
                                    self.emitRedeclarationError(capture_node.*, capture_node.data.string_id);
                                    return err;
                                },
                                else => return err,
                            };
                        }

                        const condition = self.ast.nodes.items[extra.condition];
                        self.error_reporter.semanticAnalyserError(self, Error.MissingCapture, condition, "missing else capture for error union condition");
                        maybe_err = Error.MissingCapture;
                    }
                } else {
                    const condition = self.ast.nodes.items[extra.condition];
                    self.error_reporter.semanticAnalyserError(self, Error.IncompatibleTypes, condition, "condition needs to evaluate to bool, nullable type or error union");

                    const type_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, type_condition, self.ast.string_table);
                    defer self.allocator.free(type_name);

                    const hint_message = try std.fmt.allocPrint(self.allocator, "condition evaluates to {s}", .{type_name});
                    defer self.allocator.free(hint_message);

                    self.error_reporter.semanticAnalyserHint(self, condition, hint_message);
                    maybe_err = Error.IncompatibleTypes;
                }

                const type_then = try self.analyse(extra.then_branch);
                var type_else = type_then;

                if (extra.else_branch) |else_branch_id| {
                    type_else = try self.analyse(else_branch_id);
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

                break :case TypePool.VOID;
            },

            // access
            .assignment => case: {
                const extra = self.ast.getExtra(node.data.extra_id, AssignmentExtra);
                // TODO chexck is assignable
                // TODO check target allowd
                const target_node = self.ast.nodes.items[extra.target];
                if (target_node.tag != .identifier_expr) {
                    self.error_reporter.semanticAnalyserError(self, Error.InvalidAssignmentTarget, target_node, "invalid assignment target");
                    return Error.InvalidAssignmentTarget;
                }

                const maybe_symbol = self.symbol_table.lookup(target_node.data.string_id);

                if (maybe_symbol == null) {
                    self.error_reporter.semanticAnalyserError(self, Error.UnknownIdentifier, target_node, "unknown identifier");
                    return Error.UnknownIdentifier;
                }

                if (!maybe_symbol.?.is_mutable) {
                    self.error_reporter.semanticAnalyserError(self, Error.IllegalMutation, node.*, "mutation not allowd");
                    return Error.IllegalMutation;
                }

                const source_type = try self.analyse(extra.source);
                if (!self.ast.type_pool.isAssignable(maybe_symbol.?.type_id, source_type)) {
                    self.error_reporter.semanticAnalyserError(self, Error.TypeMismatch, node.*, "incompatible types");
                    return Error.TypeMismatch;
                }

                break :case source_type;
            },
            .identifier_expr => |_| case: {
                const maybe_symbol = self.symbol_table.lookup(node.data.string_id);
                if (maybe_symbol) |symbol| {
                    break :case symbol.type_id;
                }

                self.error_reporter.semanticAnalyserError(self, Error.UnknownIdentifier, node.*, "unknown identifier");
                return Error.UnknownIdentifier;
            },
            // unary operations
            .negate => |_| case: {
                const type_rhs = try self.analyse(node.data.node_id);

                if (type_rhs == TypePool.INT or type_rhs == TypePool.FLOAT) {
                    break :case type_rhs;
                }

                self.error_reporter.semanticAnalyserError(self, Error.UnsupportedOperand, node.*, "operand must be a number");
                return Error.UnsupportedOperand;
            },
            .logical_not => |_| case: {
                const type_rhs = try self.analyse(node.data.node_id);

                if (type_rhs == TypePool.BOOL) {
                    break :case type_rhs;
                }

                self.error_reporter.semanticAnalyserError(self, Error.UnsupportedOperand, node.*, "operand must be a bool");
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
            .call_return => |_| case: {
                break :case try self.analyse(node.data.node_id);
            },
            .call => |_| case: {
                const extra = self.ast.getExtra(node.data.extra_id, CallExtra);
                const type_callee = try self.analyse(extra.callee);

                var iterator = NodeListIterator.init(self.ast, extra.args_start);
                while (iterator.next()) |list_node_id| {
                    _ = try self.analyse(list_node_id);
                }

                break :case type_callee;
            },
        };

        node.resolved_type_id = resolved_type;
        return resolved_type;
    }

    fn analyseDeclaration(self: *SemanticAnalyser, node_id: NodeId, is_mutable: bool) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const extra = self.ast.getExtra(node.data.extra_id, VarDeclarationExtra);

        // analyse the initializer
        var inferred_type: TypeId = TypePool.UNRESOLVED;
        if (extra.init_value) |init_value_id| {
            inferred_type = try self.analyse(init_value_id);
        }

        var type_id: TypeId = undefined;

        if (inferred_type != TypePool.UNRESOLVED and extra.explicit_type != TypePool.UNRESOLVED) {
            // both types are present

            if (!self.ast.type_pool.isAssignable(extra.explicit_type, inferred_type)) {
                const init_node = self.ast.nodes.items[extra.init_value.?];

                const inferred_type_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, inferred_type, self.ast.string_table);
                defer self.allocator.free(inferred_type_name);
                const explicit_type_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, extra.explicit_type, self.ast.string_table);
                defer self.allocator.free(explicit_type_name);

                const error_message = try std.fmt.allocPrint(self.allocator, "can not assign {s} to {s}", .{ inferred_type_name, explicit_type_name });

                self.error_reporter.semanticAnalyserError(self, Error.TypeMismatch, init_node, error_message);
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

        // add variable to symbol table
        self.symbol_table.declare(extra.name_id, .{
            .name_id = extra.name_id,
            .type_id = type_id,
            .is_mutable = is_mutable,
            .node_id = node_id,
        }) catch |err| switch (err) {
            error.RedeclarationError => {
                self.emitRedeclarationError(node, extra.name_id);
                return err;
            },
            else => return err,
        };

        return TypePool.VOID;
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
        self.error_reporter.semanticAnalyserError(self, Error.IncompatibleTypes, node, "Incompatible types");

        return error.IncompatibleTypes;
    }

    fn emitRedeclarationError(self: *const SemanticAnalyser, node: Node, identifier_name: StringId) void {
        self.error_reporter.semanticAnalyserError(self, Error.RedeclarationError, node, "name is already in use");

        const symbol_collision = self.symbol_table.lookup(identifier_name);
        const node_collision = self.ast.nodes.items[symbol_collision.?.node_id];
        self.error_reporter.semanticAnalyserHint(self, node_collision, "name is already declared here:");
    }
};

const std = @import("std");
const as = @import("as");

const ErrorReporter = as.common.reporting.ErrorReporter;

const AST = as.frontend.AST;
const TypePool = as.frontend.TypePool;
const SymbolTable = as.frontend.SymbolTable;

const Symbol = as.frontend.Symbol;
const StringId = as.common.StringId;
const TypeId = as.frontend.TypeId;
const NodeId = as.frontend.ast.NodeId;
const Node = as.frontend.ast.Node;

const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;
const VarDeclarationExtra = as.frontend.ast.VarDeclarationExtra;
const NodeListExtra = as.frontend.ast.NodeListExtra;
const NodeListIterator = as.frontend.ast.NodeListIterator;
const CallExtra = as.frontend.ast.CallExtra;
const IfExtra = as.frontend.ast.IfExtra;
const AssignmentExtra = as.frontend.ast.AssignmentExtra;

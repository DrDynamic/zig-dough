pub const SemanticAnalyzer = struct {
    pub const Error = error{
        OutOfMemory,
        UnhandledNodeType,
        TypeMismatch,
        IncompatibleTypes,
        RedeclarationError,
        UnknownIdentifier,
        UnsupportedOperand,
    };

    allocator: std.mem.Allocator,
    ast: *AST,
    type_pool: *TypePool,
    error_reporter: *ErrorReporter,
    symbol_table: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, type_pool: *TypePool, error_reporter: *ErrorReporter) !SemanticAnalyzer {
        return .{
            .allocator = allocator,
            .ast = undefined,
            .type_pool = type_pool,
            .error_reporter = error_reporter,
            .symbol_table = try SymbolTable.init(allocator),
        };
    }

    pub fn deinit(self: *SemanticAnalyzer) void {
        self.symbol_table.deinit();
    }

    pub fn analyseAst(self: *SemanticAnalyzer, ast: *AST) Error!void {
        self.ast = ast;

        for (ast.getRoots()) |node_id| {
            _ = self.analyze(node_id) catch |err| {
                ast.invalidate();
                return err;
            };
        }
    }

    fn analyze(self: *SemanticAnalyzer, node_id: NodeId) Error!TypeId {
        var node = &self.ast.nodes.items[node_id];

        const resolved_type: TypeId = switch (node.tag) {
            // literals
            .literal_null => TypePool.NULL,
            .literal_bool => TypePool.BOOL,
            .literal_int => TypePool.INT,
            .literal_float => TypePool.FLOAT,

            // objects
            .object_string => TypePool.STRING,

            // declarations
            .declaration_var => try self.analyzeDeclarationVar(node_id),
            // access
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
                const type_rhs = try self.analyze(node.data.node_id);

                if (type_rhs == TypePool.INT or type_rhs == TypePool.FLOAT) {
                    break :case type_rhs;
                }

                self.error_reporter.semanticAnalyserError(self, Error.UnsupportedOperand, node.*, "operand must be a number");
                return Error.UnsupportedOperand;
            },
            .logical_not => |_| case: {
                const type_rhs = try self.analyze(node.data.node_id);

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
            => try self.analyzeBinaryMath(node_id),
            .binary_equal,
            .binary_not_equal,
            .binary_less,
            .binary_less_equal,
            .binary_greater,
            .binary_greater_equal,
            => try self.analyzeBinaryCompare(node_id),
            .call_return => |_| case: {
                break :case try self.analyze(node.data.node_id);
            },
            .call => |_| case: {
                const extra = self.ast.getExtra(node.data.extra_id, CallExtra);
                const type_callee = try self.analyze(extra.callee);

                var arg_list = extra.args_start;
                for (0..extra.args_count) |_| {
                    const list_node = self.ast.nodes.items[arg_list];
                    const list_extra = self.ast.getExtra(list_node.data.extra_id, NodeListExtra);

                    // TODO compare argument types with callee parameter list
                    _ = try self.analyze(list_extra.node_id);

                    arg_list = list_extra.next;
                }

                break :case type_callee;
            },
            else => |_| {
                std.debug.print("Unhandled node: {s}\n", .{@tagName(node.tag)});
                return error.UnhandledNodeType;
            },
        };

        node.resolved_type_id = resolved_type;
        return resolved_type;
    }

    fn analyzeDeclarationVar(self: *SemanticAnalyzer, node_id: NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, VarDeclarationExtra);

        // Analyze the initializer
        const inferred_type = try self.analyze(data.init_value);

        if (data.explicit_type != TypePool.UNRESOLVED) {
            if (data.explicit_type != inferred_type) {
                // TODO add implicit casts (type promotions)
                return error.TypeMismatch;
            }
        } else {
            // TODO is there is no explicit type, there needs to be an initializer

        }

        // add variable to symbol table
        try self.symbol_table.declare(data.name_id, .{
            .name_id = data.name_id,
            .type_id = inferred_type,
            .is_mutable = true,
            .node_id = node_id,
        });

        return TypePool.VOID;
    }

    fn analyzeBinaryCompare(self: *SemanticAnalyzer, node_id: NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);

        const left_type = try self.analyze(data.lhs);
        const right_type = try self.analyze(data.rhs);

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

    fn analyzeBinaryMath(self: *SemanticAnalyzer, node_id: NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);

        const left_type = try self.analyze(data.lhs);
        const right_type = try self.analyze(data.rhs);

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
};

const std = @import("std");
const as = @import("as");

const ErrorReporter = as.common.reporting.ErrorReporter;

const AST = as.frontend.AST;
const TypePool = as.frontend.TypePool;
const SymbolTable = as.frontend.SymbolTable;

const Symbol = as.frontend.Symbol;
const TypeId = as.frontend.TypeId;
const NodeId = as.frontend.ast.NodeId;

const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;
const VarDeclarationExtra = as.frontend.ast.VarDeclarationExtra;
const NodeListExtra = as.frontend.ast.NodeListExtra;
const CallExtra = as.frontend.ast.CallExtra;

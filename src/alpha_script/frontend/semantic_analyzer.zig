pub const SemanticAnalyzer = struct {
    pub const Error = error{
        OutOfMemory,
        UnhandledNodeType,
        TypeMismatch,
        IncompatibleTypes,
        RedeclarationError,
    };

    allocator: std.mem.Allocator,
    ast: *AST,
    type_pool: *TypePool,
    error_reporter: *ErrorReporter,
    symbol_table: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, ast_: *AST, type_pool: *TypePool, error_reporter: *ErrorReporter) !SemanticAnalyzer {
        return .{
            .allocator = allocator,
            .ast = ast_,
            .type_pool = type_pool,
            .error_reporter = error_reporter,
            .symbol_table = try SymbolTable.init(allocator),
        };
    }

    pub fn deinit(self: *SemanticAnalyzer) void {
        self.symbol_table.deinit();
    }

    pub fn analyze(self: *SemanticAnalyzer, node_id: ast.NodeId) Error!TypeId {
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
            .identifier_expr => TypePool.UNRESOLVED, // TODO: implement identifier resolution
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
            .call_return => {
                return self.analyze(node.data.node_id);
            },
            .call => {
                const extra = self.ast.getExtra(node.data.extra_id, ast.CallExtra);
                const type_callee = self.analyze(extra.callee);

                var arg_list = extra.args_start;
                for (0..extra.args_count) |_| {
                    const list_node = self.ast.nodes.items[arg_list];
                    const list_extra = self.ast.getExtra(list_node.data.extra_id, ast.NodeListExtra);

                    // TODO compare argument types with callee parameter list
                    _ = try self.analyze(list_extra.node_id);

                    arg_list = list_extra.next;
                }

                return type_callee;
            },
            else => {
                std.debug.print("Unhandled node: {s}\n", .{@tagName(node.tag)});
                return error.UnhandledNodeType;
            },
        };

        node.resolved_type_id = resolved_type;
        return resolved_type;
    }

    fn analyzeDeclarationVar(self: *SemanticAnalyzer, node_id: ast.NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationExtra);

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

    fn analyzeBinaryCompare(self: *SemanticAnalyzer, node_id: ast.NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, ast.BinaryOpExtra);

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

    fn analyzeBinaryMath(self: *SemanticAnalyzer, node_id: ast.NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, ast.BinaryOpExtra);

        const left_type = try self.analyze(data.lhs);
        const right_type = try self.analyze(data.rhs);

        if (left_type == right_type) {
            return left_type;
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
const ast = as.frontend.ast;

const ErrorReporter = as.common.reporting.ErrorReporter;

const AST = as.frontend.AST;
const TypePool = as.frontend.TypePool;
const SymbolTable = as.frontend.SymbolTable;

const Symbol = as.frontend.Symbol;
const TypeId = as.frontend.TypeId;

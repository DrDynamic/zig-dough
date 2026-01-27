pub const Error = error{
    OutOfMemory,
    UnhandledNodeType,
    TypeMismatch,
    IncompatibleTypes,
    RedeclarationError,
};

pub const SemanticAnalyzer = struct {
    allocator: std.mem.Allocator,
    ast: *AST,
    type_pool: *TypePool,
    error_reporter: *const ErrorReporter,
    symbol_table: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, ast_: *AST, type_pool: *TypePool, error_reporter: *const ErrorReporter) !SemanticAnalyzer {
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
            .literal_void => TypePool.VOID,
            .literal_null => TypePool.NULL,
            .literal_bool => TypePool.BOOL,
            .literal_int => TypePool.INT,
            .literal_float => TypePool.FLOAT,
            .literal_string => TypePool.STRING,

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
            else => {
                return error.UnhandledNodeType;
            },
        };

        node.resolved_type_id = resolved_type;
        return resolved_type;
    }

    fn analyzeDeclarationVar(self: *SemanticAnalyzer, node_id: ast.NodeId) Error!TypeId {
        const node = self.ast.nodes.items[node_id];
        const data = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationData);

        // Analyze the initializer
        const inferred_type = try self.analyze(data.init_value);

        if (data.explicit_type != TypePool.UNRESOLVED) {
            if (data.explicit_type != inferred_type) {
                // TODO add implicit casts (type promotions)
                return error.TypeMismatch;
            }
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
        const data = self.ast.getExtra(node.data.extra_id, ast.BinaryOpData);

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
        const data = self.ast.getExtra(node.data.extra_id, ast.BinaryOpData);

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
        return error.IncompatibleTypes;
    }
};

const std = @import("std");
const as = @import("as");
const ast = as.frontend.ast;

const ErrorReporter = as.frontend.ErrorReporter;

const AST = as.frontend.AST;
const TypePool = as.frontend.TypePool;
const SymbolTable = as.frontend.SymbolTable;

const Symbol = as.frontend.Symbol;
const TypeId = as.frontend.TypeId;

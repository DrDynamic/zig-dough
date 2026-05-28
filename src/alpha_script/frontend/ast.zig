pub const NodeId = u32;
pub const NodeExtraId = u32;

pub const NodeType = enum(u8) {
    // literals
    literal_null, // none
    literal_bool, // none
    literal_int, // int_value
    literal_float, // float_value
    literal_error, // error_value

    // objects
    object_string, // string_id

    // declarations
    declaration_error_set, // DeclarationExtra
    declaration_type, // DeclarationExtra
    declaration_var, // DeclarationExtra
    declaration_const, // DeclarationExtra
    declaration_parameter, // string_id (the name of the parameter)

    // statements
    //    statement_for,
    statement_return, // node_id (the returned expression)

    // expressions
    expression_block, // BlockExtra (the start of a NodeList of Satements)
    expression_if, // IfExtra
    expression_grouping, // node_id (the expression, that is grouped)
    expression_function, // FunctionExtra

    // access
    expression_assignment, // node_id (the expression that is assigned)
    identifier_expr, // string_id
    call, // CallExtra
    node_list, // NodeListExtra

    // unary operations
    negate,
    logical_not,

    // binary operations
    binary_add, // BinaryOpExtra
    binary_sub, // BinaryOpExtra
    binary_mul, // BinaryOpExtra
    binary_div, // BinaryOpExtra
    binary_equal, // BinaryOpExtra
    binary_not_equal, // BinaryOpExtra
    binary_less, // BinaryOpExtra
    binary_less_equal, // BinaryOpExtra
    binary_greater, // BinaryOpExtra
    binary_greater_equal, // BinaryOpExtra

    // logical operations
    logical_and, // BinaryOpExtra
    logical_or, // BinaryOpExtra
};

pub const AssignmentExtra = struct {
    target: NodeId,
    source: NodeId,
};

pub const BinaryOpExtra = struct {
    lhs: NodeId,
    rhs: NodeId,
};

pub const BlockExtra = struct {
    statements: ?[]NodeId, // NodeListExtra
};

pub const CallExtra = struct {
    callee: NodeId,
    args_start: ?NodeExtraId, // NodeListExtra
    arg_count: u8,
};

pub const DeclarationExtra = struct {
    name_id: StringId,
    explicit_type: TypeId,
    init_value: ?NodeId,
};

pub const FunctionExtra = struct {
    name_id: ?StringId,
    parameters: ?[]NodeExtraId, // NodeListExtra
    return_type: TypeId,
    body: NodeId, // expression_block
};

pub const IfExtra = struct {
    condition: NodeId,

    then_capture: ?NodeId,
    then_branch: NodeId,

    else_capture: ?NodeId,
    else_branch: ?NodeId,
};

pub const NodeListExtra = struct {
    node_id: NodeId,
    next: ?NodeExtraId,
};

pub const NodeListIterator = struct {
    ast: *const AST,
    current: ?NodeExtraId,

    pub fn init(ast: *const AST, first_extra_id: NodeExtraId) NodeListIterator {
        return .{
            .ast = ast,
            .current = first_extra_id,
        };
    }

    pub fn hasNext(self: *NodeListIterator) bool {
        return self.current != null;
    }

    pub fn next(self: *NodeListIterator) ?NodeId {
        if (self.current == null) return null;

        const current_extra = self.ast.getExtra(self.current.?, NodeListExtra);
        self.current = current_extra.next;

        return current_extra.node_id;
    }
};

pub const Node = struct {
    tag: NodeType,
    token_position: usize,
    resolved_type_id: TypeId,

    data: union {
        bool_value: bool,
        int_value: i64,
        float_value: f64,
        error_value: TypeId,
        string_id: StringId,
        node_id: NodeId,
        extra_id: NodeExtraId,
    },
};

pub const AST = struct {
    allocator: Allocator,

    scanner: *Scanner,
    roots: ArrayList(NodeId),
    nodes: ArrayList(Node),
    extra_data: ArrayList(u8),
    string_table: *StringTable,
    type_pool: TypePool,
    is_valid: bool,

    pub fn init(scanner: *Scanner, string_table: *StringTable, type_pool: TypePool, allocator: Allocator) !AST {
        const ast: AST = .{
            .allocator = allocator,
            .scanner = scanner,
            .roots = ArrayList(NodeId).init(allocator),
            .nodes = ArrayList(Node).init(allocator),
            .extra_data = ArrayList(u8).init(allocator),
            .string_table = string_table,
            .type_pool = type_pool,
            .is_valid = true,
        };

        return ast;
    }

    pub fn deinit(self: *AST) void {
        for (self.nodes.items) |node| {
            switch (node.tag) {
                .expression_block => {
                    const extra = self.getExtra(node.data.extra_id, BlockExtra);
                    if (extra.statements != null) {
                        self.allocator.free(extra.statements.?);
                    }
                },
                .expression_function => {
                    const extra = self.getExtra(node.data.extra_id, FunctionExtra);
                    if (extra.parameters != null) {
                        self.allocator.free(extra.parameters.?);
                    }
                },
                else => {},
            }
        }

        self.roots.deinit();
        self.nodes.deinit();
        self.extra_data.deinit();
    }

    pub fn invalidate(self: *AST) void {
        self.is_valid = false;
    }

    pub fn addRoot(self: *AST, node_id: NodeId) !void {
        try self.roots.append(node_id);
    }

    pub fn getRoots(self: AST) []const NodeId {
        return self.roots.items;
    }

    pub fn addNode(self: *AST, node: Node) !NodeId {
        const id = self.nodes.items.len;
        try self.nodes.append(node);
        return @intCast(id);
    }

    /// Stores each field of data as a separate element in self.extra_data
    pub fn addExtra(self: *AST, data: anytype) !u32 {
        const start_idx: u32 = @intCast(self.extra_data.items.len);

        const extra_data = std.mem.toBytes(data);
        try self.extra_data.appendSlice(&extra_data);

        return start_idx;
    }

    pub fn getExtra(self: AST, index: u32, comptime T: type) T {
        const bytes = self.extra_data.items[index .. index + @sizeOf(T)];
        return std.mem.bytesToValue(T, bytes);
    }

    pub fn getTypeDeclarationNode(self: *const AST, type_name_id: StringId) ?Node {
        for (self.nodes.items) |node| {
            if (node.tag == .declaration_type or node.tag == .declaration_error_set) {
                const extra = self.getExtra(node.data.extra_id, DeclarationExtra);
                if (extra.name_id == type_name_id) {
                    return node;
                }
            }
        }
        return null;
    }

    pub fn getSymbolDeclarationNode(self: *const AST, type_name_id: StringId) ?Node {
        for (self.nodes.items) |node| {
            if (node.tag == .declaration_type or node.tag == .declaration_error_set) {
                const extra = self.getExtra(node.data.extra_id, DeclarationExtra);
                if (extra.name_id == type_name_id) {
                    return node;
                }
            }
        }
        return null;
    }
};

const std = @import("std");
const assert = std.debug.assert;
const meta = std.meta;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const as = @import("as");
const TypeId = as.frontend.TypeId;
const StringId = as.common.StringId;
const StringTable = as.common.StringTable;
const Scanner = as.frontend.Scanner;
const TypePool = as.frontend.TypePool;

pub const NodeId = u32;

pub const NodeType = enum(u8) {
    // nodes needed ad compiletime (should not bleed into runtime!)
    comptime_uninitialized,

    // literals
    literal_null, // none
    literal_bool, // none
    literal_int, // int_value
    literal_float, // float_value

    // objects
    object_string, // string_id

    // declarations
    declaration_var, // VarDeclarationExtra
    declaration_const, // VarDeclarationExtra

    // expressions
    expression_block, // node_id (the start of a NodeList of Satements)
    expression_if, // IfExtra

    // access
    identifier_expr, // string_id
    call, // CallExtra
    call_return,
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
};

pub const VarDeclarationExtra = struct {
    name_id: StringId,
    explicit_type: TypeId,
    init_value: ?NodeId,
};

pub const IfExtra = struct {
    condition: NodeId,

    then_capture: ?NodeId,
    then_branch: NodeId,

    else_capture: ?NodeId,
    else_branch: ?NodeId,
};

pub const BinaryOpExtra = struct {
    lhs: NodeId,
    rhs: NodeId,
};

pub const CallExtra = struct {
    callee: NodeId,
    args_start: NodeId,
};

pub const NodeListExtra = struct {
    node_id: NodeId,
    next: ?NodeId,
};

pub const NodeListIterator = struct {
    ast: *const AST,
    current: ?NodeId,

    pub fn init(ast: *const AST, first_node_id: NodeId) NodeListIterator {
        return .{
            .ast = ast,
            .current = first_node_id,
        };
    }

    pub fn hasNext(self: *NodeListIterator) bool {
        return self.current != null;
    }

    pub fn next(self: *NodeListIterator) ?NodeId {
        if (self.current == null) return null;

        const current_node = self.ast.nodes.items[self.current.?];
        assert(current_node.tag == .node_list);

        const extra = self.ast.getExtra(current_node.data.extra_id, NodeListExtra);
        self.current = extra.next;
        return extra.node_id;
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
        string_id: StringId,
        node_id: NodeId,
        extra_id: u32,
    },
};

pub const AST = struct {
    allocator: Allocator,

    scanner: *Scanner,
    roots: ArrayList(NodeId),
    nodes: ArrayList(Node),
    extra_data: ArrayList(u8),
    string_table: *StringTable,
    is_valid: bool,

    pub fn init(scanner: *Scanner, string_table: *StringTable, allocator: Allocator) !AST {
        const ast: AST = .{
            .allocator = allocator,
            .scanner = scanner,
            .roots = ArrayList(NodeId).init(allocator),
            .nodes = ArrayList(Node).init(allocator),
            .extra_data = ArrayList(u8).init(allocator),
            .string_table = string_table,
            .is_valid = true,
        };

        return ast;
    }

    pub fn deinit(self: *AST) void {
        self.roots.deinit();
        self.nodes.deinit();
        self.extra_data.deinit();
        self.string_table.deinit();
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

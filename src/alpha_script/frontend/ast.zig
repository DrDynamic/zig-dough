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
    init_value: NodeId,
};

pub const IfExtra = struct {
    condition: NodeId,

    has_then_capture: bool,
    has_else_capture: bool,
    has_else_branch: bool,

    then_capture: NodeId,
    then_branch: NodeId,

    else_capture: NodeId,
    else_branch: NodeId,
};

pub const BinaryOpExtra = struct {
    lhs: NodeId,
    rhs: NodeId,
};

pub const CallExtra = struct {
    callee: NodeId,
    args_count: u8,
    args_start: NodeId,
};

pub const NodeListExtra = struct {
    node_id: NodeId,
    next: NodeId,
    is_last: bool,
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
    extra_data: ArrayList(u32),
    string_table: *StringTable,
    is_valid: bool,

    pub fn init(scanner: *Scanner, string_table: *StringTable, allocator: Allocator) !AST {
        const ast: AST = .{
            .allocator = allocator,
            .scanner = scanner,
            .roots = ArrayList(NodeId).init(allocator),
            .nodes = ArrayList(Node).init(allocator),
            .extra_data = ArrayList(u32).init(allocator),
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
        const fields = meta.fields(@TypeOf(data));
        const start_idx: u32 = @intCast(self.extra_data.items.len);
        inline for (fields) |field| {
            const data_value = @field(data, field.name);
            // TODO this only works for data that can fit in u32, need a more general solution if we want to store more complex data
            // maybe use @bitcast?
            try self.extra_data.append(@intCast(data_value));
        }
        return start_idx;
    }

    pub fn getExtra(self: AST, index: u32, comptime T: type) T {
        const fields = std.meta.fields(T);
        var result: T = undefined;
        inline for (fields, 0..) |field, i| {
            @field(result, field.name) = @intCast(self.extra_data.items[index + i]);
        }
        return result;
    }
};

const std = @import("std");
const meta = std.meta;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const as = @import("as");
const TypeId = as.frontend.TypeId;
const StringId = as.common.StringId;
const StringTable = as.common.StringTable;

const Scanner = as.frontend.Scanner;

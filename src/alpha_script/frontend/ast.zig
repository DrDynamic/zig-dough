pub const NodeId = u32;

pub const NodeType = enum(u8) {
    // literals
    null_literal,
    bool_literal,
    int_literl,
    float_literal,
    string_literal,

    identifier_expr,

    // declarations
    var_declaration,
};

pub const VarDeclarationData = struct {
    name_id: StringId,
    init_value: ?NodeId,
};

pub const Node = struct {
    tag: NodeType,
    resolved_type_idx: TypeIndex,

    data: union {
        bool_value: bool,
        int_value: i64,
        float_value: f64,
        string_id: StringId,
        extra_id: u32,
    },
};

pub const AST = struct {
    allocator: Allocator,

    nodes: ArrayList(Node),
    extra_data: ArrayList(u32),
    string_table: StringTable,

    pub fn init(allocator: Allocator) AST {
        return .{
            .allocator = allocator,
            .nodes = ArrayList(Node).init(allocator),
            .extra_data = ArrayList(u32).init(allocator),
            .string_table = StringTable.init(allocator),
        };
    }

    pub fn deinit(self: *AST) void {
        self.nodes.deinit();
        self.extra_data.deinit();
        self.string_table.deinit();
    }

    pub fn addNode(self: *AST, node: Node) !NodeId {
        const id = self.nodes.items.len;
        self.nodes.append(node);
        return id;
    }

    /// Stores each field of data as a separate element in self.extra_data
    pub fn addExtra(self: *AST, data: anytype) !u32 {
        const fields = meta.fields(@TypeOf(data));
        const start_idx: u32 = @intCast(self.extra_data.items.len);

        inline for (fields) |field| {
            const data_value = @field(data, field.name);
            try self.extra_data.append(@intCast(data_value));
        }
        return start_idx;
    }
};

const std = @import("std");
const meta = std.meta;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const as = @import("as");
const TypeIndex = as.frontend.TypeIndex;
const StringId = as.common.StringId;
const StringTable = as.common.StringTable;

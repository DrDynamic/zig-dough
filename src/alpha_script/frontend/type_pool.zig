pub const TypeId = u32;

pub const TypeTag = enum(u8) {
    unresolved,
    void,
    null,
    bool,
    int,
    float,
    string,
    module,
    /// mixed type like int|float or string|null
    union_type,
};

pub const Type = union(TypeTag) {
    union_type: struct {
        type_list_index: u32,
        count: u32,
    },
    data: union {
        pointer_to: TypeId,
    },
};

pub const TypePool = struct {
    allocator: std.mem.Allocator,
    types: ArrayList(Type),
    extra_data: ArrayList(u32),
    type_list_buffer: std.ArrayList(TypeId),
    union_cache: TypeListMap,

    pub const UNRESOLVED = 0;
    pub const VOID = 1;
    pub const NULL = 2;
    pub const BOOL = 3;
    pub const INT = 4;
    pub const FLOAT = 5;
    pub const STRING = 6;
    pub const MODULE = 7;

    pub fn init(allocator: Allocator) !TypePool {
        var pool = TypePool{
            .allocatior = allocator,
            .types = ArrayList(Type).init(allocator),
            .extra_data = ArrayList(u32).init(allocator),
            .type_list_buffer = std.ArrayList(TypeId).init(allocator),
            .union_cache = TypeListMap.init(allocator),
        };

        try pool.types.append(.{ .tag = .unresolved, .data = undefined });
        try pool.types.append(.{ .tag = .void, .data = undefined });
        try pool.types.append(.{ .tag = .null, .data = undefined });
        try pool.types.append(.{ .tag = .bool, .data = undefined });
        try pool.types.append(.{ .tag = .int, .data = undefined });
        try pool.types.append(.{ .tag = .float, .data = undefined });
        try pool.types.append(.{ .tag = .string, .data = undefined });
        try pool.types.append(.{ .tag = .module, .data = undefined });

        return pool;
    }

    pub fn deinit(self: *TypePool) void {
        self.types.deinit();
        self.extra_data.deinit();
        self.type_list_buffer.deinit();
        self.union_cache.deinit();
    }

    /// a type is assignable to another type, when both type are the same or target is a superset of source
    pub fn isAssignable(self: *const TypePool, target_id: TypeId, source_id: TypeId) bool {
        if (target_id == source_id) return true;

        const target = self.types.items[target_id];
        switch (target) {
            .unresolved => unreachable,
            .void => unreachable,
            .null => false, // null is only assignable to null. Since target_id != source_id , the source can not be of type null
            .bool => false, // same with bool
            .int => false, // and so on
            .float => source_id == TypePool.INT, // int type can be promoted to float
            .string => false,
            .module => unreachable,
            .union_type => {
                // TODO test if target is a superset of source
            },
        }
    }

    pub fn getOrCreateUnionType(self: *TypePool, member_types: []const TypeId) TypeId {
        // sort / canonicalize member_type, so that (int|float) == (float|int)
        const sorted_members = try self.allocator.alloc(TypeId, member_types.len);
        defer self.allocator.free(sorted_members);

        std.mem.copy(TypeId, sorted_members, member_types);
        std.mem.sort(TypeId, sorted_members, {}, std.sort.asc(TypeId));

        // return type_id if cached
        if (self.union_cache.get(sorted_members)) |type_id| {
            return type_id;
        }

        // create type otherwise
        const list_index: u32 = @intCast(self.type_list_buffer.items.len);
        try self.type_list_buffer.append(sorted_members);

        const type_id: TypeId = @intCast(self.types.items.len);
        try self.types.append(.{ .union_type = .{
            .type_list_index = list_index,
        } });

        // put union in cache
        const list_slice = self.type_list_buffer.items[list_index .. list_index + sorted_members.len];
        try self.union_cache.put(list_slice, type_id);

        return type_id;
    }
};

const TypeListMap = std.HashMap([]const TypeId, TypeId, TypeListContext, 80);

const TypeListContext = struct {
    pub const eql = std.hash_map.getAutoEqlFn([]const TypeId, undefined);
    pub const hash = std.hash_map.getAutoHashFn([]const TypeId, undefined);
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

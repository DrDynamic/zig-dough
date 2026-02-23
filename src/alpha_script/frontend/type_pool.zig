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
};

pub const TypePool = struct {
    allocator: std.mem.Allocator,
    types: ArrayList(Type),
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
        self.type_list_buffer.deinit();
        self.union_cache.deinit();
    }

    /// a type is nullable when the type is null or a union type that contains null
    pub fn isNullable(self: *const TypePool, type_id: TypeId) bool {
        if (type_id == TypePool.NULL) return true;

        const ty = self.types.items[type_id];
        if (ty.tag == .union_type) {
            const members = self.getUnionMembers(ty);
            for (members) |member| {
                // recursion for nested unions
                if (self.isNullable(member)) {
                    return true;
                }
            }
        }

        return false;
    }

    pub fn isNumeric(self: *const TypePool, type_id: TypeId) bool {
        if (type_id == TypePool.INT or type_id == TypePool.FLOAT) {
            return true;
        }
        const ty = self.types.items[type_id];
        if (ty.tag == .union_type) {
            const members = self.getUnionMembers(ty);
            for (members) |member| {
                // recursion for nested unions
                if (!self.isNumeric(member)) {
                    return false;
                }
            }
            return true;
        }
        return false;
    }

    pub fn isErrorUnion(self: *const TypePool, type_id: TypeId) bool {
        _ = self;
        _ = type_id;
        return false; // TODO implement errors
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
                const source = self.types.items[source_id];
                if (source != .union_type) {
                    // if source is not a union type, then source must be assignable to at least one member of target
                    const target_members = self.getUnionMembers(target);
                    for (target_members) |target_member| {
                        if (self.isAssignable(target_member, source_id)) {
                            return true;
                        }
                    }
                    return false;
                } else {
                    // if source is also a union type, then all members of source must be assignable to target
                    const source_members = self.getUnionMembers(source);
                    for (source_members) |source_member| {
                        if (!self.isAssignable(target_id, source_member)) {
                            return false;
                        }
                    }
                    return true;
                }
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

    inline fn getUnionMembers(self: *const TypePool, union_type: Type) []const TypeId {
        return self.type_list_buffer.items[union_type.union_type.type_list_index .. union_type.union_type.type_list_index + union_type.union_type.count];
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

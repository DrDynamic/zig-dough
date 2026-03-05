pub const TypeId = u32;

pub const TypeTag = enum(u8) {
    /// the type is not resolved yet. (should only occur in before execution of the SemanticAnalyzer)
    unresolved,

    // primitives
    void,
    null,
    bool,
    int,
    float,
    string,

    // complex
    module,

    // error
    anyerror,
    error_type,
    error_set,

    /// mixed type like int|float or string|null
    union_type,
};

pub const Type = union(TypeTag) {
    unresolved,
    void,
    null,
    bool,
    int,
    float,
    string,
    module,

    anyerror,
    error_type: StringId,
    error_set: struct {
        type_list_index: u32,
        count: u32,
    },

    union_type: struct {
        type_list_index: u32,
        count: u32,
    },
};

pub const TypePool = struct {
    allocator: std.mem.Allocator,
    types: ArrayList(Type),
    type_list_buffer: std.ArrayList(TypeId),
    named_type_cache: std.AutoHashMap(StringId, TypeId),
    union_cache: TypeListMap,

    pub const UNRESOLVED = 0;
    pub const ANYERROR = 1;
    pub const VOID = 2;
    pub const NULL = 3;
    pub const BOOL = 4;
    pub const INT = 5;
    pub const FLOAT = 6;
    pub const STRING = 7;
    pub const MODULE = 8;
    pub const ERROR_TYPE = 9;

    pub fn init(allocator: Allocator) !TypePool {
        var pool = TypePool{
            .allocator = allocator,
            .types = ArrayList(Type).init(allocator),
            .type_list_buffer = std.ArrayList(TypeId).init(allocator),
            .named_type_cache = std.AutoHashMap(StringId, TypeId).init(allocator),
            .union_cache = TypeListMap.init(allocator),
        };

        try pool.types.append(.{ .unresolved = undefined });
        try pool.types.append(.{ .anyerror = undefined });
        try pool.types.append(.{ .void = undefined });
        try pool.types.append(.{ .null = undefined });
        try pool.types.append(.{ .bool = undefined });
        try pool.types.append(.{ .int = undefined });
        try pool.types.append(.{ .float = undefined });
        try pool.types.append(.{ .string = undefined });
        try pool.types.append(.{ .module = undefined });
        try pool.types.append(.{ .error_type = undefined });

        return pool;
    }

    pub fn deinit(self: *TypePool) void {
        self.types.deinit();
        self.type_list_buffer.deinit();
        self.named_type_cache.deinit();
        self.union_cache.deinit();
    }

    /// a type is nullable when the type is null or a union type that contains null
    pub fn isNullable(self: *const TypePool, type_id: TypeId) bool {
        if (type_id == TypePool.NULL) return true;

        const type_struct = self.types.items[type_id];
        if (type_struct != .union_type) return false;

        const members = self.getUnionMembers(type_struct);
        for (members) |member| {
            // recursion for nested unions
            if (self.isNullable(member)) {
                return true;
            }
        }

        return false;
    }

    /// a type is numeric, when it is int, float or a union type containing only numeric types
    pub fn isNumeric(self: *const TypePool, type_id: TypeId) bool {
        if (type_id == TypePool.INT or type_id == TypePool.FLOAT) {
            return true;
        }

        const t = self.types.items[type_id];
        if (t != .union_type) return false;

        const members = self.getUnionMembers(t);
        for (members) |member| {
            // recursion for nested unions
            if (!self.isNumeric(member)) {
                return false;
            }
        }
        return true;
    }

    /// a type is an error union, when it is a type union that contains an ErrorSet
    pub fn isErrorUnion(self: *const TypePool, type_id: TypeId) bool {
        const t = self.types.items[type_id];
        if (t != .union_type) return false;

        const members = self.getUnionMembers(t);
        for (members) |member| {
            if (self.types.items[member] == .error_set) {
                return true;
            } else if (self.isErrorUnion(member)) {
                return true;
            }
        }

        return false;
    }

    /// a type is assignable to another type, when both type are the same or target is a superset of source
    pub fn isAssignable(self: *const TypePool, target_id: TypeId, source_id: TypeId) bool {
        if (target_id == source_id) return true;

        const target = self.types.items[target_id];
        switch (target) {
            .unresolved => unreachable,
            .void => unreachable,
            .null => return false, // null is only assignable to null. Since target_id != source_id , the source can not be of type null
            .bool => return false, // same with bool
            .int => return false, // and so on
            .float => return source_id == TypePool.INT, // int type can be promoted to float
            .string => return false,
            .module => unreachable,
            .anyerror => return source_id == TypePool.ERROR_TYPE,
            .error_type => {
                const source = self.types.items[source_id];
                return target.error_type == source.error_type;
            },
            .error_set => {
                const members = self.getErrorSetMembers(target);
                for (members) |member| {
                    if (self.isAssignable(member, source_id)) {
                        return true;
                    }
                }
                return false;
            },
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

    pub fn getOrCreateErrorType(self: *TypePool, name_id: StringId) Allocator.Error!TypeId {
        // return type_id if cached
        if (self.named_type_cache.get(name_id)) |error_type_id| {
            return error_type_id;
        }

        // create error_type otherwise
        const error_type_id = self.types.items.len;
        try self.types.append(.{
            .error_type = name_id,
        });
        try self.named_type_cache.put(name_id, error_type_id);

        return error_type_id;
    }

    pub fn getType(self: *TypePool, name_id: StringId) !TypeId {
        if (self.named_type_cache.get(name_id)) |error_type_id| {
            return error_type_id;
        }

        return error.NotFound;
    }

    pub fn getOrCreateUnionType(self: *TypePool, member_types: []const TypeId) Allocator.Error!TypeId {
        // sort / canonicalize member_type, so that (int|float) == (float|int)
        const sorted_members = try self.allocator.alloc(TypeId, member_types.len);
        defer self.allocator.free(sorted_members);

        @memcpy(sorted_members, member_types);
        std.mem.sort(TypeId, sorted_members, {}, std.sort.asc(TypeId));

        // return type_id if cached
        if (self.union_cache.get(sorted_members)) |type_id| {
            return type_id;
        }

        // create type otherwise
        const list_index: u32 = @intCast(self.type_list_buffer.items.len);
        try self.type_list_buffer.appendUnalignedSlice(sorted_members);

        const type_id: TypeId = @intCast(self.types.items.len);
        try self.types.append(.{ .union_type = .{
            .type_list_index = list_index,
            .count = @intCast(sorted_members.len),
        } });

        // put union in cache
        const list_slice = self.type_list_buffer.items[list_index .. list_index + sorted_members.len];
        try self.union_cache.put(list_slice, type_id);

        return type_id;
    }

    inline fn getUnionMembers(self: *const TypePool, union_type: Type) []const TypeId {
        return self.type_list_buffer.items[union_type.union_type.type_list_index .. union_type.union_type.type_list_index + union_type.union_type.count];
    }

    inline fn getErrorSetMembers(self: *const TypePool, error_set: Type) []const TypeId {
        return self.type_list_buffer.items[error_set.error_set.type_list_index .. error_set.error_set.type_list_index + error_set.error_set.count];
    }
};

const TypeListMap = std.HashMap([]const TypeId, TypeId, TypeListContext, 80);

pub const TypeListContext = struct {
    pub fn hash(self: @This(), key: []const TypeId) u64 {
        _ = self;
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(key));
    }
    pub fn eql(self: @This(), a: []const TypeId, b: []const TypeId) bool {
        _ = self;
        return std.mem.eql(TypeId, a, b);
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const as = @import("as");
const StringId = as.common.StringId;

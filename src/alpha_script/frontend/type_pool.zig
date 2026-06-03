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
    function,

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
    function: struct {
        type_list_index: u32,
        count: u32,
    },

    anyerror,
    error_type: ErrorId,
    error_set: struct {
        type_list_index: u32,
        count: u32,
    },

    union_type: struct {
        type_list_index: u32,
        count: u32,
    },
};

pub const ErrorId = u32;
pub const ErrorPool = struct {
    allocator: std.mem.Allocator,
    error_ids: std.AutoArrayHashMap(StringId, ErrorId),

    pub fn init(allocator: Allocator) ErrorPool {
        return .{
            .allocator = allocator,
            .error_ids = std.AutoArrayHashMap(StringId, ErrorId).init(allocator),
        };
    }

    pub fn deinit(self: *ErrorPool) void {
        self.error_ids.deinit();
    }

    /// create an ErrorType by its name
    pub fn getOrCreateError(self: *ErrorPool, name_id: StringId) Allocator.Error!ErrorId {
        // return type_id if cached
        if (self.error_ids.get(name_id)) |error_id| {
            return error_id;
        }

        // create error_type otherwise
        const error_id: ErrorId = @intCast(self.error_ids.count());
        try self.error_ids.put(name_id, error_id);

        return error_id;
    }

    pub fn getErrorNameId(self: *const ErrorPool, error_id: ErrorId) StringId {
        return self.error_ids.keys()[error_id];
    }
};

pub const TypePool = struct {
    const Error = error{
        RedaclarationError,
        NotFound,
        NotCallable,
    };
    allocator: std.mem.Allocator,
    error_pool: *ErrorPool,
    types: ArrayList(Type),
    type_list_buffer: std.ArrayList(TypeId),
    named_type_cache: std.AutoHashMap(StringId, TypeId),
    function_cache: TypeListMap,
    union_cache: TypeListMap,
    error_set_cache: TypeListMap,
    error_type_cache: std.AutoHashMap(ErrorId, TypeId),

    pub const UNRESOLVED = 0;
    pub const ANYERROR = 1;
    pub const VOID = 2;
    pub const NULL = 3;
    pub const BOOL = 4;
    pub const INT = 5;
    pub const FLOAT = 6;
    pub const STRING = 7;
    pub const MODULE = 8;

    pub fn init(error_pool: *ErrorPool, allocator: Allocator) !TypePool {
        var pool = TypePool{
            .allocator = allocator,
            .error_pool = error_pool,
            .types = .{},
            .type_list_buffer = .{},
            .named_type_cache = std.AutoHashMap(StringId, TypeId).init(allocator),
            .function_cache = TypeListMap.init(allocator),
            .union_cache = TypeListMap.init(allocator),
            .error_set_cache = TypeListMap.init(allocator),
            .error_type_cache = std.AutoHashMap(ErrorId, TypeId).init(allocator),
        };

        try pool.types.append(allocator, .{ .unresolved = undefined });
        try pool.types.append(allocator, .{ .anyerror = undefined });
        try pool.types.append(allocator, .{ .void = undefined });
        try pool.types.append(allocator, .{ .null = undefined });
        try pool.types.append(allocator, .{ .bool = undefined });
        try pool.types.append(allocator, .{ .int = undefined });
        try pool.types.append(allocator, .{ .float = undefined });
        try pool.types.append(allocator, .{ .string = undefined });
        try pool.types.append(allocator, .{ .module = undefined });

        return pool;
    }

    pub fn deinit(self: *TypePool) void {
        self.types.deinit(self.allocator);
        self.type_list_buffer.deinit(self.allocator);
        self.named_type_cache.deinit();
        self.union_cache.deinit();
        self.error_set_cache.deinit();
        self.error_type_cache.deinit();
    }

    pub fn getTypeNameAlloc(
        self: *const TypePool,
        allocator: std.mem.Allocator,
        type_id: TypeId,
        string_table: *const StringTable,
    ) ![]u8 {
        const t = self.types.items[type_id];
        var type_name: std.ArrayList(u8) = .{};

        switch (t) {
            .unresolved => try type_name.appendSlice(allocator, "unresolved"),
            .void => try type_name.appendSlice(allocator, "void"),
            .null => try type_name.appendSlice(allocator, "null"),
            .bool => try type_name.appendSlice(allocator, "bool"),
            .int => try type_name.appendSlice(allocator, "int"),
            .float => try type_name.appendSlice(allocator, "float"),
            .string => try type_name.appendSlice(allocator, "string"),
            .module => try type_name.appendSlice(allocator, "module"),
            .function => {
                try type_name.appendSlice(allocator, "fn (");
                const signature = self.getFunctionSignature(t);
                for (signature[0 .. signature.len - 1]) |parameter_id| {
                    const name = try self.getTypeNameAlloc(allocator, parameter_id, string_table);
                    defer allocator.free(name);

                    try type_name.appendSlice(allocator, name);
                    try type_name.append(allocator, ',');
                }

                if (signature.len > 1) {
                    _ = type_name.pop();
                }

                try type_name.appendSlice(allocator, "): ");

                const return_name = try self.getTypeNameAlloc(allocator, signature[signature.len - 1], string_table);
                defer allocator.free(return_name);

                try type_name.appendSlice(allocator, return_name);

                return type_name.items;
            },
            .anyerror => try type_name.appendSlice(allocator, "Anyerror"),
            .error_type => try type_name.appendSlice(allocator, string_table.get(self.types.items[type_id].error_type)),
            .error_set => {
                try type_name.appendSlice(allocator, "error{");
                const members = self.getErrorSetMembers(t);

                for (members) |error_type_id| {
                    const error_type = self.types.items[error_type_id];
                    const error_name_id = self.error_pool.getErrorNameId(error_type.error_type);
                    const error_name = string_table.get(error_name_id);

                    try type_name.appendSlice(allocator, error_name);
                    try type_name.append(allocator, ',');
                }

                if (members.len > 0) {
                    _ = type_name.pop();
                }

                try type_name.append(allocator, '}');

                return type_name.items;
            },
            .union_type => {
                const members = self.getUnionMembers(t);

                for (members) |member| {
                    const name = try self.getTypeNameAlloc(allocator, member, string_table);
                    defer allocator.free(name);

                    try type_name.appendSlice(allocator, name);
                    try type_name.append(allocator, '|');
                }

                if (type_name.items.len > 0) {
                    _ = type_name.pop();
                }
            },
        }
        return type_name.items;
    }

    pub fn isCallable(self: *const TypePool, type_id: TypeId) bool {
        const t = self.types.items[type_id];
        return t == .function;
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
            const member_type = self.types.items[member];
            if (member_type == .anyerror) {
                return true;
            } else if (member_type == .error_set) {
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
            .void => return false,
            .null => return false, // null is only assignable to null. Since target_id != source_id , the source can not be of type null
            .bool => return false, // same with bool
            .int => return false, // and so on
            .float => return source_id == TypePool.INT, // int type can be promoted to float
            .string => return false,
            .module => unreachable,
            .function => {
                const source = self.types.items[source_id];
                if (source != .function) {
                    return false;
                }

                const target_signature = self.getFunctionSignature(target);
                const source_signature = self.getFunctionSignature(source);

                if (target_signature.len != source_signature.len) {
                    // TODO special case optionas:
                    // This is Invalid (we dont know how test is called):
                    //   const test:(a:Int, b:Int=42)void = fn(a:Int)void{}
                    // This could be valid (when test is called, b would get always the default):
                    //   const test:(a:Int)void = fn(a:Int, b:Int=42)void{}
                    return false;
                }

                for (0..target_signature.len) |index| {
                    if (target_signature[index] != source_signature[index]) {
                        return false;
                    }
                }

                return true;
            },
            .anyerror => {
                const source_type = self.types.items[source_id];
                return source_type == .error_type;
            },
            .error_type => {
                const source = self.types.items[source_id];

                if (source != .error_type) return false;
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

    pub fn getCallableSignature(self: *const TypePool, type_id: TypeId) !struct { param_types: []const TypeId, return_type: TypeId } {
        if (!self.isCallable(type_id)) {
            return Error.NotCallable;
        }

        const t = self.types.items[type_id];
        const signature = self.getFunctionSignature(t);
        return .{
            .param_types = signature[0 .. signature.len - 1],
            .return_type = signature[signature.len - 1],
        };
    }

    /// bind a StringId (name) to a type_id
    pub fn declareNamedType(self: *TypePool, name_id: StringId, type_id: TypeId) !void {
        if (self.named_type_cache.contains(name_id)) {
            return Error.RedaclarationError;
        }
        try self.named_type_cache.put(name_id, type_id);
    }

    /// retrive a type by the bound name
    pub fn getType(self: *TypePool, name_id: StringId) ?TypeId {
        if (self.named_type_cache.get(name_id)) |error_type_id| {
            return error_type_id;
        }

        return null;
    }

    /// creates a function type
    pub fn getOrCreateFunctionType(self: *TypePool, parameter_type_ids: ?[]const TypeId, return_type_id: TypeId) Allocator.Error!TypeId {
        // concat all types so TypeListMap can be used as cache
        const signature_len = if (parameter_type_ids) |ids| ids.len + 1 else 1;
        const signature = try self.allocator.alloc(TypeId, signature_len);
        if (parameter_type_ids) |ids| {
            @memcpy(signature[0..ids.len], ids);
            signature[signature.len - 1] = return_type_id;
        } else {
            signature[0] = return_type_id;
        }

        if (self.function_cache.get(signature)) |type_id| {
            return type_id;
        }

        const list_index: u32 = @intCast(self.type_list_buffer.items.len);
        try self.type_list_buffer.appendSlice(self.allocator, signature);

        const type_id: TypeId = @intCast(self.types.items.len);
        try self.types.append(self.allocator, .{ .function = .{
            .type_list_index = list_index,
            .count = @intCast(signature.len),
        } });

        return type_id;
    }

    /// create an type union
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
        try self.type_list_buffer.appendSlice(self.allocator, sorted_members);

        const type_id: TypeId = @intCast(self.types.items.len);
        try self.types.append(self.allocator, .{ .union_type = .{
            .type_list_index = list_index,
            .count = @intCast(sorted_members.len),
        } });

        // put union in cache
        const list_slice = self.type_list_buffer.items[list_index .. list_index + sorted_members.len];
        try self.union_cache.put(list_slice, type_id);

        return type_id;
    }

    /// remove the null type from a typeunion
    pub fn getOrCreateNotNullableType(self: *TypePool, type_id: TypeId) !TypeId {
        const t = self.types.items[type_id];

        switch (t) {
            .null => return TypePool.VOID,
            .union_type => {
                var new_members: std.ArrayList(TypeId) = .{};
                defer new_members.deinit(self.allocator);

                const members = self.getUnionMembers(t);
                for (members) |member| {
                    const member_type = self.types.items[member];
                    if (member_type == .null) continue;
                    try new_members.append(self.allocator, member);
                }
                if (new_members.items.len == 1) {
                    return new_members.items[0];
                } else {
                    return try self.getOrCreateUnionType(new_members.items);
                }
            },
            else => {
                return type_id;
            },
        }
    }

    /// retrive the ErrorSet from an ErrorUnion
    pub fn getErrorSetFromTypeUnion(self: *const TypePool, type_id: TypeId) Error!TypeId {
        const t = self.types.items[type_id];

        switch (t) {
            .error_set => return type_id,
            .union_type => {
                const members = self.getUnionMembers(t);
                for (members) |member| {
                    const member_type = self.types.items[member];
                    if (member_type == .error_set) {
                        return member;
                    } else if (member_type == .anyerror) {
                        return member;
                    }
                }
                return Error.NotFound;
            },
            else => {
                return Error.NotFound;
            },
        }
    }

    /// remove the ErrorSet from an ErrorUnion
    pub fn getOrCreateNotErrorUnionType(self: *TypePool, type_id: TypeId) !TypeId {
        const t = self.types.items[type_id];

        switch (t) {
            .error_set => return TypePool.VOID,
            .union_type => {
                var new_members: std.ArrayList(TypeId) = .{};
                defer new_members.deinit(self.allocator);

                const members = self.getUnionMembers(t);
                for (members) |member| {
                    const member_type = self.types.items[member];
                    if (member_type == .error_set) continue;
                    try new_members.append(self.allocator, member);
                }
                if (new_members.items.len == 1) {
                    return new_members.items[0];
                } else {
                    return try self.getOrCreateUnionType(new_members.items);
                }
            },
            else => {
                return type_id;
            },
        }
    }

    pub fn isErrorSet(self: *TypePool, type_id: TypeId) bool {
        return self.types.items[type_id] == .error_set;
    }

    pub fn getOrCreateErrorType(self: *TypePool, error_name_id: StringId) !TypeId {
        const error_id = try self.error_pool.getOrCreateError(error_name_id);

        if (self.error_type_cache.get(error_id)) |error_type_id| {
            return error_type_id;
        }

        const type_id: TypeId = @intCast(self.types.items.len);
        try self.types.append(self.allocator, .{
            .error_type = error_id,
        });
        try self.error_type_cache.putNoClobber(error_id, type_id);
        return type_id;
    }

    pub fn getTypeByErrorId(self: *TypePool, error_id: ErrorId) ?TypeId {
        return self.error_type_cache.get(error_id);
    }

    /// create an ErrorSet
    pub fn getOrCreateErrorSet(self: *TypePool, member_errors: []const TypeId) Allocator.Error!TypeId {
        // sort / canonicalize member_type, so that (int|float) == (float|int)
        const sorted_members = try self.allocator.alloc(TypeId, member_errors.len);
        defer self.allocator.free(sorted_members);

        @memcpy(sorted_members, member_errors);
        std.mem.sort(TypeId, sorted_members, {}, std.sort.asc(TypeId));

        // return type_id if cached
        if (self.error_set_cache.get(sorted_members)) |type_id| {
            return type_id;
        }

        // create type otherwise
        const list_index: u32 = @intCast(self.type_list_buffer.items.len);
        try self.type_list_buffer.appendSlice(self.allocator, sorted_members);

        const type_id: TypeId = @intCast(self.types.items.len);
        try self.types.append(self.allocator, .{ .error_set = .{
            .type_list_index = list_index,
            .count = @intCast(sorted_members.len),
        } });

        // put union in cache
        const list_slice = self.type_list_buffer.items[list_index .. list_index + sorted_members.len];
        try self.error_set_cache.put(list_slice, type_id);

        return type_id;
    }

    pub fn isErrorInSet(self: *TypePool, set_id: TypeId, error_type_id: TypeId) bool {
        const set = self.types.items[set_id];
        const members = self.getErrorSetMembers(set);
        for (members) |member_error_id| {
            if (member_error_id == error_type_id) return true;
        }
        return false;
    }

    /// retrive the signature oof a function type, the last type_id in the returned slice is the return type
    inline fn getFunctionSignature(self: *const TypePool, function: Type) []const TypeId {
        return self.type_list_buffer.items[function.function.type_list_index .. function.function.type_list_index + function.function.count];
    }

    /// retrive all member types of an type union
    inline fn getUnionMembers(self: *const TypePool, union_type: Type) []const TypeId {
        return self.type_list_buffer.items[union_type.union_type.type_list_index .. union_type.union_type.type_list_index + union_type.union_type.count];
    }

    /// retrive all members of an error set
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
const StringTable = as.common.StringTable;

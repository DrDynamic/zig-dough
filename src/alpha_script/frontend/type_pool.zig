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
};

pub const Type = struct {
    tag: TypeTag,

    data: union {
        pointer_to: TypeId,
    },
};

pub const TypePool = struct {
    types: ArrayList(Type),
    extra_data: ArrayList(u32),

    pub const UNRESOLVED = 0;
    pub const VOID = 1;
    pub const NULL = 2;
    pub const BOOL = 3;
    pub const INT = 4;
    pub const FLOAT = 5;
    pub const STRING = 6;
    pub const MODULE = 7;

    pub fn init(allocatior: Allocator) !TypePool {
        var pool = TypePool{
            .types = ArrayList(Type).init(allocatior),
            .extra_data = ArrayList(u32).init(allocatior),
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
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

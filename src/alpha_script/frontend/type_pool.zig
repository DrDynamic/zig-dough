pub const TypeId = u32;

pub const TypeTag = enum(u8) {
    unresolved,
    void,
    null,
    bool,
    number,
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
    pub const NUMBER = 4;
    pub const STRING = 5;
    pub const MODULE = 6;

    pub fn init(allocatior: Allocator) !TypePool {
        var pool = TypePool{
            .types = ArrayList(Type).init(allocatior),
            .extra_data = ArrayList(u32).init(allocatior),
        };

        try pool.types.append(.{ .tag = .unresolved });
        try pool.types.append(.{ .tag = .void });
        try pool.types.append(.{ .tag = .null });
        try pool.types.append(.{ .tag = .bool });
        try pool.types.append(.{ .tag = .number });
        try pool.types.append(.{ .tag = .string });
        try pool.types.append(.{ .tag = .module });
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

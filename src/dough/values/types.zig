pub const TypeError = error{NoSimpleType};

pub const FunctionMeta = struct {
    parameter_types: []Type,
    return_type: Type,
};

pub const TypeUnionMeta = struct {
    types: []Type,
};

pub const Type = union(enum) {
    Void,
    Null,
    Bool,
    Number,
    String,
    Function: *FunctionMeta,
    Module,

    // Meta Types
    TypeUnion: *TypeUnionMeta,

    pub fn makeVoid() Type {
        return Type{ .Void = {} };
    }

    pub fn makeNull() Type {
        return Type{ .Null = {} };
    }

    pub fn makeBool() Type {
        return Type{ .Bool = {} };
    }

    pub fn makeNumber() Type {
        return Type{ .Number = {} };
    }

    pub fn makeString() Type {
        return Type{ .String = {} };
    }

    pub fn makeFunction() Type {
        return Type{ .Function = undefined };
    }

    pub fn makeModule() Type {
        return Type{ .Module = {} };
    }

    pub fn makeTypeUnion(types: []Type) !Type {
        const own_types = try dough.allocator.alloc(Type, types.len);
        @memcpy(own_types, types);

        var type_meta = try dough.allocator.create(TypeUnionMeta);
        type_meta.types = own_types;

        return Type{ .TypeUnion = type_meta };
    }

    pub fn deinit(self: Type) void {
        switch (self) {
            .TypeUnion => |union_type| {
                dough.allocator.free(union_type.types);
                dough.allocator.destroy(union_type);
            },
            else => {},
        }
    }

    pub fn equals(self: Type, other: Type) bool {
        return switch (self) {
            else => std.meta.activeTag(self) == std.meta.activeTag(other),
        };
    }

    pub fn satisfiesShape(self: Type, value_type: Type) bool {
        return switch (self) {
            .Void => false, // nothing can be assigned to void
            .Null => value_type == .Null,
            .Bool => value_type == .Bool,
            .Number => value_type == .Number,
            .String => value_type == .String,
            .Function => false, // no functions in frontend yet
            .Module => false, // no mudules in frontend yet
            .TypeUnion => |union_type| TypeUnion_case: {
                break :TypeUnion_case switch (value_type) {
                    .Void, .Function, .Module => false,

                    .Null, .Bool, .Number, .String => containsType(union_type.types, value_type),

                    .TypeUnion => |value_union| containsAllTypes(union_type.types, value_union.types),
                };
            },
        };
    }

    pub fn format(
        self: Type,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .Void => try out_stream.print("Void", .{}),
            .Null => try out_stream.print("Null", .{}),
            .Bool => try out_stream.print("Bool", .{}),
            .Number => try out_stream.print("Number", .{}),
            .String => try out_stream.print("String", .{}),
            .Function => try out_stream.print("Function () => Void", .{}),
            .Module => try out_stream.print("Module", .{}),
            .TypeUnion => |union_type| {
                for (0.., union_type.types) |index, t| {
                    if (index != 0) {
                        try out_stream.print(" or ", .{});
                    }
                    try out_stream.print("{}", .{t});
                }
            },
        }
    }

    pub fn fromToken(token: Token) !Type {
        return switch (token.token_type.?) {
            .TypeBool => Type.makeBool(),
            .TypeNull => Type.makeNull(),
            .TypeNumber => Type.makeNumber(),
            .TypeString => Type.makeString(),
            .TypeVoid => Type.makeVoid(),
            else => TypeError.NoSimpleType,
        };
    }
};

fn containsType(haystack: []Type, needle: Type) bool {
    for (haystack) |element| {
        if (element.equals(needle)) {
            return true;
        }
    }
    return false;
}

fn containsAllTypes(haystack: []Type, needles: []Type) bool {
    if (haystack.len < needles.len) {
        return false;
    }

    for (needles) |needle| {
        if (!containsType(haystack, needle)) {
            return false;
        }
    }
    return true;
}

const std = @import("std");
const dough = @import("dough");
const Token = dough.frontend.Token;

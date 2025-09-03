pub const TypeError = error{NoSimpleType};

pub const FunctionMeta = struct {
    parameter_types: []Type,
    return_type: Type,
};

pub const TypeUnionMeta = struct {
    name: ?[]const u8,
    types: []Type,

    pub fn makeTypeUnion(name: ?[]const u8, types: []Type) !Type {
        var own_name: ?[]const u8 = null;
        if (name) |assured_name| {
            const tmp = try dough.allocator.alloc(u8, assured_name.len);
            @memcpy(tmp, assured_name);
            own_name = tmp;
        }

        const own_types = try dough.allocator.alloc(Type, types.len);
        @memcpy(own_types, types);

        var type_meta = try dough.allocator.create(TypeUnionMeta);
        type_meta.name = own_name;
        type_meta.types = own_types;

        return Type{ .TypeUnion = type_meta };
    }

    pub fn copyWithoutType(self: TypeUnionMeta, lose_type: Type) !Type {
        var new_size: usize = 0;
        for (self.types) |own_type| {
            if (!own_type.equals(lose_type)) {
                new_size += 1;
            }
        }

        const own_types = try dough.allocator.alloc(Type, new_size);
        for (0.., self.types) |index, own_type| {
            if (!own_type.equals(lose_type)) {
                own_types[index] = own_type;
            }
        }

        var type_meta = try dough.allocator.create(TypeUnionMeta);
        type_meta.name = null;
        type_meta.types = own_types;

        return Type{ .TypeUnion = type_meta };
    }
};

pub const Type = union(enum) {
    Void,
    Null,
    Error,
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

    pub fn makeTypeUnion(name: ?[]const u8, types: []Type) !Type {
        return TypeUnionMeta.makeTypeUnion(name, types);
    }

    pub fn deinit(self: Type) void {
        switch (self) {
            .TypeUnion => |union_type| {
                if (union_type.name) |assured_name| {
                    dough.allocator.free(assured_name);
                }
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
            .Error => value_type == .Error,
            .Bool => value_type == .Bool,
            .Number => value_type == .Number,
            .String => value_type == .String,
            .Function => false, // no functions in frontend yet
            .Module => false, // no mudules in frontend yet
            .TypeUnion => |union_type| TypeUnion_case: {
                break :TypeUnion_case switch (value_type) {
                    .Void, .Function, .Module => false,

                    .Null, .Error, .Bool, .Number, .String => containsType(union_type.types, value_type),

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
        _ = options;

        switch (self) {
            .Void => try out_stream.print("Void", .{}),
            .Null => try out_stream.print("Null", .{}),
            .Error => try out_stream.print("Error", .{}),
            .Bool => try out_stream.print("Bool", .{}),
            .Number => try out_stream.print("Number", .{}),
            .String => try out_stream.print("String", .{}),
            .Function => try out_stream.print("Function () => Void", .{}),
            .Module => try out_stream.print("Module", .{}),
            .TypeUnion => |union_type| {
                if (!std.mem.eql(u8, fmt, "shape")) {
                    if (union_type.name) |name| {
                        try out_stream.print("{s}", .{name});
                        return;
                    }
                }

                for (0.., union_type.types) |index, t| {
                    if (index != 0) {
                        try out_stream.print(" or ", .{});
                    }
                    try out_stream.print("{}", .{t});
                }
            },
        }
    }

    pub fn getName(self: Type) ?[]const u8 {
        return switch (self) {
            .Void => "Void",
            .Null => "Null",
            .Error => "Error",
            .Bool => "Bool",
            .Number => "Number",
            .String => "String",
            .Function => unreachable,
            .Module => unreachable,
            .TypeUnion => |union_type| union_type.name,
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

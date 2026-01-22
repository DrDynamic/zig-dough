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
        var index: u16 = 0;
        for (self.types) |own_type| {
            if (!own_type.equals(lose_type)) {
                own_types[index] = own_type;
                index += 1;
            }
        }

        // we could do this, but then we need to deal with deinit() of the type...
        // if(own_types.len == 1) {
        //     defer dough.allocator.free(own_types);
        //     return own_types[0];
        // }

        var type_meta = try dough.allocator.create(TypeUnionMeta);
        type_meta.name = null;
        type_meta.types = own_types;

        return Type{ .TypeUnion = type_meta };
    }

    pub fn copyWithoutErrorSets(self: TypeUnionMeta) !Type {
        var new_size: usize = 0;
        for (self.types) |own_type| {
            if (!own_type.isError()) {
                new_size += 1;
            }
        }

        const own_types = try dough.allocator.alloc(Type, new_size);
        var index: u16 = 0;
        for (self.types) |own_type| {
            if (!own_type.isError()) {
                own_types[index] = own_type;
                index += 1;
            }
        }

        var type_meta = try dough.allocator.create(TypeUnionMeta);
        type_meta.name = null;
        type_meta.types = own_types;

        return Type{ .TypeUnion = type_meta };
    }

    pub fn copyOnlyErrorSets(self: TypeUnionMeta) !Type {
        var new_size: usize = 0;
        for (self.types) |own_type| {
            if (own_type.isError()) {
                new_size += 1;
            }
        }

        const own_types = try dough.allocator.alloc(Type, new_size);
        var index: u16 = 0;
        for (self.types) |own_type| {
            if (own_type.isError()) {
                own_types[index] = own_type;
                index += 1;
            }
        }

        var type_meta = try dough.allocator.create(TypeUnionMeta);
        type_meta.name = null;
        type_meta.types = own_types;

        return Type{ .TypeUnion = type_meta };
    }

    pub fn isErrorUnion(self: *TypeUnionMeta) bool {
        for (self.types) |own_type| {
            if (own_type == .AnyError) {
                return true;
            }
            if (own_type.isTypeObject(.ErrorSet)) {
                return true;
            }
        }
        return false;
    }
};

pub const Type = union(enum) {
    AnyError,
    Void,
    Null,
    Bool,
    Number,
    String,
    Function: *FunctionMeta,
    Module,

    // Meta Types
    TypeUnion: *TypeUnionMeta,
    TypeObject: *objects.DoughObject,

    pub fn makeAnyError() Type {
        return Type{ .AnyError = {} };
    }

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

    pub fn makeTypeObject(object: *objects.DoughObject) Type {
        return Type{ .TypeObject = object };
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
            .TypeObject => {
                return (other == .TypeObject and self.TypeObject == other.TypeObject);
            },
            else => std.meta.activeTag(self) == std.meta.activeTag(other),
        };
    }

    pub fn satisfiesShape(self: Type, value_type: Type) bool {
        return switch (self) {
            .AnyError => value_type.isError(),
            .Void => false, // nothing can be assigned to void
            .Null => value_type == .Null,
            .Bool => value_type == .Bool,
            .Number => value_type == .Number,
            .String => value_type == .String,
            .Function => false, // no functions in frontend yet
            .Module => false, // no mudules in frontend yet
            .TypeUnion => |union_type| {
                if (value_type == .TypeUnion) {
                    for (value_type.TypeUnion.types) |vt| {
                        if (!self.satisfiesShape(vt)) {
                            return false;
                        }
                    }
                    return true;
                }

                for (union_type.types) |own_type| {
                    if (own_type.satisfiesShape(value_type)) {
                        return true;
                    }
                }
                return false;
            },
            .TypeObject => |object| {
                return switch (object.obj_type) {
                    .ErrorSet => {
                        if (value_type == .TypeObject and value_type.TypeObject.obj_type == .Error) {
                            return object.as(objects.DoughErrorSet) == value_type.TypeObject.as(objects.DoughError).error_set;
                        }
                        return false;
                    },
                    else => unreachable,
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
        switch (self) {
            .AnyError => try out_stream.print("AnyError", .{}),
            .Void => try out_stream.print("Void", .{}),
            .Null => try out_stream.print("Null", .{}),
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
            .TypeObject => |type_object| {
                try type_object.format(fmt, options, out_stream);
                //                try out_stream.print("{s}", .{self.getName() orelse "???"});
            },
        }
    }

    pub fn getName(self: Type) ?[]const u8 {
        return switch (self) {
            .AnyError => "AnyError",
            .Void => "Void",
            .Null => "Null",
            .Bool => "Bool",
            .Number => "Number",
            .String => "String",
            .Function => unreachable,
            .Module => unreachable,
            .TypeUnion => |union_type| union_type.name,
            .TypeObject => |object| {
                return switch (object.obj_type) {
                    .ErrorSet => object.as(objects.DoughErrorSet).name,
                    .Error => object.as(objects.DoughError).name,
                    else => unreachable,
                };
            },
        };
    }

    pub fn isTypeObject(self: Type, obj_type: objects.ObjType) bool {
        return self == .TypeObject and self.TypeObject.obj_type == obj_type;
    }

    pub fn asObject(self: Type, comptime T: type) *T {
        return self.TypeObject.as(T);
    }

    pub fn isError(self: Type) bool {
        return self == .TypeObject and self.TypeObject.obj_type == .Error;
    }

    pub fn asError(self: Type) *objects.DoughError {
        return self.TypeObject.as(objects.DoughError);
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

fn satisfiesType(haystack: []Type, needle: Type) bool {
    return containsType(haystack ++ .AnyError, needle);
}

const std = @import("std");
const dough = @import("dough");
const Token = dough.frontend.Token;

const objects = dough.values.objects;

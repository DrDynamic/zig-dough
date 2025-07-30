const std = @import("std");
const globals = @import("../globals.zig");
pub const objects = @import("./objects.zig");

pub const ValueType = enum {
    Uninitialized,
    Void,
    Null,
    Bool,
    Number,
    Object,
};

// TODO: add NAN_BOXING
pub const Value = UnionValue;

const UnionValue = union(ValueType) {
    // for variables, constants, etc. that have been defined but didn't get a real value (yet)
    Uninitialized,
    Void,

    Null,
    Bool: bool,
    Number: f64,
    Object: *objects.DoughObject,

    pub fn print(self: UnionValue) void {
        // TODO: don't use debug.print!
        switch (self) {
            .Uninitialized => std.debug.print("uninitialized", .{}),
            .Void => std.debug.print("void", .{}),
            .Null => std.debug.print("null", .{}),
            .Bool => |val| std.debug.print("{s}", .{if (val) "true" else "false"}),
            .Number => |val| std.debug.print("{d}", .{val}),
            .Object => |val| val.print(),
        }
    }

    pub fn getType(self: UnionValue) ValueType {
        std.meta.activeTag(self);
    }

    pub fn toString(self: UnionValue) *objects.DoughString {
        return switch (self) {
            .Uninitialized => objects.DoughString.copy("uninitialized"),
            .Void => objects.DoughString.copy("void"),
            .Null => objects.DoughString.copy("null"),
            .Bool => |val| objects.DoughString.copy(if (val) "true" else "false"),
            .Number => |val| objects.DoughString.init(std.fmt.allocPrint(globals.allocator, "{d}", .{val}) catch @panic("failed to allocate memory!")),
            .Object => |val| val.toString(),
        };
    }

    pub inline fn isString(self: UnionValue) bool {
        return self.isObject() and self.toObject().obj_type == .String;
    }

    pub inline fn makeUninitialized() Value {
        return UnionValue{ .Uninitialized = {} };
    }

    pub inline fn isUninitialized(self: UnionValue) bool {
        return switch (self) {
            .Uninitialized => true,
            else => false,
        };
    }

    pub inline fn makeVoid() Value {
        return UnionValue{ .Void = {} };
    }

    pub inline fn isVoid(self: UnionValue) Value {
        return switch (self) {
            .Void => true,
            else => false,
        };
    }

    pub inline fn makeNull() Value {
        return UnionValue{ .Null = {} };
    }

    pub inline fn isNull(self: UnionValue) bool {
        return switch (self) {
            .Null => true,
            else => false,
        };
    }

    pub inline fn fromBoolean(value: bool) Value {
        return UnionValue{ .Bool = value };
    }

    pub inline fn toBoolean(self: UnionValue) bool {
        return self.Bool;
    }

    pub inline fn isBoolean(self: UnionValue) bool {
        return switch (self) {
            .Bool => true,
            else => false,
        };
    }

    pub inline fn fromNumber(value: f64) Value {
        return UnionValue{ .Number = value };
    }

    pub inline fn toNumber(self: UnionValue) f64 {
        return self.Number;
    }

    pub inline fn isNumber(self: UnionValue) bool {
        return switch (self) {
            .Number => true,
            else => false,
        };
    }

    pub inline fn fromObject(value: *objects.DoughObject) Value {
        return UnionValue{ .Object = value };
    }

    pub inline fn toObject(self: UnionValue) *objects.DoughObject {
        return self.Object;
    }

    pub inline fn isObject(self: UnionValue) bool {
        return switch (self) {
            .Object => true,
            else => false,
        };
    }
};

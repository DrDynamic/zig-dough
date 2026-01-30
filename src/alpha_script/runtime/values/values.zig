pub const ValueType = enum(u8) {
    uninitialized,
    null,
    bool,
    integer,
    float,
    object,
};
pub const Value = UnionValue;
pub const UnionValue = union(ValueType) {
    uninitialized,
    null,
    bool: bool,
    integer: i64,
    float: f64,
    object: *ObjectHeader,

    pub fn equals(self: UnionValue, other: Value) bool {
        const both_null = self.isNull() and other.isNull();
        const both_bool = self.isBool() and other.isBool();
        const both_numeric = self.isNumeric() and other.isNumeric();
        const both_object = self.isObject() and other.isObject();

        if (!both_null and
            !both_bool and
            !both_numeric and
            !both_object)
        {
            return false;
        }

        if (both_numeric) {
            const a = self.castToF64() catch return false;
            const b = other.castToF64() catch return false;
            return a == b;
        }

        return switch (self) {
            .uninitialized => false,
            .null => true,
            .bool => self.bool == other.bool,
            .object => self.toObject().equals(other),
            else => unreachable,
        };
    }

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .uninitialized => try writer.print("uninitialized", .{}),
            .null => try writer.print("null", .{}),
            .bool => try writer.print("{s}", .{if (self.bool) "true" else "false"}),
            .integer => try writer.print("{d}", .{self.integer}),
            .float => try writer.print("{d}", .{self.float}),
            .object => try writer.print("<object {*}>", .{self.object}),
        }
    }

    pub inline fn makeUninitialized() UnionValue {
        return .{.uninitialized};
    }

    pub inline fn isUninitialized(self: UnionValue) bool {
        return switch (self) {
            .uninitialized => true,
            else => false,
        };
    }

    pub inline fn makeNull() UnionValue {
        return .{ .null = undefined };
    }

    pub inline fn isNull(self: UnionValue) bool {
        return switch (self) {
            .null => true,
            else => false,
        };
    }

    pub inline fn makeBool(value: bool) UnionValue {
        return .{ .bool = value };
    }

    pub inline fn toBool(self: *const UnionValue) bool {
        return self.bool;
    }

    pub inline fn isBool(self: UnionValue) bool {
        return switch (self) {
            .bool => true,
            else => false,
        };
    }

    pub inline fn isNumeric(self: UnionValue) bool {
        return switch (self) {
            .integer, .float => true,
            else => false,
        };
    }

    pub fn castToF64(self: UnionValue) !f64 {
        return switch (self) {
            .integer => @floatFromInt(self.integer),
            .float => self.float,
            else => error.InvalidCast,
        };
    }

    pub inline fn makeInteger(value: i64) UnionValue {
        return .{ .integer = value };
    }

    pub inline fn toI64(self: *const UnionValue) i64 {
        return self.integer;
    }

    pub inline fn isInteger(self: UnionValue) bool {
        return switch (self) {
            .integer => true,
            else => false,
        };
    }

    pub inline fn makeFloat(value: f64) UnionValue {
        return .{ .float = value };
    }

    pub inline fn toF64(self: *const UnionValue) f64 {
        return self.float;
    }

    pub inline fn isFloat(self: UnionValue) bool {
        return switch (self) {
            .float => true,
            else => false,
        };
    }

    pub inline fn fromObject(value: *ObjectHeader) UnionValue {
        return .{ .object = value };
    }

    pub inline fn toObject(self: *const UnionValue) *ObjectHeader {
        return self.object;
    }

    pub inline fn isObject(self: UnionValue) bool {
        return switch (self) {
            .object => true,
            else => false,
        };
    }
};

const std = @import("std");
const objects = @import("objects.zig");
pub const ObjectType = objects.ObjectType;
pub const ObjectHeader = objects.ObjectHeader;
pub const ObjString = objects.ObjString;

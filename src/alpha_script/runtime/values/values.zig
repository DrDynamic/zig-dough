pub const ValueType = enum(u8) {
    uninitialized,
    null,
    bool,
    integer,
    float,
    object,
};

pub const Value = struct {
    tag: ValueType,
    data: union {
        boolean: bool,
        integer: i64,
        float: f64,
        object: *ObjectHeader,
    },

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.tag) {
            .uninitialized => try writer.print("uninitialized", .{}),
            .null => try writer.print("null", .{}),
            .bool => try writer.print("{s}", .{if (self.data.boolean) "true" else "false"}),
            .integer => try writer.print("{d}", .{self.data.integer}),
            .float => try writer.print("{d}", .{self.data.float}),
            .object => try writer.print("<object {*}>", .{self.data.object}),
        }
    }
};

const std = @import("std");
const objects = @import("objects.zig");
pub const ObjectType = objects.ObjectType;
pub const ObjectHeader = objects.ObjectHeader;
pub const ObjString = objects.ObjString;

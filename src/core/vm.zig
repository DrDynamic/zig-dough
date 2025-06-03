const std = @import("std");

pub const Vm = struct {
    allocator: std.mem.Allocator = undefined,
};

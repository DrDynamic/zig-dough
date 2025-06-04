const std = @import("std");

const core = @import("./core.zig");

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

pub const VirtualMachine = struct {
    dough_allocator: core.memory.GarbageColletingAllocator,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) VirtualMachine {
        return .{
            .dough_allocator = core.memory.GarbageColletingAllocator.init(allocator),
            .allocator = allocator,
        };
    }
};

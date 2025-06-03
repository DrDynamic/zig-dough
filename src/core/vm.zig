const std = @import("std");

const core = @import("./core.zig");

pub const InterpretError = error{
    CompileError,
    RuntimeError,
};

pub const VirtualMachine = struct {
    doughAllocator: core.memory.GarbageColletingAllocator,
    allocator: std.mem.Allocator,
};

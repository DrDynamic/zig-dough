var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub var allocator: std.mem.Allocator = undefined;
pub var garbage_collector: memory.GarbageColletingAllocator = undefined;

pub var compiler: core.compiler.ModuleCompiler = undefined;
pub var virtual_machine: core.vm.VirtualMachine = undefined;

pub var internedStrings: std.StringArrayHashMap(*objects.DoughString) = undefined;

/// Objects that should not be sweeped by the gc but have no other roots
pub var tmpObjects: std.ArrayList(*objects.DoughObject) = undefined;

pub fn init() !void {
    virtual_machine = core.vm.VirtualMachine{};
    compiler = core.compiler.ModuleCompiler.init(&virtual_machine);

    allocator = gpa.allocator();
    garbage_collector = memory.GarbageColletingAllocator.init(allocator, &compiler, &virtual_machine);

    try virtual_machine.init();

    internedStrings = std.StringArrayHashMap(*objects.DoughString).init(allocator);
    tmpObjects = std.ArrayList(*objects.DoughObject).init(allocator);
}

pub fn deinit() void {
    virtual_machine.deinit();

    internedStrings.deinit();
    tmpObjects.deinit();
    _ = gpa.deinit();
}

const std = @import("std");
const memory = @import("core/memory.zig");

const core = @import("core/core.zig");

const values = @import("values/values.zig");
const objects = values.objects;

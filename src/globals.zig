var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub var allocator: std.mem.Allocator = undefined;
pub var dough_allocator: memory.GarbageColletingAllocator = undefined;

pub var internedStrings: std.StringHashMap(*objects.DoughString) = undefined;

pub var tmpValues: std.ArrayList(values.Value) = undefined;

pub fn init() void {
    allocator = gpa.allocator();
    dough_allocator = memory.GarbageColletingAllocator.init(allocator);

    internedStrings = std.StringHashMap(*objects.DoughString).init(allocator);
    tmpValues = std.ArrayList(values.Value).init(allocator);
}

pub fn deinit() void {
    internedStrings.deinit();
    tmpValues.deinit();
}

const std = @import("std");
const memory = @import("core/memory.zig");

const values = @import("values/values.zig");
const objects = values.objects;

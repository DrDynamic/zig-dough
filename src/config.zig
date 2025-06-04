const std = @import("std");

// debugging flags
pub var debug_print_tokens: bool = false;
pub var debug_print_code: bool = false;

// allocators
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();
pub const dough_allocator = @import("core/memory.zig").GarbageColletingAllocator.init(allocator);

// infos for sanity checks
pub var max_file_size: usize = std.math.maxInt(usize);

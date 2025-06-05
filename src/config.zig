const std = @import("std");
const memory = @import("core/memory.zig");

// debugging flags
pub var debug_print_tokens: bool = false;
pub var debug_print_code: bool = false;

// allocators
pub var allocator: std.mem.Allocator = undefined;
pub var dough_allocator: memory.GarbageColletingAllocator = undefined;

// infos for sanity checks
pub var max_file_size: usize = std.math.maxInt(usize);

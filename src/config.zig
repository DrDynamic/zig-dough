const std = @import("std");
const memory = @import("core/memory.zig");

// debugging flags
pub var debug_print_tokens: bool = false;
pub var debug_print_code: bool = false;
pub var debug_trace_execution: bool = false;

// allocators
pub var allocator: std.mem.Allocator = undefined;
pub var dough_allocator: memory.GarbageColletingAllocator = undefined;

// sizes and infos for sanity checks
pub var MAX_FILE_SIZE: usize = std.math.maxInt(usize);

pub var MAX_STACK_SIZE: usize = std.math.maxInt(u8);

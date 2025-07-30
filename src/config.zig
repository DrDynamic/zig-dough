const std = @import("std");

// debugging flags
pub var debug_print_tokens: bool = false;
pub var debug_print_code: bool = false;
pub var debug_trace_execution: bool = false;

// sizes and infos for sanity checks
pub var MAX_FILE_SIZE: usize = std.math.maxInt(usize);

pub var MAX_STACK_SIZE: usize = std.math.maxInt(u8);

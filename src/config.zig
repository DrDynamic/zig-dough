const std = @import("std");

// debugging flags
pub var debug_print_tokens = false;
pub var debug_print_code = false;
pub var debug_trace_execution = false;

pub var debug_log_gc_alloc = false;
pub var debug_log_gc_mark = false;
pub var debug_log_gc_blacken = false;
pub var debug_log_gc_sweep = false;
pub var debug_log_gc_stats = false;

pub fn debug_log_gc_any() bool {
    return debug_log_gc_alloc or debug_log_gc_mark or debug_log_gc_blacken or debug_log_gc_sweep or debug_log_gc_stats;
}

pub var debug_stress_gc = true;

// sizes and infos for sanity checks
pub var MAX_FILE_SIZE: usize = std.math.maxInt(usize);

pub var MAX_STACK_SIZE: usize = std.math.maxInt(u8);

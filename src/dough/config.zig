const std = @import("std");
const dough = @import("dough");

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

//pub const IoConfig = struct {
//    compileErrorReporter: *const fn (token: *const dough.frontend.Token, message: []const u8, args: anytype) void = undefined,
//    runtimeErrorReporter: *const fn (format: []const u8, args: anytype, frames: []dough.backend.CallFrame, frameCount: usize) void = undefined,
//    print: *const fn (format: []const u8, args: anytype) void = undefined,
//};
pub var io_config = .{
    .compileErrorReporter = @import("./util/util.zig").errorReporter.compileError,
    .runtimeErrorReporter = @import("./util/util.zig").errorReporter.runtimeError,
    .print = @import("./util/util.zig").console.print,
};

// sizes and infos for sanity checks
pub var MAX_FILE_SIZE: usize = std.math.maxInt(usize);

pub var MAX_STACK_SIZE: usize = std.math.maxInt(u8);

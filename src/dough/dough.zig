pub var allocator: std.mem.Allocator = undefined;

pub var garbage_collector: memory.GarbageColletingAllocator = undefined;

pub var compiler: ModuleCompiler = undefined;
pub var virtual_machine: VirtualMachine = undefined;

pub var internedStrings: std.StringArrayHashMap(*objects.DoughString) = undefined;

/// Objects that should not be sweeped by the gc but have no other roots
pub var tmpObjects: std.ArrayList(*objects.DoughObject) = undefined;

pub const DoughOptions = struct {
    compileErrorReporter: *const fn (token: *const frontend.Token, message: []const u8, args: anytype) void,
    runtimeErrorReporter: *const fn (format: []const u8, args: anytype, frames: []backend.CallFrame, frameCount: usize) void,
    print: *const fn (format: []const u8, args: anytype) void,
};

pub fn init(allocator_: std.mem.Allocator) !void {
    allocator = allocator_;

    virtual_machine = VirtualMachine{};
    compiler = ModuleCompiler.init(&virtual_machine);

    garbage_collector = memory.GarbageColletingAllocator.init(allocator, &compiler, &virtual_machine);

    try virtual_machine.init();

    internedStrings = std.StringArrayHashMap(*objects.DoughString).init(allocator);
    tmpObjects = std.ArrayList(*objects.DoughObject).init(allocator);
}

pub fn deinit() void {
    virtual_machine.deinit();

    internedStrings.deinit();
    tmpObjects.deinit();
}

const std = @import("std");

pub const types = @import("./types.zig");
pub const config = @import("./config.zig");

const memory = @import("./memory.zig");

pub const frontend = @import("./frontend/frontend.zig");
pub const backend = @import("./backend/backend.zig");
pub const values = @import("./values/values.zig");

//m const vm = @import("./backend/vm.zig");
//m pub const InterpretError = vm.InterpretError;
const VirtualMachine = backend.VirtualMachine;
//m pub const OpCode = @import("./backend/opcodes.zig").OpCode;

// const cmp = @import("./frontend/compiler.zig");
const ModuleCompiler = frontend.ModuleCompiler;
// pub const FunctionCompiler = cmp.FunctionCompiler;

const objects = values.objects;

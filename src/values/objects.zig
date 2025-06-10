const std = @import("std");

const config = @import("../config.zig");

const core = @import("../core/core.zig");
const Chunk = core.chunk.Chunk;
const VirtualMachine = core.vm.VirtualMachine;
const InterpretError = core.vm.InterpretError;

const slot_stack = @import("./slot_stack.zig");
const SlotStack = slot_stack.SlotStack;

const Value = @import("values.zig").Value;

pub const ObjType = enum {
    Module,
    Closure,
    Function,
};

pub const DoughObject = struct {
    obj_type: ObjType,
    is_marked: bool,

    pub fn init(comptime T: type, obj_type: ObjType) !*DoughObject {
        const ptr = try config.dough_allocator.allocator().create(T);
        ptr.obj = DoughObject{
            .obj_type = obj_type,
            .is_marked = false,
        };

        return &ptr.obj;
    }

    pub fn deinit(self: *DoughObject) void {
        switch (self.obj_type) {
            .Module => self.as(DoughModule).deinit(),
            .Closure => self.as(DoughClosure).deinit(),
            .Function => self.as(DoughFunction).deinit(),
        }
    }

    pub fn print(self: *DoughObject) void {
        switch (self.obj_type) {
            .Module => self.as(DoughModule).print(),
            .Closure => self.as(DoughClosure).print(),
            .Function => self.as(DoughFunction).print(),
        }
    }

    pub inline fn is(self: *DoughObject, obj_type: ObjType) bool {
        return self.obj_type == obj_type;
    }

    pub inline fn as(self: *DoughObject, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

    pub inline fn asFunction(self: *DoughObject) *DoughFunction {
        return @fieldParentPtr("obj", self);
    }
};

pub const DoughExecutable = struct {
    pub const CallFrame = struct {
        closure: *DoughClosure = undefined,
        ip: [*]u8 = undefined,
        slots: [*]Value = undefined,
    };

    obj: DoughObject,

    frames: []CallFrame = undefined,
    frame_count: usize = undefined,
    frame_capacity: usize = undefined,

    stack: []Value = undefined,
    stack_top: [*]Value = undefined,
    stack_capacity: usize = undefined,

    function: ?*DoughFunction = null,

    pub fn init(comptime T: type, obj_type: ObjType) !*DoughExecutable {
        const obj = try DoughObject.init(T, obj_type);
        const executable = obj.as(DoughExecutable);
        executable.* = .{};
        return executable;
    }

    pub fn initStack(self: *DoughExecutable) void {
        // TODO: recalc sizes in compiler if possible
        // TODO: grow / shrink frames and stack
        self.frames = config.allocator([64]CallFrame);
        self.frame_count = 0;
        self.frame_capacity = 64;

        self.stack = config.allocator([64]Value);
        self.stack_capacity = 64;
        self.resetStack();
    }

    fn call(self: *VirtualMachine, closure: *DoughClosure, arg_count: u8) core.vm.InterpretError!void {
        if (arg_count < closure.function.arity) {
            self.runtime_error("Expected {d} arguments but got {d}", .{ closure.function.arity, arg_count });
            return InterpretError.RuntimeError;
        }
    }

    pub fn push(self: *VirtualMachine, value: Value) void {
        self.stack_top[0] = value;
        self.stack_top += 1;
    }

    pub fn pop(self: *VirtualMachine) Value {
        self.stack_top -= 1;
        return self.stack_top[0];
    }

    pub fn resetStack(self: *DoughExecutable) void {
        self.stack_top = self.stack[0..];
    }
};

pub const DoughModule = struct {
    obj: DoughObject,

    pub fn init() !*DoughModule {
        const obj = try DoughExecutable.init(DoughModule, ObjType.Module);
        const module = obj.as(DoughModule);
        module.* = .{
            .obj = obj.*,
        };
        return module;
    }

    pub fn deinit(self: DoughModule) void {
        config.dough_allocator.allocator().destroy(self);
    }

    pub fn asObject(self: *DoughModule) *DoughObject {
        return @ptrCast(self);
    }

    pub fn print(_: *DoughModule) void {
        std.debug.print("<DoughModule>");
    }
};

pub const DoughClosure = struct {
    obj: DoughObject,
    function: *DoughFunction,

    pub fn init(function: *DoughFunction) !*DoughClosure {
        const obj = try DoughObject.init(DoughClosure, ObjType.Closure);
        const closure = obj.as(DoughClosure);
        closure.* = .{
            .obj = obj,
            .function = function,
        };
        return closure;
    }

    pub fn deinit(self: *DoughClosure) void {
        config.dough_allocator.allocator().destroy(self);
    }

    pub fn asObject(self: *DoughClosure) *DoughObject {
        return @ptrCast(self);
    }

    pub fn print(self: *DoughClosure) void {
        self.function.print();
    }
};

pub const DoughFunction = struct {
    obj: DoughObject,
    arity: u8,
    chunk: Chunk,
    slots: SlotStack,

    pub fn init() !*DoughFunction {
        const obj = try DoughObject.init(DoughFunction, .Function);
        const function = obj.as(DoughFunction);
        function.* = .{
            .obj = obj.*,
            .arity = 0,
            .chunk = Chunk.init(config.allocator),
            .slots = SlotStack.init(),
        };
        return function;
    }

    pub fn deinit(self: DoughFunction) void {
        self.chunk.deinit();
        self.slots.deinit();
        config.dough_allocator.allocator().destroy(self);
    }

    pub fn asObject(self: *DoughFunction) *DoughObject {
        return @ptrCast(self);
    }

    pub fn print(_: *DoughFunction) void {
        std.debug.print("<DoughFunction>");
    }
};

pub const DoughString = struct {
    obj: DoughObject,
    chars: []const u8,
};

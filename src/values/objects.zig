const std = @import("std");

const config = @import("../config.zig");

const core = @import("../core/core.zig");
const Chunk = core.chunk.Chunk;
const VirtualMachine = core.vm.VirtualMachine;

const slot_stack = @import("./slot_stack.zig");
const SlotStack = slot_stack.SlotStack;

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

pub const DoughModule = struct {
    obj: DoughObject,
    function: ?*DoughFunction = null,

    pub fn init() !*DoughModule {
        const obj = try DoughObject.init(DoughModule, ObjType.Module);
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

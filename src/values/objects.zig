const std = @import("std");

const core = @import("../core/core.zig");
const Chunk = core.chunk.Chunk;
const VirtualMachine = core.vm.VirtualMachine;

pub const ObjType = enum {
    Module,
    Function,
};

pub const DoughObject = struct {
    obj_type: ObjType,
    is_marked: bool,

    pub fn init(vm: *VirtualMachine, comptime T: type, obj_type: ObjType) !*DoughObject {
        const ptr = try vm.dough_allocator.allocator().create(T);
        ptr.obj = DoughObject{
            .obj_type = obj_type,
            .is_marked = false,
        };

        return &ptr.obj;
    }

    pub fn deinit(self: *DoughObject, vm: *VirtualMachine) void {
        switch (self.obj_type) {
            .Module => self.as(DoughModule).deinit(vm),
            .Function => self.as(DoughFunction).deinit(vm),
        }
    }

    pub fn print(self: *DoughObject) void {
        switch (self.obj_type) {
            .Module => self.as(DoughModule).print(),
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
};

pub const DoughFunction = struct {
    obj: DoughObject,
    chunk: Chunk,

    pub fn init(vm: *VirtualMachine) !*DoughFunction {
        const obj = try DoughObject.init(vm, DoughFunction, .Function);
        const function = obj.as(DoughFunction);
        function.* = .{
            .obj = obj.*,
            .chunk = Chunk.init(vm.allocator),
        };
        return function;
    }

    pub fn deinit(self: DoughFunction, vm: *VirtualMachine) void {
        self.chunk.deinit();
        vm.doughAllocator.allocator().destroy(self);
    }

    pub fn asObject(self: *DoughFunction) DoughObject {
        return @ptrCast(self);
    }

    pub fn print(_: *DoughFunction) void {
        std.debug.print("<DoughFunction>");
    }
};

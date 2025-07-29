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
    Closure,
    Function,
    Module,
    NativeFunction,
    String,
};

pub const NativeFn = fn (usize, []Value) Value;
pub const DoughNativeFunction = struct {
    obj: DoughObject,
    name: []const u8,
    function: *const NativeFn,

    pub fn init(name: []const u8, function: NativeFn) !*DoughNativeFunction {
        const obj = try DoughObject.init(DoughNativeFunction, ObjType.NativeFunction);
        const native = obj.as(DoughNativeFunction);
        native.* = .{
            .obj = obj.*,
            .name = name,
            .function = function,
        };
        return native;
    }

    pub fn deinit(self: *DoughNativeFunction) void {
        config.dough_allocator.allocator().destroy(self);
    }

    pub inline fn asObject(self: *DoughNativeFunction) *DoughObject {
        return &self.obj;
    }

    pub fn print(_: *DoughNativeFunction) void {
        std.debug.print("<native fn>", .{});
    }
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
            .NativeFunction => self.as(DoughNativeFunction).deinit(),
            .Closure => self.as(DoughClosure).deinit(),
            .Function => self.as(DoughFunction).deinit(),
            .String => self.as(DoughString).deinit(),
        }
    }

    pub fn print(self: *DoughObject) void {
        switch (self.obj_type) {
            .Module => self.as(DoughModule).print(),
            .NativeFunction => self.as(DoughNativeFunction).print(),
            .Closure => self.as(DoughClosure).print(),
            .Function => self.as(DoughFunction).print(),
            .String => self.as(DoughString).print(),
        }
    }

    pub inline fn is(self: *DoughObject, obj_type: ObjType) bool {
        return self.obj_type == obj_type;
    }

    pub inline fn as(self: *DoughObject, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }
};

pub const DoughModule = struct {
    obj: DoughObject,
    function: *DoughFunction = undefined,

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
        std.debug.print("<DoughModule>", .{});
    }
};

pub const DoughClosure = struct {
    obj: DoughObject,
    function: *DoughFunction,

    pub fn init(function: *DoughFunction) !*DoughClosure {
        const obj = try DoughObject.init(DoughClosure, ObjType.Closure);
        const closure = obj.as(DoughClosure);
        closure.* = .{
            .obj = obj.*,
            .function = function,
        };
        return closure;
    }

    pub fn deinit(self: *DoughClosure) void {
        config.dough_allocator.allocator().destroy(self);
    }

    pub fn asObject(self: *DoughClosure) *DoughObject {
        return &self.obj;
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
    name: ?[]const u8 = null,

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

    pub inline fn asObject(self: *DoughFunction) *DoughObject {
        return &self.obj;
    }

    pub fn print(_: *DoughFunction) void {
        //        std.debug.print("<fn {s}>", .{self.name orelse "anonymous"});
        std.debug.print("<fn>", .{});
    }
};

pub const DoughString = struct {
    obj: DoughObject,
    bytes: []const u8,

    pub fn init(bytes: []const u8, vm: *VirtualMachine) !*DoughString {
        if (vm.strings.get(bytes)) |interned| {
            config.allocator.free(bytes);
            return interned;
        } else {
            const obj = try DoughObject.init(DoughString, .String);
            const string = obj.as(DoughString);

            string.* = .{
                .obj = obj.*,
                .bytes = bytes,
            };

            vm.push(Value.fromObject(string.asObject()));
            try vm.strings.put(bytes, string);
            _ = vm.pop();

            return string;
        }
    }

    pub fn copy(bytes: []const u8, vm: *VirtualMachine) !*DoughString {
        const buffer = try config.allocator.alloc(u8, bytes.len);
        @memcpy(buffer, bytes);
        return DoughString.init(buffer, vm);
    }

    pub fn deinit(self: *DoughString) void {
        config.allocator.free(self.bytes);
        config.allocator.destroy(self);
    }

    pub inline fn asObject(self: *DoughString) *DoughObject {
        return &self.obj;
    }

    pub fn print(self: *DoughString) void {
        std.debug.print("{s}", .{self.bytes});
    }
};

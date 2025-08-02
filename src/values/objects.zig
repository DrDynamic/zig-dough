const std = @import("std");

const globals = @import("../globals.zig");
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

    pub fn toString(self: DoughNativeFunction) *DoughString {
        const bytes = std.fmt.allocPrint(globals.allocator, "<native fn '{s}'>", .{self.name}) catch @panic("failed to create string!");
        return DoughString.init(bytes);
    }
};

pub const DoughObject = struct {
    obj_type: ObjType,
    is_marked: bool,

    pub fn init(comptime T: type, obj_type: ObjType) !*DoughObject {
        const ptr = try globals.dough_allocator.allocator().create(T);
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

    pub fn toString(self: *DoughObject) *DoughString {
        return switch (self.obj_type) {
            .Module => self.as(DoughModule).toString(),
            .NativeFunction => self.as(DoughNativeFunction).toString(),
            .Closure => self.as(DoughClosure).toString(),
            .Function => self.as(DoughFunction).toString(),
            .String => self.as(DoughString),
        };
    }

    pub fn equals(self: *DoughObject, other: Value) bool {
        return switch (self.obj_type) {
            .Module, .NativeFunction, .Closure, .Function => self == other.toObject(),
            .String => self.as(DoughString).equals(other),
        };
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

    pub fn init() *DoughModule {
        const obj = DoughObject.init(DoughModule, ObjType.Module) catch {
            @panic("failed to create DoughModule!");
        };
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

    pub fn toString(_: *DoughModule) *DoughString {
        return DoughString.init("<DoughModule>");
    }
};

pub const DoughClosure = struct {
    obj: DoughObject,
    function: *DoughFunction,

    pub fn init(function: *DoughFunction) *DoughClosure {
        const obj = DoughObject.init(DoughClosure, ObjType.Closure) catch {
            @panic("failed to create DoughClosure");
        };
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

    pub fn toString(self: *DoughClosure) *DoughString {
        return self.function.toString();
    }
};

pub const DoughFunction = struct {
    obj: DoughObject,
    arity: u8,
    chunk: Chunk,
    slots: SlotStack,
    name: ?[]const u8 = null,

    pub fn init() *DoughFunction {
        const obj = DoughObject.init(DoughFunction, .Function) catch {
            @panic("failed to create DoughFunction");
        };
        const function = obj.as(DoughFunction);
        function.* = .{
            .obj = obj.*,
            .arity = 0,
            .chunk = Chunk.init(globals.allocator),
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

    pub fn toString(self: *DoughFunction) *DoughString {
        const name = self.name orelse "anonymous";
        const bytes = std.fmt.allocPrint(globals.allocator, "<fn '{s}'>", .{name}) catch @panic("failed to create string!");

        return DoughString.init(bytes);
    }
};

pub const DoughString = struct {
    obj: DoughObject,
    bytes: []const u8,

    pub fn init(bytes: []const u8) *DoughString {
        if (globals.internedStrings.get(bytes)) |interned| {
            globals.allocator.free(bytes);
            return interned;
        } else {
            const obj = DoughObject.init(DoughString, .String) catch {
                @panic("failed to create DoughString!");
            };
            const string = obj.as(DoughString);

            string.* = .{
                .obj = obj.*,
                .bytes = bytes,
            };

            globals.tmpValues.append(Value.fromObject(string.asObject())) catch {
                @panic("failed to create DoughString!");
            };

            globals.internedStrings.put(bytes, string) catch {
                @panic("failed to create DoughString!");
            };

            _ = globals.tmpValues.pop();

            return string;
        }
    }

    pub fn copy(bytes: []const u8) *DoughString {
        const buffer = globals.allocator.alloc(u8, bytes.len) catch {
            @panic("failed to create DoughString!");
        };
        @memcpy(buffer, bytes);
        return DoughString.init(buffer);
    }

    pub fn deinit(self: *DoughString) void {
        globals.allocator.free(self.bytes);
        globals.allocator.destroy(self);
    }

    pub inline fn asObject(self: *DoughString) *DoughObject {
        return &self.obj;
    }

    pub fn print(self: *DoughString) void {
        std.debug.print("{s}", .{self.bytes});
    }

    pub fn toString(self: *DoughString) *DoughString {
        return self;
    }

    pub fn equals(self: *DoughString, other: Value) bool {
        if (!other.isString()) {
            return false;
        }

        return std.mem.eql(u8, self.bytes, other.toObject().as(DoughString).bytes);
    }
};

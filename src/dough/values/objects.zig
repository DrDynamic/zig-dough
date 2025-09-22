const std = @import("std");

const dough = @import("dough");
const config = dough.config;

const Chunk = dough.values.Chunk;
const VirtualMachine = dough.backend.VirtualMachine;
const InterpretError = dough.backend.InterpretError;

const Value = @import("values.zig").Value;

pub const ObjType = enum {
    Closure,
    Function,
    Module,
    NativeFunction,
    String,

    ErrorSet,
    Error,
};

pub const NativeFn = fn (usize, []Value) Value;
pub const DoughNativeFunction = struct {
    obj: DoughObject,
    name: []const u8,
    function: *const NativeFn,

    pub fn init(name: []const u8, function: NativeFn) *DoughNativeFunction {
        const obj = DoughObject.init(DoughNativeFunction, ObjType.NativeFunction);
        const native = obj.as(DoughNativeFunction);
        native.* = .{
            .obj = obj.*,
            .name = name,
            .function = function,
        };
        return native;
    }

    pub fn deinit(self: *DoughNativeFunction) void {
        dough.garbage_collector.allocator().destroy(self);
    }

    pub inline fn asObject(self: *DoughNativeFunction) *DoughObject {
        return &self.obj;
    }

    pub fn print(_: *DoughNativeFunction) void {
        std.debug.print("<native fn>", .{});
    }

    pub fn format(self: DoughNativeFunction, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
        _ = fmt;
        _ = options;

        try out_stream.print("<native fn '{s}'>", .{self.name});
    }

    pub fn toString(self: DoughNativeFunction) *DoughString {
        const bytes = std.fmt.allocPrint(dough.allocator, "<native fn '{s}'>", .{self.name}) catch @panic("failed to create string!");
        return DoughString.init(bytes);
    }
};

pub const DoughObject = struct {
    obj_type: ObjType,

    next: ?*DoughObject,
    nextGray: ?*DoughObject,
    is_marked: bool,

    pub fn init(comptime T: type, obj_type: ObjType) *DoughObject {
        const ptr = dough.garbage_collector.allocator().create(T) catch {
            @panic("failed create Object");
        };

        ptr.obj = DoughObject{
            .obj_type = obj_type,

            .next = dough.garbage_collector.doughObjects,
            .nextGray = null,
            .is_marked = false,
        };

        dough.garbage_collector.doughObjects = &ptr.obj;

        if (config.debug_log_gc_alloc) {
            std.debug.print("   [init] {*} ({s}) {d} bytes\n", .{
                &ptr.obj,
                @tagName(obj_type),
                @sizeOf(T),
            });
        }

        return &ptr.obj;
    }

    pub fn deinit(self: *DoughObject) void {
        switch (self.obj_type) {
            .Closure => self.as(DoughClosure).deinit(),
            .ErrorSet => self.as(DoughErrorSet).deinit(),
            .Error => self.as(DoughError).deinit(),
            .Function => self.as(DoughFunction).deinit(),
            .Module => self.as(DoughModule).deinit(),
            .NativeFunction => self.as(DoughNativeFunction).deinit(),
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

    pub fn format(self: *DoughObject, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
        switch (self.obj_type) {
            .Closure => try self.as(DoughClosure).format(fmt, options, out_stream),
            .ErrorSet => try self.as(DoughErrorSet).format(fmt, options, out_stream),
            .Error => try self.as(DoughError).format(fmt, options, out_stream),
            .Function => try self.as(DoughFunction).format(fmt, options, out_stream),
            .Module => try self.as(DoughModule).format(fmt, options, out_stream),
            .NativeFunction => try self.as(DoughNativeFunction).format(fmt, options, out_stream),
            .String => try self.as(DoughString).format(fmt, options, out_stream),
        }
    }

    pub fn toString(self: *DoughObject) *DoughString {
        return switch (self.obj_type) {
            .Closure => self.as(DoughClosure).toString(),
            .ErrorSet => self.as(DoughErrorSet).toString(),
            .Error => self.as(DoughError).toString(),
            .Function => self.as(DoughFunction).toString(),
            .Module => self.as(DoughModule).toString(),
            .NativeFunction => self.as(DoughNativeFunction).toString(),
            .String => self.as(DoughString),
        };
    }

    pub fn equals(self: *DoughObject, other: Value) bool {
        return switch (self.obj_type) {
            .Closure,
            .Function,
            .ErrorSet,
            .Error,
            .Module,
            .NativeFunction,
            => self == other.toObject(),
            .String => self.as(DoughString).equals(other),
        };
    }

    pub inline fn is(self: *DoughObject, obj_type: ObjType) bool {
        return self.obj_type == obj_type;
    }

    pub inline fn as(self: *DoughObject, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

    pub inline fn asValue(self: *DoughObject) Value {
        return Value.fromObject(self);
    }
};

pub const DoughModule = struct {
    obj: DoughObject,
    function: *DoughFunction,

    pub fn init(function: *DoughFunction) *DoughModule {
        const obj = DoughObject.init(DoughModule, ObjType.Module);
        const module = obj.as(DoughModule);
        module.* = .{
            .obj = obj.*,
            .function = function,
        };
        return module;
    }

    pub fn deinit(self: *DoughModule) void {
        dough.garbage_collector.allocator().destroy(self);
    }

    pub fn asObject(self: *DoughModule) *DoughObject {
        return @ptrCast(self);
    }

    pub fn print(_: *DoughModule) void {
        std.debug.print("<DoughModule>", .{});
    }

    pub fn format(_: DoughModule, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
        _ = fmt;
        _ = options;

        try out_stream.print("<DoughModule>", .{});
    }

    pub fn toString(_: *DoughModule) *DoughString {
        return DoughString.init("<DoughModule>");
    }
};

pub const DoughClosure = struct {
    obj: DoughObject,
    function: *DoughFunction,

    pub fn init(function: *DoughFunction) *DoughClosure {
        const obj = DoughObject.init(DoughClosure, ObjType.Closure);
        const closure = obj.as(DoughClosure);
        closure.* = .{
            .obj = obj.*,
            .function = function,
        };
        return closure;
    }

    pub fn deinit(self: *DoughClosure) void {
        dough.garbage_collector.allocator().destroy(self);
    }

    pub fn asObject(self: *DoughClosure) *DoughObject {
        return &self.obj;
    }

    pub fn print(self: *DoughClosure) void {
        self.function.print();
    }

    pub fn format(self: DoughClosure, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
        try self.function.format(fmt, options, out_stream);
    }

    pub fn toString(self: *DoughClosure) *DoughString {
        return self.function.toString();
    }
};

pub const DoughFunction = struct {
    obj: DoughObject,
    arity: u8,
    chunk: Chunk,
    name: ?[]const u8 = null,

    pub fn init() *DoughFunction {
        const obj = DoughObject.init(DoughFunction, .Function);
        const function = obj.as(DoughFunction);
        function.* = .{
            .obj = obj.*,
            .arity = 0,
            .chunk = Chunk.init(dough.allocator),
        };
        return function;
    }

    pub fn deinit(self: *DoughFunction) void {
        self.chunk.deinit();
        dough.garbage_collector.allocator().destroy(self);
    }

    pub inline fn asObject(self: *DoughFunction) *DoughObject {
        return &self.obj;
    }

    pub fn print(_: *DoughFunction) void {
        //        std.debug.print("<fn {s}>", .{self.name orelse "anonymous"});
        std.debug.print("<fn>", .{});
    }

    pub fn format(self: DoughFunction, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
        _ = fmt;
        _ = options;

        const name = self.name orelse "anonymous";
        try out_stream.print("<fn '{s}'>", .{name});
    }

    pub fn toString(self: *DoughFunction) *DoughString {
        const name = self.name orelse "anonymous";
        const bytes = std.fmt.allocPrint(dough.allocator, "<fn '{s}'>", .{name}) catch @panic("failed to create string!");

        return DoughString.init(bytes);
    }
};

pub const DoughString = struct {
    obj: DoughObject,
    bytes: []const u8,

    pub fn init(bytes: []const u8) *DoughString {
        if (dough.internedStrings.get(bytes)) |interned| {
            dough.allocator.free(bytes);
            return interned;
        } else {
            const obj = DoughObject.init(DoughString, .String);
            const string = obj.as(DoughString);

            string.* = .{
                .obj = obj.*,
                .bytes = bytes,
            };

            dough.tmpObjects.append(string.asObject()) catch {
                @panic("failed to create DoughString!");
            };

            dough.internedStrings.put(bytes, string) catch {
                @panic("failed to create DoughString!");
            };

            _ = dough.tmpObjects.pop();

            return string;
        }
    }

    pub fn copy(bytes: []const u8) *DoughString {
        const buffer = dough.allocator.alloc(u8, bytes.len) catch {
            @panic("failed to create DoughString!");
        };
        @memcpy(buffer, bytes);
        return DoughString.init(buffer);
    }

    pub fn deinit(self: *DoughString) void {
        dough.allocator.free(self.bytes);
        dough.garbage_collector.allocator().destroy(self);
    }

    pub inline fn asObject(self: *DoughString) *DoughObject {
        return &self.obj;
    }

    pub fn print(self: *DoughString) void {
        std.debug.print("{s}", .{self.bytes});
    }

    pub fn format(self: DoughString, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
        _ = fmt;
        _ = options;

        try out_stream.print("{s}", .{self.bytes});
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

pub const DoughError = struct {
    obj: DoughObject,
    name: []const u8,
    error_set: *DoughErrorSet,

    pub fn init(name: []const u8, error_set: *DoughErrorSet) *DoughError {
        const obj = DoughObject.init(DoughError, .Error);

        const buffer = dough.allocator.alloc(u8, name.len) catch {
            @panic("failed to create ErrorList");
        };
        @memcpy(buffer, name);

        const error_list_item = obj.as(DoughError);
        error_list_item.* = .{
            .obj = obj.*,
            .name = buffer,
            .error_set = error_set,
        };
        return error_list_item;
    }

    pub fn deinit(self: *DoughError) void {
        dough.allocator.free(self.name);
        dough.garbage_collector.allocator().destroy(self);
    }

    pub inline fn asObject(self: *DoughError) *DoughObject {
        return &self.obj;
    }

    pub fn print(self: *DoughError) void {
        std.debug.print("{}", .{self});
    }

    pub fn format(self: DoughError, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
        _ = fmt;
        _ = options;

        try out_stream.print("{s}", .{self.name});
    }

    pub fn toString(self: *DoughError) *DoughString {
        const bytes = std.fmt.allocPrint(dough.allocator, "{}", .{self}) catch @panic("failed to create string!");
        return DoughString.init(bytes);
    }

    pub inline fn toType(self: *DoughError) dough.values.Type {
        return dough.values.Type.makeTypeObject(self.asObject());
    }

    pub fn equals(self: *DoughError, other: Value) bool {
        if (!other.isObject()) {
            return false;
        }

        if (!other.toObject().is(.ErrorListItem)) {
            return false;
        }

        return self == other.toObject().as(DoughError);
    }
};

pub const DoughErrorSet = struct {
    obj: DoughObject,
    name: []const u8,
    // items: []*DoughError,
    items: std.StringHashMap(*DoughError),

    pub fn init(name: []const u8) *DoughErrorSet {
        const obj = DoughObject.init(DoughErrorSet, .ErrorSet);

        const name_buffer = dough.allocator.alloc(u8, name.len) catch {
            @panic("failed to create ErrorList");
        };
        @memcpy(name_buffer, name);

        const error_list = obj.as(DoughErrorSet);
        error_list.* = .{
            .obj = obj.*,
            .name = name_buffer,
            .items = std.StringHashMap(*DoughError).init(dough.allocator),
        };

        return error_list;
    }

    pub fn setItems(self: *DoughErrorSet, items: []*DoughError) void {
        for (items) |dough_error| {
            self.items.put(dough_error.name, dough_error) catch {
                @panic("allocation failed!");
            };
        }
    }

    pub fn getError(self: *DoughErrorSet, name: []const u8) ?*DoughError {
        return self.items.get(name);
    }

    pub fn deinit(self: *DoughErrorSet) void {
        dough.allocator.free(self.name);
        self.items.deinit();

        dough.garbage_collector.allocator().destroy(self);
    }

    pub inline fn asObject(self: *DoughErrorSet) *DoughObject {
        return &self.obj;
    }

    pub inline fn toType(self: *DoughErrorSet) dough.values.Type {
        return dough.values.Type.makeTypeObject(self.asObject());
    }

    pub fn print(self: *DoughErrorSet) void {
        std.debug.print("{}", .{self});
    }

    pub fn format(self: DoughErrorSet, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: anytype) !void {
        _ = fmt;
        _ = options;

        try out_stream.print("{s}", .{self.name});
    }

    pub fn toString(self: *DoughErrorSet) *DoughString {
        return DoughString.copy(self.name);
    }

    pub fn equals(self: *DoughErrorSet, other: Value) bool {
        if (!other.isObject()) {
            return false;
        }

        if (!other.toObject().is(.ErrorList)) {
            return false;
        }

        return self == other.toObject().as(DoughErrorSet);
    }
};

pub const ObjectType = enum(u8) {
    upvalue,
    closure,
    function,
    native_function,
    module,
    string,
};

pub const ObjectHeader = struct {
    tag: ObjectType,
    is_marked: bool,
    next: ?*ObjectHeader,
    next_gray: ?*ObjectHeader,

    pub inline fn equals(self: *ObjectHeader, other: Value) bool {
        if (!other.isObject()) return false;

        return self == other.toObject();
    }

    pub inline fn is(self: *const ObjectHeader, tag: ObjectType) bool {
        return self.tag == tag;
    }

    pub inline fn as(self: *ObjectHeader, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("header", self));
    }

    pub fn deinit(self: *ObjectHeader, allocator: std.mem.Allocator) void {
        switch (self.tag) {
            .closure => self.as(ObjClosure).deinit(allocator),
            .function => self.as(ObjFunction).deinit(allocator),
            .module => self.as(ObjModule).deinit(allocator),
            .native_function => self.as(ObjNative).deinit(allocator),
            .string => self.as(ObjString).deinit(allocator),
            .upvalue => self.as(ObjUpValue).deinit(allocator),
        }
    }

    pub fn format(
        self: *ObjectHeader,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        switch (self.tag) {
            .string => try std.fmt.formatText(self.as(ObjString).data, "s", options, writer),
            .closure => {
                const closure = self.as(ObjClosure);
                const name = if (closure.function.name) |name| name.data else "anonymous";

                try writer.print("<closure {s}", .{name});
                try std.fmt.formatText(
                    ">",
                    "s",
                    .{
                        .precision = null,
                        .width = if (options.width) |width| width - name.len - 9 else null,
                        .alignment = options.alignment,
                        .fill = options.fill,
                    },
                    writer,
                );
            },
            .function => {
                const function = self.as(ObjFunction);
                const name = if (function.name) |name| name.data else "anonymous";

                try writer.print("<function {s}", .{name});
                try std.fmt.formatText(
                    ">",
                    "s",
                    .{
                        .precision = null,
                        .width = if (options.width) |width| width - name.len - 10 else null,
                        .alignment = options.alignment,
                        .fill = options.fill,
                    },
                    writer,
                );
            },
            else => {
                const name = @tagName(self.tag);
                try writer.print("<object {s}", .{name});
                try std.fmt.formatText(
                    ">",
                    "s",
                    .{
                        .precision = null,
                        .width = if (options.width) |width| width - name.len - 8 else null,
                        .alignment = options.alignment,
                        .fill = options.fill,
                    },
                    writer,
                );
            },
        }
    }
};

pub const ObjModule = struct {
    header: ObjectHeader,
    function: *ObjFunction,

    pub fn init(function: *ObjFunction, garbage_collector: *GarbageCollector) *ObjModule {
        var module = garbage_collector.createObject(ObjModule, .module);
        module.function = function;

        return module;
    }

    pub fn deinit(self: *ObjModule, allocator: std.mem.Allocator) void {
        self.function.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn asObject(self: *ObjModule) *ObjectHeader {
        return &self.header;
    }
};

pub const ObjFunction = struct {
    pub const UpValueLocation = struct { index: u8, is_local: bool };

    header: ObjectHeader,
    arity: u8,
    upvalue_locations: []UpValueLocation,
    max_registers: u8,
    chunk: Chunk,
    name: ?*ObjString,

    pub fn init(garbage_collector: *GarbageCollector) *ObjFunction {
        var function = garbage_collector.createObject(ObjFunction, .function);
        function.arity = 0;
        function.max_registers = 0;
        function.chunk = Chunk.init(garbage_collector.allocator());
        function.name = null;

        return function;
    }

    pub fn deinit(self: *ObjFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.upvalue_locations);
        self.chunk.deinit();
        if (self.name != null) {
            self.name.?.deinit(allocator);
        }
        allocator.destroy(self);
    }

    pub fn asObject(self: *ObjFunction) *ObjectHeader {
        return &self.header;
    }
};

pub const ObjClosure = struct {
    header: ObjectHeader,
    upvalues: []?*ObjUpValue,
    function: *ObjFunction,

    pub fn init(garbage_collector: *GarbageCollector, function: *ObjFunction) *ObjClosure {
        const closure = garbage_collector.createObject(ObjClosure, .closure);
        closure.function = function;
        closure.upvalues = &[_]?*ObjUpValue{};

        garbage_collector.temp_objects.append(closure.asObject()) catch @panic("Failed to create Object");
        closure.upvalues = garbage_collector.allocator().alloc(?*ObjUpValue, function.upvalue_locations.len) catch @panic("Failed to create Object");
        _ = garbage_collector.temp_objects.pop();

        for (closure.upvalues) |*upvalue| {
            upvalue.* = null;
        }

        return closure;
    }

    pub fn deinit(self: *ObjClosure, allocator: std.mem.Allocator) void {
        allocator.free(self.upvalues);
        allocator.destroy(self);
    }

    pub fn asObject(self: *ObjClosure) *ObjectHeader {
        return &self.header;
    }
};

pub const ObjUpValue = struct {
    header: ObjectHeader,
    next_open: ?*ObjUpValue,
    location: *Value,
    closed: Value,

    pub fn init(garbage_collector: *GarbageCollector, location: *Value) *ObjUpValue {
        var upvalue = garbage_collector.createObject(ObjUpValue, .upvalue);
        upvalue.location = location;
        upvalue.closed = Value.makeUninitialized();

        return upvalue;
    }

    pub fn deinit(self: *ObjUpValue, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    pub fn asObject(self: *ObjUpValue) *ObjectHeader {
        return &self.header;
    }
};

pub const ObjString = struct {
    header: ObjectHeader,
    data: []const u8,

    pub fn init(data: []const u8, memory_manager: *GarbageCollector) *ObjString {
        if (getInterned(data, memory_manager)) |interned| {
            memory_manager.allocator().free(data);
            return interned;
        }

        var string = memory_manager.createObject(ObjString, .string);
        string.data = data;

        memory_manager.interned_strings.put(data, string) catch {
            @panic("failed to create string (OutOfMemory)");
        };

        return string;
    }

    pub fn copydata(data: []const u8, memory_manager: *GarbageCollector) *ObjString {
        if (getInterned(data, memory_manager)) |interned| return interned;

        const buffer = memory_manager.allocator().alloc(u8, data.len) catch {
            // TODO runtime error?
            @panic("Failed to create String");
        };
        @memcpy(buffer, data);
        return ObjString.init(buffer, memory_manager);
    }

    pub fn deinit(self: *ObjString, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        allocator.destroy(self);
    }

    pub fn asObject(self: *ObjString) *ObjectHeader {
        return &self.header;
    }

    inline fn getInterned(data: []const u8, memory_manager: *GarbageCollector) ?*ObjString {
        return memory_manager.interned_strings.get(data);
    }
};

const std = @import("std");
const as = @import("as");

const Chunk = as.compiler.Chunk;
const GarbageCollector = as.common.memory.GarbageCollector;
const ObjNative = as.runtime.values.ObjNative;
const Value = as.runtime.values.Value;

const StringId = as.common.StringId;

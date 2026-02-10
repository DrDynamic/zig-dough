pub const ObjectType = enum(u8) {
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

    pub inline fn equals(self: ObjectHeader, other: Value) bool {
        _ = self;
        _ = other;
        return false;
    }

    pub inline fn is(self: *const ObjectHeader, tag: ObjectType) bool {
        return self.tag == tag;
    }

    pub inline fn as(self: *ObjectHeader, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("header", self));
    }

    pub fn deinit(self: *ObjectHeader, allocator: std.mem.Allocator) void {
        switch (self.tag) {
            .function => self.as(ObjFunction).deinit(allocator),
            .native_function => self.as(ObjNative).deinit(allocator),
            .module => self.as(ObjModule).deinit(allocator),
            .string => self.as(ObjString).deinit(allocator),
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
    header: ObjectHeader,
    arity: u8,
    max_registers: u8,
    chunk: Chunk,
    name: ?ObjString,

    pub fn init(garbage_collector: *GarbageCollector) *ObjFunction {
        var function = garbage_collector.createObject(ObjFunction, .function);
        function.arity = 0;
        function.chunk = Chunk.init(garbage_collector.allocator());
        function.name = null;

        return function;
    }

    pub fn deinit(self: *ObjFunction, allocator: std.mem.Allocator) void {
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

pub const ObjString = struct {
    header: ObjectHeader,
    data: []const u8,

    pub fn init(data: []const u8, garbage_collector: *GarbageCollector) *ObjString {
        var string = garbage_collector.createObject(ObjString, .string);
        string.data = data;

        return string;
    }

    pub fn copydata(data: []const u8, garbage_collector: *GarbageCollector) *ObjString {
        const buffer = garbage_collector.allocator().alloc(u8, data.len) catch {
            // TODO runtime error?
            @panic("Failed to create String");
        };
        @memcpy(buffer, data);
        return ObjString.init(buffer, garbage_collector);
    }

    pub fn deinit(self: *ObjString, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        allocator.destroy(self);
    }

    pub fn asObject(self: *ObjString) *ObjectHeader {
        return &self.header;
    }
};

const std = @import("std");
const as = @import("as");

const Chunk = as.compiler.Chunk;
const GarbageCollector = as.common.memory.GarbageCollector;
const ObjNative = as.runtime.values.ObjNative;
const Value = as.runtime.values.Value;

const StringId = as.common.StringId;

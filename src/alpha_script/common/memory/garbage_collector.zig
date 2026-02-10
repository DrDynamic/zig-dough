const DebugLogs = struct {
    alloc: bool = false,
    stats: bool = false,
    sweep: bool = false,
    blacken: bool = false,
    mark: bool = false,

    pub fn any(self: *const DebugLogs) bool {
        return self.alloc or self.stats or self.sweep or self.blacken or self.mark;
    }
};

pub const GarbageCollector = struct {
    const GC_HEAP_GROW_FACTOR: usize = 2;

    internal_allocator: std.mem.Allocator,

    // Debugging props
    /// collect garage as often as possible
    stress_mode: bool = false,
    debug_logs: DebugLogs,

    // Collector state
    bytes_allocated: usize,
    next_gc: usize,

    vm: *VirtualMachine = undefined,
    compiler: *Compiler = undefined,

    // Objects
    /// objects, that must not be collected, but arn't in a scope_root yet.
    temp_objects: std.ArrayList(*ObjectHeader),

    /// a list of all instantiated objects
    objects: ?*ObjectHeader = null,

    /// a list of objects already marked by the gc but not blackend yet
    gray_objects: ?*ObjectHeader = null,

    pub fn init(_allocator: std.mem.Allocator) GarbageCollector {
        return .{
            .internal_allocator = _allocator,
            .bytes_allocated = 0,
            .next_gc = 1024 * 1024,
            .debug_logs = .{},
            .temp_objects = std.ArrayList(*ObjectHeader).init(_allocator),
        };
    }

    pub fn createObject(self: *GarbageCollector, comptime T: type, tag: ObjectType) *T {
        var obj: *T = self.allocator().create(T) catch {
            // TODO runtime error?
            @panic("Failed to create Object");
        };

        obj.header = .{
            .tag = tag,
            .is_marked = false,
            .next = self.objects,
            .next_gray = null,
        };

        self.objects = &obj.header;

        if (self.debug_logs.alloc) {
            std.debug.print("   [init] {*} ({s}) {d} bytes\n", .{
                &obj.header,
                @tagName(tag),
                @sizeOf(T),
            });
        }

        return obj;
    }

    pub fn watchVirtualMachine(self: *GarbageCollector, vm: *VirtualMachine) void {
        self.vm = vm;
    }

    pub fn watchCompiler(self: *GarbageCollector, compiler: *Compiler) void {
        self.compiler = compiler;
    }

    pub fn collectGarbage(self: *GarbageCollector) void {
        var size_before: usize = undefined;

        if (self.debug_logs.any()) {
            std.debug.print("-- gc begin\n", .{});
            size_before = self.bytes_allocated;
        }

        //        for (dough.tmpObjects.items) |tmpObject| {
        //            self.markObject(tmpObject);
        //        }

        self.markVmRoots();
        self.markCompilerRoots();
        self.traceReferences();
        //        self.removeUnreferencedStrings();
        self.sweep();

        self.next_gc = self.bytes_allocated * GC_HEAP_GROW_FACTOR;

        if (self.debug_logs.any()) {
            if (self.debug_logs.stats) {
                std.debug.print("   # collected {} bytes \n", .{size_before - self.bytes_allocated});
                std.debug.print("   # still allocated {} bytes\n", .{
                    self.bytes_allocated,
                });

                //                const stack_top = self.vm.stack_top;
                //                const stack = self.vm.stack;

                //                std.debug.print("   # globals.tmpObjects: {d}\n", .{self.temp_objects.items.len});
                //                // TODO implement with string interning
                //                std.debug.print("   # globals.internedStrings: {d}\n", .{0}); // .{self.internedStrings.values().len});
                //                std.debug.print("   # vm.stack: {d}\n", .{(@intFromPtr(stack_top) - @intFromPtr(stack.ptr)) / @sizeOf(values.Value)});
                //                std.debug.print("   # vm.frames: {d}\n", .{self.vm.frame_count});
                //                std.debug.print("   # compiler.current_compiler: {}\n", .{self.compiler.current_compiler != null});

                var object_count: usize = 0;
                var obj = self.objects;
                while (obj != null) {
                    object_count += 1;
                    obj = obj.?.next;
                }
                std.debug.print("   # garbage_collector.objects: {d}\n", .{object_count});

                var gray_count: usize = 0;
                var gray = self.gray_objects;
                while (gray != null) {
                    gray_count += 1;
                    gray = gray.?.next;
                }
                std.debug.print("   # garbage_collector.gray_objects: {d}\n", .{gray_count});
            }
            std.debug.print("-- gc end\n", .{});
        }
    }

    fn markVmRoots(self: *GarbageCollector) void {
        const stack = &self.vm.stack;
        const stack_top = self.vm.stack_top;
        for (0.., stack) |index, value| {
            if (index >= stack_top) break;
            self.markValue(value);
        }

        const frames = &self.vm.frames;
        const frame_count = self.vm.frame_count;
        for (0.., frames) |index, frame| {
            if (index >= frame_count) break;
            self.markObject(frame.function.asObject());
        }
    }

    fn markCompilerRoots(self: *GarbageCollector) void {
        self.markArray(self.compiler.chunk.constants.items);
    }

    fn traceReferences(self: *GarbageCollector) void {
        while (self.gray_objects) |object| {
            self.gray_objects = object.next_gray;
            object.next_gray = null;

            self.blackenObject(object);
        }
    }

    fn sweep(self: *GarbageCollector) void {
        var previous: ?*ObjectHeader = null;
        var maybe_object = self.objects;
        while (maybe_object) |object| {
            if (object.is_marked) {
                object.is_marked = false;
                previous = object;
                maybe_object = object.next;
            } else {
                const unreached = object;
                maybe_object = object.next;
                if (previous) |p| {
                    p.next = maybe_object;
                } else {
                    self.objects = maybe_object;
                }

                if (self.debug_logs.sweep) {
                    std.debug.print("   [sweep] {*} ({s}) '{}'\n", .{ unreached, @tagName(unreached.tag), unreached });
                }

                if (unreached.tag == .string) {
                    // TODO remove interned ObjString
                }
                unreached.deinit(self.allocator());
            }
        }
    }

    fn blackenObject(self: *GarbageCollector, object: *ObjectHeader) void {
        if (self.debug_logs.blacken) {
            std.debug.print("   [blacken] {*} ({s}) '{}'\n", .{
                object,
                @tagName(object.tag),
                object,
            });
        }

        switch (object.tag) {
            .function => {
                const function = object.as(ObjFunction);
                self.markArray(function.chunk.constants.items);
            },
            .module => {
                const module = object.as(ObjModule);
                self.markObject(module.function.asObject());
            },
            .native_function => {},
            .string => {},
        }
    }

    fn markArray(self: *GarbageCollector, array: []Value) void {
        for (array) |value| {
            self.markValue(value);
        }
    }

    fn markValue(self: *GarbageCollector, value: Value) void {
        if (value.isObject()) {
            self.markObject(value.toObject());
        }
    }

    fn markObject(self: *GarbageCollector, maybe_object: ?*ObjectHeader) void {
        const object = maybe_object orelse return;
        if (object.is_marked) return;

        if (self.debug_logs.mark) {
            std.debug.print("   [mark] {*} ({s}) '{}'\n", .{
                object,
                @tagName(object.tag),
                object,
            });
        }

        object.is_marked = true;

        object.next_gray = self.gray_objects;
        self.gray_objects = object;
    }

    // Allocator Interface

    pub fn allocator(self: *GarbageCollector) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    /// Return a pointer to `len` bytes with specified `alignment`, or return
    /// `null` indicating the allocation failed.
    ///
    /// `ret_addr` is optionally provided as the first return address of the
    /// allocation call stack. If the value is `0` it means no return address
    /// has been provided.
    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *GarbageCollector = @ptrCast(@alignCast(context));

        if ((self.bytes_allocated + len > self.next_gc) or self.stress_mode) {
            self.collectGarbage();
        }

        const memory = self.internal_allocator.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.bytes_allocated += len;

        if (self.debug_logs.alloc) {
            std.debug.print("   [alloc] {*} {d} bytes\n", .{
                memory,
                len,
            });
        }

        return memory;
    }

    /// Attempt to expand or shrink memory in place.
    ///
    /// `memory.len` must equal the length requested from the most recent
    /// successful call to `alloc`, `resize`, or `remap`. `alignment` must
    /// equal the same value that was passed as the `alignment` parameter to
    /// the original `alloc` call.
    ///
    /// A result of `true` indicates the resize was successful and the
    /// allocation now has the same address but a size of `new_len`. `false`
    /// indicates the resize could not be completed without moving the
    /// allocation to a different address.
    ///
    /// `new_len` must be greater than zero.
    ///
    /// `ret_addr` is optionally provided as the first return address of the
    /// allocation call stack. If the value is `0` it means no return address
    /// has been provided.
    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *GarbageCollector = @ptrCast(@alignCast(context));
        if (new_len > memory.len) {
            if ((self.bytes_allocated + (new_len - memory.len) > self.next_gc) or self.stress_mode) {
                self.collectGarbage();
            }
        }

        if (self.debug_logs.alloc) {
            std.debug.print("   [resize] {*} from {d} bytes to {d} bytes (delta {d}) \n", .{
                memory.ptr,
                memory.len,
                new_len,
                if (new_len > memory.len) new_len - memory.len else memory.len + new_len,
            });
        }

        if (self.internal_allocator.rawResize(memory, alignment, new_len, ret_addr)) {
            if (new_len > memory.len) {
                self.bytes_allocated += new_len - memory.len;
            } else {
                self.bytes_allocated -= memory.len + new_len;
            }
            return true;
        } else {
            return false;
        }
    }

    /// Attempt to expand or shrink memory, allowing relocation.
    ///
    /// `memory.len` must equal the length requested from the most recent
    /// successful call to `alloc`, `resize`, or `remap`. `alignment` must
    /// equal the same value that was passed as the `alignment` parameter to
    /// the original `alloc` call.
    ///
    /// A non-`null` return value indicates the resize was successful. The
    /// allocation may have same address, or may have been relocated. In either
    /// case, the allocation now has size of `new_len`. A `null` return value
    /// indicates that the resize would be equivalent to allocating new memory,
    /// copying the bytes from the old memory, and then freeing the old memory.
    /// In such case, it is more efficient for the caller to perform the copy.
    ///
    /// `new_len` must be greater than zero.
    ///
    /// `ret_addr` is optionally provided as the first return address of the
    /// allocation call stack. If the value is `0` it means no return address
    /// has been provided.
    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *GarbageCollector = @ptrCast(@alignCast(context));
        if (new_len > memory.len) {
            if ((self.bytes_allocated + (new_len - memory.len) > self.next_gc) or self.stress_mode) {
                self.collectGarbage();
            }
        }

        if (self.debug_logs.alloc) {
            std.debug.print("   [remap] {*} from {d} bytes to {d} bytes (delta {d}) \n", .{
                memory.ptr,
                memory.len,
                new_len,
                if (new_len > memory.len) new_len - memory.len else memory.len + new_len,
            });
        }

        const ptr = self.internal_allocator.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;

        if (new_len > memory.len) {
            self.bytes_allocated += new_len - memory.len;
        } else {
            self.bytes_allocated -= memory.len + new_len;
        }

        return ptr;
    }

    /// Free and invalidate a region of memory.
    ///
    /// `memory.len` must equal the length requested from the most recent
    /// successful call to `alloc`, `resize`, or `remap`. `alignment` must
    /// equal the same value that was passed as the `alignment` parameter to
    /// the original `alloc` call.
    ///
    /// `ret_addr` is optionally provided as the first return address of the
    /// allocation call stack. If the value is `0` it means no return address
    /// has been provided.
    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *GarbageCollector = @ptrCast(@alignCast(context));
        self.internal_allocator.rawFree(memory, alignment, ret_addr);

        if (self.debug_logs.alloc) {
            std.debug.print("   [free] {*} {d} bytes reclaimed\n", .{
                memory.ptr,
                memory.len,
            });
        }

        self.bytes_allocated -= memory.len;
    }
};

const std = @import("std");
const as = @import("as");

const Compiler = as.compiler.Compiler;
const ObjectHeader = as.runtime.values.ObjectHeader;
const ObjFunction = as.runtime.values.ObjFunction;
const ObjModule = as.runtime.values.ObjModule;
const Value = as.runtime.values.Value;
const VirtualMachine = as.runtime.VirtualMachine;

const ObjectType = as.runtime.values.ObjectType;

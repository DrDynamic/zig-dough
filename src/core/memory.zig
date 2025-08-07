const std = @import("std");
const config = @import("../config.zig");
const globals = @import("../globals.zig");
const core = @import("../core/core.zig");
const values = @import("../values/values.zig");
const objects = values.objects;

/// NOTE: only collects Obj types
pub const GarbageColletingAllocator = struct {
    const GC_HEAP_GROW_FACTOR: usize = 2;

    parent_allocator: std.mem.Allocator,

    // data for triggering the gc
    bytes_allocated: usize,
    next_gc: usize,

    // a list of all objects. Filled by DoughObject.init()
    doughObjects: ?*objects.DoughObject = null,

    // a list of objects already marked by the gc but are not blackend yet
    grayObjects: ?*objects.DoughObject = null,

    // references for accessing roots to mark
    compiler: *core.compiler.ModuleCompiler,
    vm: *core.vm.VirtualMachine,

    pub fn init(parent_allocator: std.mem.Allocator, compiler: *core.compiler.ModuleCompiler, vm: *core.vm.VirtualMachine) GarbageColletingAllocator {
        return .{
            .parent_allocator = parent_allocator,
            .bytes_allocated = 0,
            .next_gc = 1024 * 1024,

            .compiler = compiler,
            .vm = vm,
        };
    }

    pub fn allocator(self: *GarbageColletingAllocator) std.mem.Allocator {
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
        const self: *GarbageColletingAllocator = @ptrCast(@alignCast(context));

        if ((self.bytes_allocated + len > self.next_gc) or config.debug_stress_gc) {
            self.collectGarbage();
        }

        const memory = self.parent_allocator.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.bytes_allocated += len;

        if (config.debug_log_gc_alloc) {
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
        const self: *GarbageColletingAllocator = @ptrCast(@alignCast(context));
        if (new_len > memory.len) {
            if ((self.bytes_allocated + (new_len - memory.len) > self.next_gc) or config.debug_stress_gc) {
                self.collectGarbage();
            }
        }

        if (config.debug_log_gc_alloc) {
            std.debug.print("   [resize] {*} from {d} bytes to {d} bytes (delta {d}) \n", .{
                memory.ptr,
                memory.len,
                new_len,
                if (new_len > memory.len) new_len - memory.len else memory.len + new_len,
            });
        }

        if (self.parent_allocator.rawResize(memory, alignment, new_len, ret_addr)) {
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
        const self: *GarbageColletingAllocator = @ptrCast(@alignCast(context));
        if (new_len > memory.len) {
            if ((self.bytes_allocated + (new_len - memory.len) > self.next_gc) or config.debug_stress_gc) {
                self.collectGarbage();
            }
        }

        if (config.debug_log_gc_alloc) {
            std.debug.print("   [remap] {*} from {d} bytes to {d} bytes (delta {d}) \n", .{
                memory.ptr,
                memory.len,
                new_len,
                if (new_len > memory.len) new_len - memory.len else memory.len + new_len,
            });
        }

        const ptr = self.parent_allocator.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;

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
        const self: *GarbageColletingAllocator = @ptrCast(@alignCast(context));
        self.parent_allocator.rawFree(memory, alignment, ret_addr);

        if (config.debug_log_gc_alloc) {
            std.debug.print("   [free] {*} {d} bytes reclaimed\n", .{
                memory.ptr,
                memory.len,
            });
        }

        self.bytes_allocated -= memory.len;
    }

    pub fn collectGarbage(self: *GarbageColletingAllocator) void {
        var size_before: usize = undefined;

        if (config.debug_log_gc_any()) {
            std.debug.print("-- gc begin\n", .{});
            size_before = self.bytes_allocated;
        }

        for (globals.tmpObjects.items) |tmpObject| {
            self.markObject(tmpObject);
        }

        self.markVmRoots();
        self.markCompilerRoots();
        self.traceReferences();
        //        self.removeUnreferencedStrings();
        self.sweep();

        self.next_gc = self.bytes_allocated * GC_HEAP_GROW_FACTOR;

        if (config.debug_log_gc_any()) {
            if (config.debug_log_gc_stats) {
                std.debug.print("   # collected {} bytes \n", .{size_before - self.bytes_allocated});
                std.debug.print("   # still allocated {} bytes\n", .{
                    self.bytes_allocated,
                });

                const stack_top = self.vm.stack_top;
                const stack = self.vm.stack;

                std.debug.print("   # globals.tmpObjects: {d}\n", .{globals.tmpObjects.items.len});
                std.debug.print("   # globals.internedStrings: {d}\n", .{globals.internedStrings.values().len});
                std.debug.print("   # vm.stack: {d}\n", .{(@intFromPtr(stack_top) - @intFromPtr(stack.ptr)) / @sizeOf(values.Value)});
                std.debug.print("   # vm.frames: {d}\n", .{self.vm.frame_count});
                std.debug.print("   # compiler.current_compiler: {}\n", .{self.compiler.current_compiler != null});

                var objectCount: usize = 0;
                var obj = self.doughObjects;
                while (obj != null) {
                    objectCount += 1;
                    obj = obj.?.next;
                }
                std.debug.print("   # garbage_collector.objects: {d}\n", .{objectCount});

                var grayCount: usize = 0;
                var gray = self.grayObjects;
                while (gray != null) {
                    grayCount += 1;
                    gray = gray.?.next;
                }
                std.debug.print("   # garbage_collector.grayObjects: {d}\n", .{grayCount});
            }
            std.debug.print("-- gc end\n", .{});
        }
    }

    fn markVmRoots(self: *GarbageColletingAllocator) void {
        var slot: [*]values.Value = self.vm.stack.ptr;
        while (@intFromPtr(slot) < @intFromPtr(self.vm.stack_top)) : (slot += 1) {
            self.markValue(slot[0]);
        }

        for (0.., self.vm.frames) |index, frame| {
            if (index >= self.vm.frame_count) break;

            self.markObject(frame.closure.asObject());
        }
    }

    fn markCompilerRoots(self: *GarbageColletingAllocator) void {
        var maybeCompiler: ?*core.compiler.FunctionCompiler = self.compiler.current_compiler;
        while (maybeCompiler) |fn_compiler| {
            self.markObject(fn_compiler.function.asObject());
            maybeCompiler = fn_compiler.enclosing;
        }
    }

    fn traceReferences(self: *GarbageColletingAllocator) void {
        while (self.grayObjects) |object| {
            self.grayObjects = object.nextGray;
            object.nextGray = null;

            self.blackenObject(object);
        }
    }

    fn removeUnreferencedStrings(_: *GarbageColletingAllocator) void {
        const strings = &globals.internedStrings;

        std.debug.print("[interned] len: {d}\n", .{strings.count()});
        std.debug.print("[interned] keys.len: {d}\n", .{strings.keys().len});
        std.debug.print("[interned] vals.len: {d}\n", .{strings.values().len});

        var interned = globals.internedStrings.iterator();

        while (interned.next()) |internedString| {
            std.debug.print("  [string] {s} = {*}\n", .{ internedString.key_ptr.*, internedString.value_ptr.* });
            if (!internedString.value_ptr.*.asObject().is_marked) {
                std.debug.print("  [interned] remove {s}\n", .{internedString.key_ptr});
                interned
                    ._ = globals.internedStrings.swapRemove(internedString.key_ptr.*);
            }
        }
        std.debug.print("[interned] len: {d}\n", .{strings.count()});
        std.debug.print("[interned] keys.len: {d}\n", .{strings.keys().len});
        std.debug.print("[interned] vals.len: {d}\n", .{strings.values().len});
    }

    fn sweep(self: *GarbageColletingAllocator) void {
        var previous: ?*objects.DoughObject = null;
        var maybeObject = self.doughObjects;
        while (maybeObject) |object| {
            if (object.is_marked) {
                object.is_marked = false;
                previous = object;
                maybeObject = object.next;
            } else {
                const unreached = object;
                maybeObject = object.next;
                if (previous) |p| {
                    p.next = maybeObject;
                } else {
                    self.doughObjects = maybeObject;
                }

                if (config.debug_log_gc_sweep) {
                    std.debug.print("   [sweep] {*} ({s}) '{}'\n", .{ unreached, @tagName(unreached.obj_type), unreached });
                }

                if (unreached.is(.String)) {
                    _ = globals.internedStrings.swapRemove(unreached.as(objects.DoughString).bytes);
                }
                unreached.deinit();
            }
        }
    }

    fn blackenObject(self: *GarbageColletingAllocator, object: *objects.DoughObject) void {
        if (config.debug_log_gc_blacken) {
            std.debug.print("   [blacken] {*} ({s}) '{}'\n", .{
                object,
                @tagName(object.obj_type),
                object,
            });
        }

        switch (object.obj_type) {
            .Closure => {
                const closure = object.as(objects.DoughClosure);
                self.markObject(closure.function.asObject());
            },
            .Function => {
                const function = object.as(objects.DoughFunction);
                self.markArray(function.chunk.constants.items);
            },
            .Module => {
                const module = object.as(objects.DoughModule);
                self.markObject(module.function.asObject());
            },
            .NativeFunction => {},
            .String => {},
        }
    }

    fn markArray(self: *GarbageColletingAllocator, array: []values.Value) void {
        for (array) |value| {
            self.markValue(value);
        }
    }

    fn markValue(self: *GarbageColletingAllocator, value: values.Value) void {
        if (value.isObject()) {
            self.markObject(value.toObject());
        }
    }

    fn markObject(self: *GarbageColletingAllocator, object: ?*objects.DoughObject) void {
        const assured_object = object orelse return;
        if (assured_object.is_marked) return;

        if (config.debug_log_gc_mark) {
            std.debug.print("   [mark] {*} ({s}) '{}'\n", .{
                assured_object,
                @tagName(assured_object.obj_type),
                assured_object,
            });
        }

        assured_object.is_marked = true;

        assured_object.nextGray = self.grayObjects;
        self.grayObjects = assured_object;
    }
};

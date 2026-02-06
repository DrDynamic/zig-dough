pub const GarbageCollector = struct {
    const GC_HEAP_GROW_FACTOR: usize = 2;

    // Debugging props
    /// collect garage as often as possible
    stress_mode: bool,
    debug_logs: struct {
        /// log allocations
        alloc: bool,

        pub fn any(self: GarbageCollector.debug_logs) bool {
            return self.alloc;
        }
    },

    internal_allocator: std.mem.Allocator,

    // Collector state
    bytes_allocated: usize,
    next_gc: usize,

    // Objects
    /// a list of all instantiated objects
    objects: ?*ObjectHeader = null,

    /// a list of objects already marked by the gc but not blackend yet
    grayObjects: ?*ObjectHeader = null,

    // references for accessing roots to mark
    compiler: *Compiler,
    vm: *VirtualMachine,

    pub fn init(_allocator: std.mem.Allocator, compiler: *Compiler, vm: *VirtualMachine) GarbageCollector {
        return .{
            .internal_allocator = _allocator,
            .bytes_allocated = 0,
            .next_gc = 1024 * 1024,
            .compiler = compiler,
            .vm = vm,
        };
    }

    pub fn collectGarbage(self: GarbageCollector) void {
        var size_before: usize = undefined;

        if (self.debug_logs.any()) {
            std.debug.print("-- gc begin\n", .{});
            size_before = self.bytes_allocated;
        }

        for (dough.tmpObjects.items) |tmpObject| {
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

                std.debug.print("   # globals.tmpObjects: {d}\n", .{dough.tmpObjects.items.len});
                std.debug.print("   # globals.internedStrings: {d}\n", .{dough.internedStrings.values().len});
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

const ObjectHeader = as.runtime.values.ObjectHeader;
const Compiler = as.compiler.Compiler;
const VirtualMachine = as.runtime.VirtualMachine;

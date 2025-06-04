const std = @import("std");

/// NOTE: only collects Obj types
pub const GarbageColletingAllocator = struct {
    parent_allocator: std.mem.Allocator,

    pub fn init(parent_allocator: std.mem.Allocator) GarbageColletingAllocator {
        return .{
            .parent_allocator = parent_allocator,
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

        return self.parent_allocator.rawAlloc(len, alignment, ret_addr);
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

        return self.parent_allocator.rawResize(memory, alignment, new_len, ret_addr);
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

        return self.parent_allocator.rawRemap(memory, alignment, new_len, ret_addr);
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
    }
};

pub const RegisterAllocator = struct {
    pub const Error = error{
        OutOfRegisters,
        RegisterAlreadyAllocated,
        InvalidArgument,
    };

    allocated_bits: std.StaticBitSet(256),

    // statistics
    max_allocated: usize,
    current_allocated: usize,

    forced_next_reg: ?RegisterId,

    pub fn init() RegisterAllocator {
        return .{
            .allocated_bits = std.StaticBitSet(256).initEmpty(),
            .max_allocated = 0,
            .current_allocated = 0,
            .forced_next_reg = null,
        };
    }

    pub fn saveSnapshot(self: RegisterAllocator) RegisterAllocator {
        return self;
    }

    pub fn restoreSnapshot(self: *RegisterAllocator, snapshot: RegisterAllocator) void {
        self.* = snapshot;
    }

    /// returns the allocated register ID or an error if no registers are available
    pub fn allocate(self: *RegisterAllocator) Error!RegisterId {
        // check if there's a forced register to allocate
        if (self.forced_next_reg) |forced_reg| {
            self.forced_next_reg = null;

            self.allocateSpecific(forced_reg);
            return forced_reg;
        }

        var inverted = self.allocated_bits;
        inverted.toggleAll();

        const free_reg = inverted.findFirstSet() orelse return error.OutOfRegisters;

        const reg_index = @as(RegisterId, @intCast(free_reg));
        self.allocateSpecific(reg_index);
        return reg_index;
    }

    /// returns a temporary register that is not allocated (can be requested immediately again)
    pub fn allocateTemporary(self: *RegisterAllocator) Error!RegisterId {
        // allocated and freed to track the register in statistics and ensure forceNext behavior
        const reg = try self.allocate();
        self.free(reg);
        return reg;
    }

    /// allocates the given register if it isn't already
    pub fn ensureAllocated(self: *RegisterAllocator, reg: RegisterId) void {
        if (!self.allocated_bits.isSet(reg)) {
            self.allocateSpecific(reg);
        }
    }

    /// allocates a contiguous range of registers, returns the start register or an error if no suitable range is available
    pub fn allocateRange(self: *RegisterAllocator, count: u8) Error!u8 {
        if (count == 0) return Error.InvalidArgument;
        if (count == 1) return try self.allocate();

        var start_reg: u16 = 0;
        while (start_reg <= 256 - count) {
            var contiguous_found = true;

            // test if the range can start here
            var i: u8 = 0;
            while (i < count) : (i += 1) {
                if (self.allocated_bits.isSet(@intCast(start_reg + i))) {
                    start_reg = start_reg + i + 1;
                    contiguous_found = false;
                    break;
                }
            }

            // allocate the range
            if (contiguous_found) {
                const final_start = @as(u8, @intCast(start_reg));

                var reg_idx = final_start;
                while (reg_idx < final_start + count) : (reg_idx += 1) {
                    self.allocateSpecific(reg_idx);
                }

                return final_start;
            }
        }

        return Error.OutOfRegisters;
    }

    /// free a previously allocated register
    pub fn free(self: *RegisterAllocator, reg: RegisterId) void {
        if (self.allocated_bits.isSet(reg)) {
            self.allocated_bits.unset(reg);
            self.current_allocated -= 1;
        }
    }

    /// returns the maximum number of simultaneously allocated registers
    pub fn getMaxAllocated(self: RegisterAllocator) usize {
        return self.max_allocated;
    }

    /// checks if a register is currently allocated
    pub fn isAllocated(self: *const RegisterAllocator, reg: RegisterId) bool {
        return self.allocated_bits.isSet(reg);
    }

    /// ensures that the next allocate() call will return the specified register
    pub fn forceNext(self: *RegisterAllocator, reg: u8) Error!void {
        if (self.allocated_bits.isSet(reg)) {
            return Error.RegisterAlreadyAllocated;
        }
        // Wir merken uns das Register für den nächsten allocate-Aufruf
        self.forced_next_reg = reg;
    }

    /// internal allocation logic
    fn allocateSpecific(self: *RegisterAllocator, reg: RegisterId) void {
        self.allocated_bits.set(reg);
        self.current_allocated += 1;

        if (self.current_allocated > self.max_allocated) {
            self.max_allocated = self.current_allocated;
        }
    }
};

const std = @import("std");
const as = @import("as");

const RegisterId = as.runtime.RegisterId;

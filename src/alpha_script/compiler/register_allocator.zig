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
        if (self.forced_next_reg) |forced_reg| {
            self.forced_next_reg = null;
            return forced_reg;
        }

        const reg = try self.allocate();
        self.free(reg);
        return reg;
    }

    pub fn allocateTemporaries(self: *RegisterAllocator, comptime count: u8) Error![count]RegisterId {
        var result: [count]RegisterId = undefined;

        const used_force_next = (self.forced_next_reg != null);

        comptime var index: u8 = 0;
        inline while (index < count) : (index += 1) {
            result[index] = try self.allocate();
        }

        index = 0;
        inline while (index < count) : (index += 1) {
            if (index == 0 and used_force_next) {
                // first register comes from force next - should not be freed
                // continue; // can not continue urolled loop
            } else {
                self.free(result[index]);
            }
        }

        return result;
    }

    /// allocates the given register if it isn't already
    pub fn ensureAllocated(self: *RegisterAllocator, reg: RegisterId) void {
        if (!self.allocated_bits.isSet(reg)) {
            self.allocateSpecific(reg);
        }
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

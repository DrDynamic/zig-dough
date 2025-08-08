const std = @import("std");

pub const SlotAddress = u24;
pub const ConstantAddress = u24;

pub const CONSTANT_ADDRESS_INVALID: ConstantAddress = 0xFFFFFF;

pub const max_slot_address = std.math.maxInt(SlotAddress);

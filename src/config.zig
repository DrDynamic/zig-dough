const std = @import("std");

pub const DoughConfig = struct {
    maxFileSize: usize,

    pub fn init() DoughConfig {
        return .{
            .maxFileSize = std.math.maxInt(usize),
        };
    }
};

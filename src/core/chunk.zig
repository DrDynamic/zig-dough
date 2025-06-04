const std = @import("std");

pub const OpCode = enum(u8) {
    Null,
    Pop,
    Return,
};

// TODO: optimize debug info
pub const Chunk = struct {
    code: std.ArrayList(u8),
    lines: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = std.ArrayList(u8).init(allocator),
            .lines = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: Chunk) void {
        self.code.deinit();
    }

    pub fn getLinenumber(self: *Chunk, code_index: usize) ?usize {
        if (self.lines.items.len <= code_index) return null;

        return self.lines.items[code_index];
    }

    pub fn writeByte(self: *Chunk, byte: u8, line: usize) !void {
        try self.code.append(byte);
        try self.lines.append(line);
    }
};

pub const StringId = u32;

pub const StringTable = struct {
    allocator: Allocator,
    buffer: ArrayList(u8), // all strings concatinated
    map: StringArrayHashMap(StringId), // maps string and id

    pub fn init(allocator: Allocator) StringTable {
        return .{
            .allocator = allocator,
            .buffer = ArrayList(u8).init(allocator),
            .map = StringArrayHashMap(StringId).init(allocator),
        };
    }

    pub fn deinit(self: *StringTable) void {
        self.buffer.deinit();
        self.map.deinit();
    }

    pub fn add(self: *StringTable, text: []const u8) !StringId {
        // retrun existing if possible
        if (self.map.get(text)) |id| {
            return id;
        }

        // add to buffer
        const stored_text_start = self.buffer.items.len;
        try self.buffer.appendSlice(text);
        try self.buffer.append(0);

        // add to map
        const new_id: StringId = @intCast(self.map.count());
        const stored_text = self.buffer.items[stored_text_start .. self.buffer.items.len - 1];
        try self.map.put(stored_text, new_id);

        return new_id;
    }

    pub fn get(self: StringTable, id: StringId) []const u8 {
        return self.map.keys()[id];
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;

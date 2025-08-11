const std = @import("std");

const types = @import("../types.zig");
const dough = @import("dough");
const SlotAddress = types.SlotAddress;

const config = dough.config;
const values = dough.values;
const Value = values.Value;

const Type = values.Type;

pub const StackError = error{
    Overflow,
    Underflow,
    ReferenceUndefined,
};

pub const SlotProperties = struct {
    token: ?dough.frontend.Token = null,
    // TODO: increment scope only when necessary
    // a should have depth 0  and b should have depth 1
    // var a; {{{{{{{var b;}}}}}}}

    /// the scope depth of the variable
    depth: u24 = 0,

    /// the identifier used in the sourcecode to access this slot
    identifier: ?[]const u8,

    readonly: bool,

    /// the address of a slot, that is shadowed by this one
    shadowsAddress: ?SlotAddress = null,

    type: ?Type = null,

    isDeclared: bool = false,
    isRead: bool = false,
    isWritten: bool = false,

    pub fn debugPrint(self: SlotProperties) void {
        std.debug.print("[identifier: '{s}', depth: {d}, {s}", .{
            self.identifier orelse "null",
            self.depth,
            if (self.readonly) "readonly" else "writable",
        });

        if (self.shadowsAddress) |shadows| {
            std.debug.print(", shadows: 0x{X}", .{shadows});
        }

        std.debug.print("]", .{});
    }
};

pub const ReferenceStack = struct {
    /// a list of properties for variables, constants, etc
    properties: std.ArrayList(SlotProperties),

    /// a table to resove indetifiers to slot adresses
    addresses: std.StringHashMap(SlotAddress),

    pub fn init() ReferenceStack {
        return .{
            .properties = std.ArrayList(SlotProperties).init(dough.garbage_collector.allocator()),
            .addresses = std.StringHashMap(u24).init(dough.allocator),
        };
    }

    pub fn deinit(self: *ReferenceStack) void {
        self.properties.deinit();
        self.addresses.deinit();
    }

    pub fn debugPrint(self: *ReferenceStack) void {
        std.debug.print("=== ReferenceStack - Properties ===\n", .{});

        for (self.properties.items) |props| {
            props.debugPrint();
            std.debug.print("\n", .{});
        }
    }

    pub fn push(self: *ReferenceStack, properties: SlotProperties) !SlotAddress {
        if (self.properties.items.len >= types.max_slot_address) {
            return StackError.Overflow;
        }

        const id: SlotAddress = @intCast(self.properties.items.len);

        var props = properties;
        if (props.identifier) |identifier| {
            if (self.addresses.contains(identifier)) {
                props.shadowsAddress = self.addresses.get(identifier).?;
            }

            self.addresses.put(identifier, id) catch {
                return StackError.Overflow;
            };
        }

        self.properties.append(props) catch {
            return StackError.Overflow;
        };

        return id;
    }

    pub fn pop(self: *ReferenceStack) !void {
        const props = self.properties.pop() orelse {
            return StackError.Underflow;
        };

        if (props.shadowsAddress) |shadowsAddress| {
            if (props.identifier) |identifier| {
                try self.addresses.put(identifier, shadowsAddress);
            }
        } else {
            if (props.identifier) |identifier| {
                _ = self.addresses.remove(identifier);
            }
        }
    }

    pub fn getProperties(self: ReferenceStack, identifier: []const u8) ?*SlotProperties {
        const address = self.addresses.get(identifier) orelse {
            return null;
        };
        return &self.properties.items[address];
    }
};

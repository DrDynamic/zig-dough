const std = @import("std");

const types = @import("../types.zig");
const SlotAddress = types.SlotAddress;

const config = @import("../config.zig");
const Value = @import("./values.zig").Value;

pub const StackError = error{
    Overflow,
    Underflow,
};

pub const Intent = enum {
    Define,
    Read,
    Write,
};

pub const SlotProperties = struct {
    /// the scope depth of the variable
    depth: usize = 0,

    /// the identifier used in the sourcecode to access this slot
    identifier: []const u8,

    /// the address of a slot, that is shadowed by this one
    shadowsAddress: ?SlotAddress = null,

    /// when the slot is accessed before it was created, intent documents why it was accessed.
    /// So the intent can be validated, when the slot gets defined (e.g. var vs const)
    intent: ?Intent = null,

    fn applyIntent(properties: *SlotProperties, intent: Intent) void {
        if (intent == .Define) {
            properties.intent = null;
        } else if (properties.intent == null or @intFromEnum(intent) > @intFromEnum(properties.intent.?)) {
            properties.intent = intent;
        }
    }
};

pub const SlotStack = struct {
    /// holds solts for values
    slots: std.ArrayList(Value),

    /// a list of properties for variables, constants, etc
    properties: std.ArrayList(SlotProperties),

    /// a table to resove indetifiers to slot adresses
    addresses: std.StringHashMap(SlotAddress),

    pub fn init() SlotStack {
        return .{
            .slots = std.ArrayList(Value).init(config.dough_allocator.allocator()),
            .properties = std.ArrayList(SlotProperties).init(config.dough_allocator.allocator()),
            .addresses = std.StringHashMap(u24).init(config.allocator),
        };
    }

    pub fn deinit(self: *SlotStack) void {
        self.slots.deinit();
        self.properties.deinit();
        self.addresses.deinit();
    }

    fn push(self: *SlotStack, identifier: []const u8, properties: SlotProperties) !SlotAddress {
        if (self.slots.items.len >= types.max_slot_address) {
            return StackError.Overflow;
        }

        const id: SlotAddress = @intCast(self.slots.items.len);
        self.slots.append(Value.makeUninitialized()) catch {
            return StackError.Overflow;
        };

        var props = properties;
        if (self.addresses.contains(identifier)) {
            props.shadowsAddress = self.addresses.get(identifier).?;
        }
        self.properties.append(props) catch {
            return StackError.Overflow;
        };

        self.addresses.put(identifier, id) catch {
            return StackError.Overflow;
        };

        return id;
    }

    pub fn pop(self: *SlotStack) !void {
        _ = self.slots.pop();
        const props = self.properties.pop() orelse {
            return StackError.Underflow;
        };

        if (props.shadowsAddress == null) {
            self.addresses.remove(props.identifier);
        } else {
            self.addresses.put(props.identifier, props.shadowsAddress);
        }
    }

    /// returns the address for the given identifier
    /// If there is not slot for the given identifier it is created with the given Properties and intent.
    ///
    /// Intent is the reason, why the slot was accessed (e.g. an assignment would be an Intent.Write)
    pub fn getOrPush(self: *SlotStack, identifier: []const u8, properties: SlotProperties, intent: Intent) !SlotAddress {
        const address = self.addresses.get(identifier);
        if (address != null) {
            var props = self.properties.items[address.?];
            props.applyIntent(intent);

            return address.?;
        }

        var props = properties;
        props.applyIntent(intent);
        return try self.push(identifier, props);
    }

    pub fn getProperties(self: SlotStack, identifier: []const u8) ?SlotProperties {
        const address = self.addresses.get(identifier) orelse {
            return null;
        };
        return self.properties.items[address];
    }
};

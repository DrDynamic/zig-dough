const std = @import("std");

const types = @import("../types.zig");
const globals = @import("../globals.zig");
const SlotAddress = types.SlotAddress;

const config = @import("../config.zig");
const Value = @import("./values.zig").Value;

pub const StackError = error{
    Overflow,
    Underflow,
    SlotUndefined,
};

pub const Intent = enum {
    Define,
    Read,
    Write,
};

pub const SlotProperties = struct {
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

pub const SlotStack = struct {
    /// holds solts for values
    slots: std.ArrayList(Value),

    /// a list of properties for variables, constants, etc
    properties: std.ArrayList(SlotProperties),

    /// a table to resove indetifiers to slot adresses
    addresses: std.StringHashMap(SlotAddress),

    pub fn init() SlotStack {
        return .{
            .slots = std.ArrayList(Value).init(globals.garbage_collector.allocator()),
            .properties = std.ArrayList(SlotProperties).init(globals.garbage_collector.allocator()),
            .addresses = std.StringHashMap(u24).init(globals.allocator),
        };
    }

    pub fn deinit(self: *SlotStack) void {
        self.slots.deinit();
        self.properties.deinit();
        self.addresses.deinit();
    }

    pub fn debugPrint(self: *SlotStack) void {
        std.debug.print("=== SlotStack - Properties ===\n", .{});

        for (self.properties.items) |props| {
            props.debugPrint();
            std.debug.print("\n", .{});
        }
    }

    pub fn push(self: *SlotStack, properties: SlotProperties) !SlotAddress {
        if (self.slots.items.len >= types.max_slot_address) {
            return StackError.Overflow;
        }

        const id: SlotAddress = @intCast(self.properties.items.len);
        self.slots.append(Value.makeUninitialized()) catch {
            return StackError.Overflow;
        };

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

    pub fn pop(self: *SlotStack) !void {
        _ = self.slots.pop();
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

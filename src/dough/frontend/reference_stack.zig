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
    IdentifierCollision,
    ReferenceUndefined,
};
pub const TypeProperties = struct {
    depth: u24 = 0,
    identifier: []const u8,
    type: Type,

    pub fn format(
        self: TypeProperties,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("[identifier: '{?s}' depth: {d}, type: {}]", .{
            self.identifier,
            self.depth,
            self.type,
        });
    }
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

    pub fn format(
        self: TypeProperties,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("[identifier: '{?s}' depth: {d}, {s}", .{
            self.identifier,
            self.depth,
            if (self.readonly) "readonly" else "writable",
        });

        if (self.shadowsAddress) |shadows| {
            try writer.print(" shadows: 0x{X}", .{shadows});
        }
        try writer.print("]", .{});
    }
};

pub const TypeStack = struct {
    /// a list of properties for variables, constants, etc
    properties: std.ArrayList(TypeProperties),

    /// a table to resove indetifiers to slot adresses
    addresses: std.StringHashMap(u24),

    _internals: _internalFunctions(TypeProperties, u24, std.math.maxInt(u24)),

    pub fn init() TypeStack {
        return .{
            .properties = std.ArrayList(TypeProperties).init(dough.allocator),
            .addresses = std.StringHashMap(u24).init(dough.allocator),
            ._internals = .{},
        };
    }

    pub fn deinit(self: *TypeStack) void {
        self.properties.deinit();
        self.addresses.deinit();
    }

    pub fn debugPrint(self: *TypeStack) void {
        self._internals.debugPrint("TypeStack - Properties", self.properties.items);
    }

    pub fn push(self: *TypeStack, properties: TypeProperties) !u24 {
        if (self.addresses.contains(properties.identifier)) {
            return StackError.IdentifierCollision;
        }

        return self._internals.push(&self.addresses, &self.properties, properties.identifier, properties);
    }

    pub fn pop(self: *TypeStack) !void {
        const props = try self._internals.pop(&self.addresses, &self.properties);
        props.type.deinit();
    }

    pub fn getProperties(self: *TypeStack, identifier: []const u8) ?*TypeProperties {
        return self._internals.getProperties(&self.addresses, &self.properties, identifier);
    }
};

pub const SlotStack = struct {
    /// a list of properties for variables, constants, etc
    properties: std.ArrayList(SlotProperties),

    /// a table to resove indetifiers to slot adresses
    addresses: std.StringHashMap(SlotAddress),

    _internals: _internalFunctions(SlotProperties, SlotAddress, types.max_slot_address),

    pub fn init() SlotStack {
        return .{
            .properties = std.ArrayList(SlotProperties).init(dough.allocator),
            .addresses = std.StringHashMap(SlotAddress).init(dough.allocator),
            ._internals = .{},
        };
    }

    pub fn deinit(self: *SlotStack) void {
        self.properties.deinit();
        self.addresses.deinit();
    }

    pub fn debugPrint(self: *SlotStack) void {
        self._internals.debugPrint("SlotStack - Properties", self.properties.items);
    }

    pub fn push(self: *SlotStack, properties: SlotProperties) !SlotAddress {
        var props = properties;
        if (properties.identifier) |assured_identifier| {
            if (self.addresses.contains(assured_identifier)) {
                props.shadowsAddress = self.addresses.get(assured_identifier).?;
            }
        }

        return self._internals.push(&self.addresses, &self.properties, properties.identifier, props);
    }

    pub fn pop(self: *SlotStack) !void {
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

        if (props.type) |t| {
            t.deinit();
        }
    }

    pub fn getProperties(self: *SlotStack, identifier: []const u8) ?*SlotProperties {
        return self._internals.getProperties(&self.addresses, &self.properties, identifier);
    }
};

fn _internalFunctions(comptime PropertyType: type, comptime AddressType: type, comptime max_stack_size: comptime_int) type {
    return struct {
        const Self = @This();

        fn debugPrint(_: Self, title: []const u8, properties: []PropertyType) void {
            std.debug.print("=== {s} ===\n", .{title});

            for (properties) |props| {
                std.debug.print("{}\n", .{props});
            }
        }

        fn push(_: Self, addresses: *std.StringHashMap(AddressType), properties: *std.ArrayList(PropertyType), identifier: ?[]const u8, pushable: PropertyType) !AddressType {
            if (properties.items.len >= max_stack_size) {
                return StackError.Overflow;
            }

            const id: AddressType = @intCast(properties.items.len);

            if (identifier) |assured_identifier| {
                addresses.put(assured_identifier, id) catch {
                    return StackError.Overflow;
                };
            }

            properties.append(pushable) catch {
                return StackError.Overflow;
            };

            return id;
        }

        pub fn pop(_: Self, addresses: *std.StringHashMap(AddressType), properties: *std.ArrayList(PropertyType)) !PropertyType {
            const props = properties.pop() orelse {
                return StackError.Underflow;
            };

            const maybe_identifier: ?[]const u8 = props.identifier;
            if (maybe_identifier) |identifier| {
                _ = addresses.remove(identifier);
            }

            return props;
        }

        pub fn getProperties(_: Self, addresses: *std.StringHashMap(AddressType), properties: *std.ArrayList(PropertyType), identifier: []const u8) ?*PropertyType {
            const address = addresses.get(identifier) orelse {
                return null;
            };
            return &properties.items[address];
        }
    };
}

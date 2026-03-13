pub const SymbolId = u32;

pub const Symbol = struct {
    name_id: StringId,
    type_id: TypeId,
    node_id: NodeId,
    is_mutable: bool,
    scope_depth: u32,
    initialized: bool,
    shadows_symbol: ?SymbolId,
};

pub const Scope = struct {
    parent: ?*Scope,
    symbols: std.AutoArrayHashMap(u32, Symbol),

    pub fn init(allocator: std.mem.Allocator, parent: ?*Scope) Scope {
        return Scope{
            .parent = parent,
            .symbols = std.AutoArrayHashMap(u32, Symbol).init(allocator),
        };
    }

    pub fn deinit(self: *Scope) void {
        self.symbols.deinit();
    }
};

pub const SymbolTable = struct {
    pub const Error = error{
        RedeclarationError,
        NotFound,
        Underflow,
        OutOfMemory,
    };

    allocator: std.mem.Allocator,

    scope_depth: u32,
    symbols: std.ArrayList(Symbol),
    symbol_ids: std.AutoHashMap(StringId, SymbolId),

    //    current_scope: *Scope,

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        return .{
            .allocator = allocator,
            .scope_depth = 0,
            .symbols = std.ArrayList(Symbol).init(allocator),
            .symbol_ids = std.AutoHashMap(StringId, SymbolId).init(allocator),
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        self.symbols.deinit();
        self.symbol_ids.deinit();
    }

    pub fn clone(self: *SymbolTable) std.mem.Allocator.Error!SymbolTable {
        return .{
            .allocator = self.allocator,
            .scope_depth = self.scope_depth,
            .symbols = try self.symbols.clone(),
            .symbol_ids = try self.symbol_ids.clone(),
        };
    }

    pub fn mergeInitialized(self: *SymbolTable, other: *const SymbolTable) std.mem.Allocator.Error!void {
        var id_map = self.symbol_ids.keyIterator();
        while (id_map.next()) |name_id| {
            const self_symbol = self.lookup(name_id.*) orelse unreachable; // iterating over own symbols, so it must exist
            const other_symbol = other.lookup(name_id.*) orelse continue; // don't make changes, when other symbol does not exist

            if (!self_symbol.initialized or !other_symbol.initialized) {
                self_symbol.initialized = false;
            }
        }
    }

    /// Create a new scope nested within the current scope and set it as current
    pub fn enterScope(self: *SymbolTable) void {
        self.scope_depth += 1;
    }

    /// Exit the current scope and return to the parent scope
    pub fn exitScope(self: *SymbolTable) void {
        self.scope_depth -= 1;

        while (self.symbols.items.len > 0 and self.symbols.getLast().scope_depth > self.scope_depth) {
            _ = self.pop();
        }
    }

    pub fn pop(self: *SymbolTable) ?Symbol {
        const symbol = self.symbols.pop() orelse return null;
        if (symbol.shadows_symbol) |shadow_id| {
            self.symbol_ids.putAssumeCapacity(symbol.name_id, shadow_id); // space shoukd already be allocated, since this is only a value replacement
        } else {
            _ = self.symbol_ids.remove(symbol.name_id);
        }
        return symbol;
    }

    /// Declare a new symbol in the current scope
    pub fn declare(self: *SymbolTable, name_id: StringId, type_id: TypeId, node_id: NodeId, is_mutable: bool) Error!void {
        const maybe_shadowed_id = self.symbol_ids.get(name_id);

        if (maybe_shadowed_id) |shadowed_id| {
            const shadowed_symbol = self.symbols.items[shadowed_id];
            if (shadowed_symbol.scope_depth == self.scope_depth) return Error.RedeclarationError;
        }

        try self.symbol_ids.put(name_id, @intCast(self.symbols.items.len));
        try self.symbols.append(.{
            .name_id = name_id,
            .type_id = type_id,
            .node_id = node_id,
            .is_mutable = is_mutable,
            .scope_depth = self.scope_depth,
            .initialized = false,
            .shadows_symbol = maybe_shadowed_id,
        });
    }

    pub inline fn setType(self: *SymbolTable, name_id: StringId, type_id: TypeId) Error!void {
        const symbol = self.lookup(name_id) orelse {
            return Error.NotFound;
        };

        symbol.type_id = type_id;
    }

    pub inline fn initialize(self: *SymbolTable, name_id: StringId) Error!void {
        const symbol = self.lookup(name_id) orelse {
            return Error.NotFound;
        };

        symbol.initialized = true;
    }

    /// Lookup a symbol by name, searching through parent scopes if necessary
    /// Returns null if the symbol is not found
    pub fn lookup(self: *const SymbolTable, name_id: StringId) ?*Symbol {
        const symbol_id = self.symbol_ids.get(name_id) orelse {
            return null;
        };

        return &self.symbols.items[symbol_id];
    }
};

const std = @import("std");
const as = @import("as");
const StringId = as.common.StringId;
const TypeId = as.frontend.TypeId;
const NodeId = as.frontend.ast.NodeId;

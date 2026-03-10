pub const Symbol = struct {
    name_id: StringId,
    type_id: TypeId,
    is_mutable: bool,
    node_id: NodeId,
    initialized: bool,
};

pub const Scope = struct {
    parent: ?*Scope,
    symbols: std.AutoHashMap(u32, Symbol),

    pub fn init(allocator: std.mem.Allocator, parent: ?*Scope) Scope {
        return Scope{
            .parent = parent,
            .symbols = std.AutoHashMap(u32, Symbol).init(allocator),
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
        OutOfMemory,
    };

    allocator: std.mem.Allocator,
    current_scope: *Scope,

    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!SymbolTable {
        const global_scope = try allocator.create(Scope);
        global_scope.* = Scope.init(allocator, null);
        return SymbolTable{
            .allocator = allocator,
            .current_scope = global_scope,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        var maybe_scope: ?*Scope = self.current_scope;
        while (maybe_scope) |scope| {
            const parent = scope.parent;
            scope.deinit();
            self.allocator.destroy(scope);
            maybe_scope = parent;
        }
    }

    /// Create a new scope nested within the current scope and set it as current
    pub fn enterScope(self: *SymbolTable) std.mem.Allocator.Error!void {
        const new_scope = try self.allocator.create(Scope);
        new_scope.* = Scope.init(self.allocator, self.current_scope);
        self.current_scope = new_scope;
    }

    /// Exit the current scope and return to the parent scope
    pub fn exitScope(self: *SymbolTable) void {
        const parent = self.current_scope.parent orelse return;
        const old_scope = self.current_scope;
        old_scope.deinit();
        self.allocator.destroy(old_scope);
        self.current_scope = parent;
    }

    /// Declare a new symbol in the current scope
    pub fn declare(self: *SymbolTable, name_id: StringId, symbol: Symbol) Error!void {
        if (self.current_scope.symbols.contains(name_id)) {
            return Error.RedeclarationError;
        }

        try self.current_scope.symbols.put(name_id, symbol);
    }

    pub inline fn setType(self: *SymbolTable, name_id: StringId, type_id: TypeId) Error!void {
        if (self.current_scope.symbols.getPtr(name_id)) |symbol| {
            symbol.type_id = type_id;
            return;
        }
        return Error.NotFound;
    }

    pub inline fn initialize(self: *SymbolTable, name_id: StringId) Error!void {
        if (self.current_scope.symbols.getPtr(name_id)) |symbol| {
            symbol.initialized = true;
            return;
        }
        return Error.NotFound;
    }

    /// Lookup a symbol by name, searching through parent scopes if necessary
    /// Returns null if the symbol is not found
    pub fn lookup(self: *const SymbolTable, name_id: StringId) ?*Symbol {
        var scope: ?*Scope = self.current_scope;
        while (scope) |s| : (scope = scope.?.*.parent) {
            if (s.symbols.contains(name_id)) return s.symbols.getPtr(name_id).?;
        }
        return null;
    }
};

const std = @import("std");
const as = @import("as");
const StringId = as.common.StringId;
const TypeId = as.frontend.TypeId;
const NodeId = as.frontend.ast.NodeId;

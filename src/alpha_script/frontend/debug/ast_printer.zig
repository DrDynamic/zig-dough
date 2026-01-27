pub const ASTPrinter = struct {
    ast: *const AST,
    type_pool: *const TypePool,
    writer: std.fs.File.Writer,

    pub fn printAST(ast_: *const AST, type_pool: *const TypePool, writer: std.fs.File.Writer) !void {
        var printer = ASTPrinter{
            .ast = ast_,
            .type_pool = type_pool,
            .writer = writer,
        };

        const roots = ast_.getRoots();
        for (0.., roots) |index, node_id| {
            try printer.printNode(node_id, "", index == roots.len - 1);
        }
    }

    fn printNode(self: ASTPrinter, node_idx: ast.NodeId, prefix: []const u8, is_last: bool) error{ OutOfMemory, NoSpaceLeft, DiskQuota, FileTooBig, InputOutput, DeviceBusy, InvalidArgument, AccessDenied, BrokenPipe, SystemResources, OperationAborted, NotOpenForWriting, LockViolation, WouldBlock, ConnectionResetByPeer, ProcessNotFound, NoDevice, Unexpected }!void {
        const node = self.ast.nodes.items[node_idx];
        const node_type = self.type_pool.types.items[node.resolved_type_id];

        // 1. Zeichne den aktuellen Zweig
        try self.writer.print("{s}{s}{s}[{s}]", .{
            prefix,
            if (is_last) "└── " else "├── ",
            //            node_idx,
            @tagName(node.tag),
            @tagName(node_type.tag),
        });

        // 2. Spezifische Daten je nach Typ ausgeben
        switch (node.tag) {
            .comptime_uninitialized => try self.writer.print(": -", .{}),
            .literal_void => try self.writer.print(": void\n", .{}),
            .literal_null => try self.writer.print(": null\n", .{}),
            .literal_int => try self.writer.print(": {d}\n", .{node.data.int_value}),
            .literal_float => try self.writer.print(": {d:.4}\n", .{node.data.float_value}),
            .literal_bool => try self.writer.print(": {}\n", .{node.data.bool_value}),
            .literal_string,
            .identifier_expr,
            => {
                const str = self.ast.string_table.get(node.data.string_id);
                try self.writer.print(": \"{s}\"\n", .{str});
            },
            // TODO print the actual string
            .object_string => try self.writer.print(": string\n", .{}),
            .binary_add,
            .binary_sub,
            .binary_mul,
            .binary_div,
            => {
                try self.writer.print("\n", .{});
            },
            .binary_equal,
            .binary_not_equal,
            .binary_less,
            .binary_less_equal,
            .binary_greater,
            .binary_greater_equal,
            => {
                try self.writer.print("\n", .{});
            },
            .declaration_var => {
                const data = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationData);
                const name = self.ast.string_table.get(data.name_id);
                try self.writer.print(" (name: {s}, init_value: {d})\n", .{ name, data.init_value });
            },
        }

        // 3. Kinder rekursiv verarbeiten
        const new_prefix = try std.fmt.allocPrint(self.ast.allocator, "{s}{s}", .{
            prefix,
            if (is_last) "    " else "│   ",
        });
        defer self.ast.allocator.free(new_prefix);

        try self.printChildren(node, new_prefix);
    }

    fn printChildren(self: ASTPrinter, node: ast.Node, prefix: []const u8) !void {
        switch (node.tag) {
            .comptime_uninitialized,
            .literal_void,
            .literal_null,
            .literal_int,
            .literal_float,
            .literal_bool,
            .literal_string,
            .identifier_expr,
            => {}, // Blätter haben keine Kinder
            .object_string => {},

            .binary_add,
            .binary_sub,
            .binary_mul,
            .binary_div,
            .binary_equal,
            .binary_not_equal,
            .binary_less,
            .binary_less_equal,
            .binary_greater,
            .binary_greater_equal,
            => {
                const extra = self.ast.getExtra(node.data.extra_id, BinaryOpData);
                try self.printNode(extra.lhs, prefix, false);
                try self.printNode(extra.rhs, prefix, true);
            },
            .declaration_var => {
                const data = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationData);
                try self.printNode(data.init_value, prefix, true);
            },
        }
    }
};

const std = @import("std");
const as = @import("as");
const ast = as.frontend.ast;
const AST = as.frontend.AST;
const TypePool = as.frontend.TypePool;
const BinaryOpData = ast.BinaryOpData;

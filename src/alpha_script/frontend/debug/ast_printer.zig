pub const ASTPrinter = struct {
    ast: *const AST,
    writer: std.fs.File.Writer,

    pub fn printAST(ast_: *const AST, writer: std.fs.File.Writer) !void {
        var printer = ASTPrinter{
            .ast = ast_,
            .writer = writer,
        };

        for (ast_.getRoots()) |node_id| {
            try printer._printRecursive(node_id, 0);
        }
    }

    pub fn _printRecursive(self: ASTPrinter, node_idx: ast.NodeId, indent: usize) !void {
        // Einrücken für die Hierarchie
        try self.printIndent(indent);

        const node = self.ast.nodes.items[node_idx];

        // Ausgabe des Tags
        try self.writer.print("[{d}] {s}", .{ node_idx, @tagName(node.tag) });

        // Spezifische Daten je nach Typ ausgeben
        switch (node.tag) {
            .comptime_uninitialized => try self.writer.print(": -", .{}),
            .literal_null => try self.writer.print(": null\n", .{}),
            .literal_int => try self.writer.print(": {d}\n", .{node.data.int_value}),
            .literal_float => try self.writer.print(": {d:.2}\n", .{node.data.float_value}),
            .literal_bool => try self.writer.print(": {}\n", .{node.data.bool_value}),
            .literal_string,
            .identifier_expr,
            => {
                const str = self.ast.string_table.get(node.data.string_id);
                try self.writer.print(": \"{s}\"\n", .{str});
            },
            .binary_add,
            .binary_sub,
            .binary_mul,
            .binary_div,
            => {
                try self.writer.print("\n", .{});

                const extra = self.ast.getExtra(node.data.extra_id, BinaryOpData);
                try self._printRecursive(extra.lhs, indent + 2);
                try self._printRecursive(extra.rhs, indent + 2);
            },
            .binary_equal,
            .binary_not_equal,
            .binary_less,
            .binary_less_equal,
            .binary_greater,
            .binary_greater_equal,
            => {
                try self.writer.print("\n", .{});

                const extra = self.ast.getExtra(node.data.extra_id, ast.BinaryOpData);
                try self._printRecursive(extra.lhs, indent + 2);
                try self._printRecursive(extra.rhs, indent + 2);
            },
            .declaration_var => {
                const data = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationData);
                const name = self.ast.string_table.get(data.name_id);
                try self.writer.print(" (name: {s}, init_value: {d})\n", .{ name, data.init_value });
                try self._printRecursive(data.init_value, indent + 2);
            },
        }
    }

    fn printIndent(self: ASTPrinter, level: usize) !void {
        try self.writer.writeByteNTimes(' ', level * 2);
    }
};

const std = @import("std");
const as = @import("as");
const ast = as.frontend.ast;
const AST = as.frontend.AST;

const BinaryOpData = ast.BinaryOpData;

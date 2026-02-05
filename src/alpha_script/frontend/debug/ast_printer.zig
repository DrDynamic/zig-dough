const branch_options: Terminal.PrintOptions = .{
    .styles = &.{.bold},
};

pub const ASTPrinter = struct {
    ast: *const AST,
    type_pool: *const TypePool,
    terminal: *const Terminal,

    pub fn printAST(ast_: *const AST, type_pool: *const TypePool, terminal: *const Terminal) !void {
        var printer = ASTPrinter{
            .ast = ast_,
            .type_pool = type_pool,
            .terminal = terminal,
        };

        printer.terminal.print("AST (valid: {s})\n", .{if (printer.ast.is_valid) "true" else "false"});
        const roots = ast_.getRoots();
        for (0.., roots) |index, node_id| {
            try printer.printNode(node_id, "", index == roots.len - 1);
        }
    }

    fn printNode(self: ASTPrinter, node_idx: ast.NodeId, prefix: []const u8, is_last: bool) std.fmt.AllocPrintError!void {
        const node = self.ast.nodes.items[node_idx];
        const node_type = self.type_pool.types.items[node.resolved_type_id];

        // 1. draw the branch
        self.terminal.print("{s}{s}", .{
            prefix,
            if (is_last) "└──" else "├──",
        });

        self.terminal.printWithOptions("[{s}] ", .{
            @tagName(node_type.tag),
        }, .{ .styles = &.{.bold} });

        self.terminal.printWithOptions("{s}", .{
            @tagName(node.tag),
        }, .{ .styles = &.{} });

        // 2. Spezifische Daten je nach Typ ausgeben
        switch (node.tag) {
            .comptime_uninitialized => self.terminal.print(": -", .{}),
            .literal_void => self.terminal.print(": void\n", .{}),
            .literal_null => self.terminal.print(": null\n", .{}),
            .literal_int => self.terminal.print(": {d}\n", .{node.data.int_value}),
            .literal_float => self.terminal.print(": {d:.4}\n", .{node.data.float_value}),
            .literal_bool => self.terminal.print(": {}\n", .{node.data.bool_value}),

            // TODO print the actual string
            .object_string => self.terminal.print(": string\n", .{}),
            .binary_add,
            .binary_sub,
            .binary_mul,
            .binary_div,
            => {
                self.terminal.print("\n", .{});
            },
            .binary_equal,
            .binary_not_equal,
            .binary_less,
            .binary_less_equal,
            .binary_greater,
            .binary_greater_equal,
            => {
                self.terminal.print("\n", .{});
            },
            .declaration_var => {
                const data = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationExtra);
                const name = self.ast.string_table.get(data.name_id);
                self.terminal.print(" (name: {s}, init_value: {d})\n", .{ name, data.init_value });
            },
            // access
            .identifier_expr,
            => {
                const str = self.ast.string_table.get(node.data.string_id);
                self.terminal.print(": \"{s}\"\n", .{str});
            },
            .call => {
                const data = self.ast.getExtra(node.data.extra_id, ast.CallExtra);
                self.terminal.print("( args: {d})\n", .{data.args_count});
            },
            .node_list => {
                self.terminal.print("\n", .{});
            },
            //
            .stack_return => {
                self.terminal.print("\n", .{});
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
                const extra = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);
                try self.printNode(extra.lhs, prefix, false);
                try self.printNode(extra.rhs, prefix, true);
            },
            .declaration_var => {
                const data = self.ast.getExtra(node.data.extra_id, ast.VarDeclarationExtra);
                try self.printNode(data.init_value, prefix, true);
            },
            .stack_return => {
                try self.printNode(node.data.node_id, prefix, true);
            },
            // access
            .call => {
                const data = self.ast.getExtra(node.data.extra_id, ast.CallExtra);
                try self.printNode(data.callee, prefix, false);

                var arg_id = data.args_start;
                for (0..data.args_count) |index| {
                    try self.printNode(arg_id, prefix, index == data.args_count - 1);

                    const arg_node = self.ast.nodes.items[arg_id];
                    const list_extra = self.ast.getExtra(arg_node.data.extra_id, ast.NodeListExtra);
                    arg_id = list_extra.next;
                }
            },
            .node_list => {
                const data = self.ast.getExtra(node.data.extra_id, ast.NodeListExtra);
                try self.printNode(data.node_id, prefix, true);
            },
        }
    }
};

const std = @import("std");
const as = @import("as");
const ast = as.frontend.ast;
const AST = as.frontend.AST;
const TypePool = as.frontend.TypePool;
const BinaryOpExtra = ast.BinaryOpExtra;
const Terminal = as.common.Terminal;

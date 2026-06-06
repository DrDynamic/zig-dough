const branch_options: Terminal.PrintOptions = .{
    .styles = &.{.bold},
};

pub const ASTPrinter = struct {
    ast: *const AST,
    type_pool: *const TypePool,
    terminal: *Terminal,

    pub fn printAST(ast_: *const AST, terminal: *Terminal) !void {
        var printer = ASTPrinter{
            .ast = ast_,
            .type_pool = &ast_.type_pool,
            .terminal = terminal,
        };

        printer.terminal.print("AST (valid: {s})\n", .{if (printer.ast.is_valid) "true" else "false"});
        const roots = ast_.getRoots();
        for (0.., roots) |index, node_id| {
            try printer.printNode(node_id, "", index == roots.len - 1);
        }
    }

    fn printNode(self: ASTPrinter, node_idx: ast.NodeId, prefix: []const u8, is_last: bool) error{OutOfMemory}!void {
        const node = self.ast.nodes.items[node_idx];
        const node_type = self.type_pool.types.items[node.resolved_type_id];

        // 1. draw the branch
        self.terminal.print("{s}{s}", .{
            prefix,
            if (is_last) "└──" else "├──",
        });

        self.terminal.printWithOptions("[{s}] ", .{
            @tagName(node_type),
        }, .{ .styles = &.{.bold} });

        self.terminal.printWithOptions("{s}", .{
            @tagName(node.tag),
        }, .{ .styles = &.{} });

        // 2. Spezifische Daten je nach Typ ausgeben
        switch (node.tag) {
            .literal_null => self.terminal.print(": null\n", .{}),
            .literal_int => self.terminal.print(": {d}\n", .{node.data.int_value}),
            .literal_float => self.terminal.print(": {d:.4}\n", .{node.data.float_value}),
            .literal_bool => self.terminal.print(": {}\n", .{node.data.bool_value}),
            .literal_error => {
                const error_name_id = self.type_pool.error_pool.getErrorNameId(node.data.error_value);
                const error_name = self.ast.string_table.get(error_name_id);
                self.terminal.print(": {s}\n", .{error_name});
            },

            .object_string => {
                const str = self.ast.string_table.get(node.data.string_id);
                self.terminal.print(": '{s}'\n", .{str});
            },
            .negate,
            .logical_not,
            => {
                self.terminal.print("\n", .{});
            },
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
            .logical_or,
            .logical_and,
            => {
                self.terminal.print("\n", .{});
            },

            .declaration_error_set,
            .declaration_type,
            .declaration_var,
            .declaration_const,
            => {
                const data = self.ast.getExtra(node.data.extra_id, ast.DeclarationExtra);
                const name = self.ast.string_table.get(data.name_id);
                self.terminal.print(" name: {s}\n", .{name});
            },
            .declaration_parameter => unreachable,

            // expressions
            .expression_assignment => self.terminal.print("\n", .{}),
            .expression_function => {
                const fn_extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);

                var prototype: std.ArrayList(u8) = .{};
                defer prototype.deinit(self.ast.allocator);

                if (fn_extra.name_id) |name_id| {
                    const fn_name = self.ast.string_table.get(name_id);
                    try prototype.appendSlice(self.ast.allocator, fn_name);
                }

                try prototype.append(self.ast.allocator, '(');

                if (fn_extra.parameters) |parameters| {
                    for (parameters) |parameter_id| {
                        const parameter_node = self.ast.nodes.items[parameter_id];
                        const parameter_name = self.ast.string_table.get(parameter_node.data.string_id);
                        try prototype.appendSlice(self.ast.allocator, parameter_name);
                        try prototype.append(self.ast.allocator, ':');

                        const type_name = try self.ast.type_pool.getTypeNameAlloc(
                            self.ast.allocator,
                            parameter_node.resolved_type_id,
                            self.ast.string_table,
                        );
                        defer self.ast.allocator.free(type_name);
                        try prototype.appendSlice(self.ast.allocator, type_name);
                        try prototype.append(self.ast.allocator, ',');
                    }
                    _ = prototype.pop(); // remove last ','
                }

                try prototype.append(self.ast.allocator, ')');

                const return_type_name = try self.ast.type_pool.getTypeNameAlloc(
                    self.ast.allocator,
                    fn_extra.return_type,
                    self.ast.string_table,
                );
                defer self.ast.allocator.free(return_type_name);
                try prototype.appendSlice(self.ast.allocator, return_type_name);
            },
            .expression_block,
            .expression_grouping,
            .expression_if,
            => {
                self.terminal.print("\n", .{});
            },

            // access
            .expression_identifier,
            => {
                const str = self.ast.string_table.get(node.data.string_id);
                self.terminal.print(": \"{s}\"\n", .{str});
            },
            .call => {
                self.terminal.print("\n", .{});
            },
            .node_list => {
                self.terminal.print("\n", .{});
            },
            //
            .statement_return => {
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
            .literal_null,
            .literal_int,
            .literal_float,
            .literal_bool,
            .literal_error,
            .expression_identifier,
            => {}, // leaves don't have children
            .object_string => {},

            .negate,
            .logical_not,
            => {
                try self.printNode(node.data.node_id, prefix, true);
            },

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
            .logical_or,
            .logical_and,
            => {
                const extra = self.ast.getExtra(node.data.extra_id, BinaryOpExtra);
                try self.printNode(extra.lhs, prefix, false);
                try self.printNode(extra.rhs, prefix, true);
            },
            .declaration_parameter => unreachable,
            .declaration_error_set,
            .declaration_type,
            .declaration_const,
            .declaration_var,
            => {
                const data = self.ast.getExtra(node.data.extra_id, ast.DeclarationExtra);
                if (data.init_value) |init_value_id| {
                    try self.printNode(init_value_id, prefix, true);
                } else {
                    self.terminal.print("{s} (no initializer)\n", .{prefix});
                }
            },
            .statement_return => {
                try self.printNode(node.data.node_id, prefix, true);
            },
            // expressions
            .expression_function => {
                const extra = self.ast.getExtra(node.data.extra_id, FunctionExtra);
                try self.printNode(extra.body, prefix, true);
            },
            .expression_assignment => {
                const extra = self.ast.getExtra(node.data.extra_id, ast.AssignmentExtra);
                try self.printNode(extra.target, prefix, false);
                try self.printNode(extra.source, prefix, true);
            },
            .expression_block => {
                const extra = self.ast.getExtra(node.data.extra_id, ast.BlockExtra);

                if (extra.statements) |statements| {
                    for (statements) |statement_id| {
                        try self.printNode(statement_id, prefix, false);
                    }
                }
            },
            .expression_grouping => {
                try self.printNode(node.data.node_id, prefix, true);
            },
            .expression_if => {
                const extra = self.ast.getExtra(node.data.extra_id, ast.IfExtra);
                try self.printNode(extra.condition, prefix, false);

                if (extra.then_capture != null) {
                    try self.printNode(extra.then_capture.?, prefix, false);
                }
                try self.printNode(extra.then_branch, prefix, false);

                if (extra.else_capture != null) {
                    try self.printNode(extra.else_capture.?, prefix, false);
                }
                if (extra.else_branch != null) {
                    try self.printNode(extra.else_branch.?, prefix, true);
                }
            },
            // access
            .call,
            => {
                const extra = self.ast.getExtra(node.data.extra_id, ast.CallExtra);
                try self.printNode(extra.callee, prefix, false);

                if (extra.args) |args| {
                    for (args) |arg_id| {
                        try self.printNode(arg_id, prefix, false);
                    }
                }
            },
            .node_list => {
                // TODO test is this still works
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
const NodeListIterator = as.frontend.ast.NodeListIterator;
const TypePool = as.frontend.TypePool;
const Terminal = as.common.Terminal;

const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;
const FunctionExtra = as.frontend.ast.FunctionExtra;

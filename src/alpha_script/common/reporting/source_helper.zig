pub const SourceLocation = struct {
    line: usize,
    column: usize,
    marker_start: usize,
    marker_end: usize,
    line_start: usize,
    line_end: usize,
};

pub inline fn astFromReportingModule(reporting_module: ReportingModule) ?*AST {
    return switch (reporting_module) {
        .TokenStream => |_| null,
        .Parser => |parser| parser.ast,
        .SemanticAnalyser => |semantic_analyser| semantic_analyser.ast,
        .Compiler => |compiler| compiler.ast,
        .VirtualMachine => |_| unreachable,
    };
}

pub inline fn sourceFromReportingModule(reporting_module: ReportingModule) []const u8 {
    return switch (reporting_module) {
        .TokenStream => |token_stream| token_stream.source,
        .Parser => |parser| parser.scanner.token_stream.source,
        .SemanticAnalyser => |semantic_analyser| semantic_analyser.ast.scanner.token_stream.source,
        .Compiler => |compiler| compiler.ast.scanner.token_stream.source,
        .VirtualMachine => |_| unreachable,
    };
}

pub inline fn calcNodeLocation(source: []const u8, node: Node, ast: *AST) !SourceLocation {
    switch (node.tag) {
        .declaration_var => {
            // TODO: find start and end position of var declaration. It contains a dynamic set of tokens (var <identifier> [:type] [=])
            var token_stream = ast.scanner.token_stream;
            const token = try token_stream.scanPosition(node.token_position);
            return calcTokenLocation(source, token);
        },
        .call => {
            const extra = ast.getExtra(node.data.extra_id, CallExtra);

            var token_stream = ast.scanner.token_stream;
            const token_start = try token_stream.scanPosition(node.token_position);
            var token_end = token_start;

            var arg_list = extra.args_start;
            for (0..extra.args_count) |_| {
                const list_node = ast.nodes.items[arg_list];
                const list_extra = ast.getExtra(list_node.data.extra_id, NodeListExtra);

                const arg_node = ast.nodes.items[list_extra.node_id];
                token_end = try token_stream.scanPosition(arg_node.token_position);

                arg_list = list_extra.next;
            }

            const location_start = calcTokenLocation(source, token_start);
            const location_end = calcTokenLocation(source, token_end);

            return SourceLocation{
                .line = location_start.line,
                .column = location_start.column,
                .marker_start = location_start.marker_start,
                .marker_end = location_end.marker_end,
                .line_start = location_start.line_start,
                .line_end = location_end.line_end,
            };
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
            const extra = ast.getExtra(node.data.extra_id, BinaryOpExtra);
            var token_stream = ast.scanner.token_stream;

            const token_lhs = try token_stream.scanPosition(ast.nodes.items[extra.lhs].token_position);
            const token_operator = try token_stream.scanPosition(node.token_position);
            const token_rhs = try token_stream.scanPosition(ast.nodes.items[extra.rhs].token_position);

            const position_lhs = calcTokenLocation(source, token_lhs);
            const position_operator = calcTokenLocation(source, token_operator);
            const position_rhs = calcTokenLocation(source, token_rhs);

            return SourceLocation{
                .line = position_lhs.line,
                .column = position_operator.column,
                .marker_start = position_lhs.marker_start,
                .marker_end = position_rhs.marker_end,
                .line_start = position_lhs.line_start,
                .line_end = position_rhs.line_end,
            };
        },
        else => {
            var token_stream = ast.scanner.token_stream;
            const token = try token_stream.scanPosition(node.token_position);
            return calcTokenLocation(source, token);
        },
    }
}

pub inline fn calcTokenLocation(source: []const u8, token: Token) SourceLocation {
    var location = SourceLocation{
        .line = 1,
        .column = 1,
        .marker_start = 1,
        .marker_end = 1,
        .line_start = 0,
        .line_end = 0,
    };

    for (source, 0..) |char, index| {
        if (index == token.location.start) break;

        if (char == '\n') {
            location.line += 1;
            location.column = 1;
            location.marker_start = 1;
            location.line_start = index + 1;
        } else {
            location.column += 1;
            location.marker_start += 1;
        }
    }

    location.marker_end = location.marker_start + (token.location.end - token.location.start);

    var end_index = token.location.start;
    while (end_index < source.len and source[end_index] != '\n' and source[end_index] != '\r') : (end_index += 1) {}
    location.line_end = end_index;

    return location;
}

const as = @import("as");
const ReportingModule = as.common.reporting.ReportingModule;
const Token = as.frontend.Token;
const Node = as.frontend.ast.Node;
const AST = as.frontend.AST;
const VarDeclarationExtra = as.frontend.ast.VarDeclarationExtra;
const CallExtra = as.frontend.ast.CallExtra;
const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;
const NodeListExtra = as.frontend.ast.NodeListExtra;

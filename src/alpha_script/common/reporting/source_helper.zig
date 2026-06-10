pub const SourceLocation = struct {
    line: usize,
    column: usize,
    marker_start: usize,
    marker_end: usize,
    line_start: usize,
    line_end: usize,
};

pub inline fn astFromReportingModule(reporting_module: ReportingModule) ?*const AST {
    return switch (reporting_module) {
        .TokenStream => |_| null,
        .Parser => |parser| &parser.ast,
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

pub inline fn calcSourceLocation(source: []const u8, source_start: usize, source_end: usize) SourceLocation {
    //    _ = source_end;
    var location = SourceLocation{
        .line = 1,
        .column = 1,
        .marker_start = 1,
        .marker_end = 1,
        .line_start = 0,
        .line_end = 0,
    };

    // set column and line
    for (source, 0..) |char, index| {
        if (index == source_start) break;

        if (char == '\n') {
            location.line += 1;
            location.column = 1;
            location.line_start = index + 1;
        } else {
            location.column += 1;
        }
    }

    // find line end
    var end_index = source_start;
    while (end_index < source.len and source[end_index] != '\n' and source[end_index] != '\r') : (end_index += 1) {}
    location.line_end = end_index;

    // calc marker location
    location.marker_start = source_start;
    location.marker_end = @min(source_end, location.line_end);

    return location;
}

const as = @import("as");
const ReportingModule = as.common.reporting.ReportingModule;
const Token = as.frontend.Token;
const Node = as.frontend.ast.Node;
const AST = as.frontend.AST;
const DeclarationExtra = as.frontend.ast.DeclarationExtra;
const CallExtra = as.frontend.ast.CallExtra;
const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;

pub const SourceLocation = struct {
    line: usize,
    column: usize,
    width: usize,
    line_start: usize,
    line_end: usize,
};

pub inline fn sourceFromReportingModule(reporting_module: ReportingModule) []const u8 {
    return switch (reporting_module) {
        .TokenStream => |token_stream| token_stream.source,
        .Parser => |parser| parser.scanner.token_stream.source,
        .SemanticAnalyser => |semantic_analyser| semantic_analyser.ast.scanner.token_stream.source,
        .Compiler => |compiler| compiler.ast.scanner.token_stream.source,
        .VirtualMachine => |_| unreachable,
    };
}

pub inline fn calcSourceLocation(source: []const u8, token: Token) SourceLocation {
    var location = SourceLocation{
        .line = 1,
        .column = 1,
        .width = token.location.end - token.location.start,
        .line_start = 0,
        .line_end = 0,
    };

    for (source, 0..) |char, index| {
        if (index == token.location.start) break;

        if (char == '\n') {
            location.line += 1;
            location.column = 1;
            location.line_start = index + 1;
        } else {
            location.column += 1;
        }
    }

    var end_index = token.location.start;
    while (end_index < source.len and source[end_index] != '\n' and source[end_index] != '\r') : (end_index += 1) {}
    location.line_end = end_index;

    return location;
}

const as = @import("as");
const ReportingModule = as.common.reporting.ReportingModule;
const Token = as.frontend.Token;

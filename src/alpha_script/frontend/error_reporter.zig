pub const ErrorType = enum {
    // from Scanner
    unexpected_character,
    unterminated_string,

    // from Parser
    expected_identifier,
    expected_type,

    // from SemanticAnalyzer
    // TODO are these two the same?
    incompatible_types,
    type_mismatch,
};

pub const ErrorReporter = struct {
    source: []const u8,
    file_name: []const u8,

    pub fn report(self: *const ErrorReporter, token: Token, errorType: ErrorType) void {}
};

const as = @import("as");
const Token = as.frontend.Token;

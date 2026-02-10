pub const ReportingModule = union(enum) {
    TokenStream: *const TokenStream,
    Parser: *const Parser,
    SemanticAnalyser: *const SemanticAnalyser,
    Compiler: *const Compiler,
    VirtualMachine: *const VirtualMachine,
};

pub const ReportedError = union {
    scanner_error: Scanner.Error,
    parser_error: Parser.Error,
    semantic_error: SemanticAnalyser.Error,
    compiler_error: Compiler.Error,
    vm_error: VirtualMachine.Error,
};

pub const SourceInfo = struct {
    file_path: ?[]const u8,
    token: Token,
};

pub const ErrorReport = struct {
    reporting_module: ReportingModule,

    reported_error: ReportedError,
    error_code: u32,
    source_info: SourceInfo,
    message: []const u8,
};

pub const ErrorReporter = struct {
    error_output: ErrorOutput, // the output, where the error is reported to (typicaly to stderr in human readable format)

    pub fn init(error_output: ErrorOutput) ErrorReporter {
        return .{
            .error_output = error_output,
        };
    }

    pub fn tokenStreamError(self: *const ErrorReporter, token_stream: *const TokenStream, err: Scanner.Error, token_start: usize, token_end: usize, message: []const u8) void {
        const reporting_module: ReportingModule = .{ .TokenStream = token_stream };

        self.error_output.reportError(.{
            .reporting_module = reporting_module,
            .reported_error = .{ .scanner_error = err },
            .error_code = self.calcErrorCode(reporting_module, @intFromError(err)),
            .source_info = .{ .file_path = token_stream.getFilePath(), .token = .{ .tag = .comptime_corrupt, .location = .{
                .start = token_start,
                .end = token_end,
            } } },
            .message = message,
        });
    }

    pub fn parserError(self: *const ErrorReporter, parser: *const Parser, err: Parser.Error, token: Token, message: []const u8) void {
        const reporting_module: ReportingModule = .{ .Parser = parser };

        self.error_output.reportError(.{
            .reporting_module = reporting_module,
            .reported_error = .{ .parser_error = err },
            .error_code = self.calcErrorCode(reporting_module, @intFromError(err)),
            .source_info = .{
                .file_path = parser.scanner.token_stream.getFilePath(),
                .token = token,
            },
            .message = message,
        });
    }

    pub fn semanticAnalyserError(self: *ErrorReporter, semantic_analyser: *const SemanticAnalyser, err: SemanticAnalyser.Error, node: Node, message: []const u8) void {
        const reporting_module: ReportingModule = .{ .SemanticAnalyser = semantic_analyser };

        self.error_output.reportError(.{
            .reporting_module = reporting_module,
            .reported_error = .{ .semantic_error = err },
            .error_code = self.calcErrorCode(reporting_module, @intFromError(err)),
            .source_info = .{
                .file_path = semantic_analyser.ast.scanner.token_stream.getFilePath(),
                .token = semantic_analyser.ast.scanner.token_stream.scanPosition(node.token_position) catch return,
            },
            .message = message,
        });
    }

    pub fn compilerError(self: *const ErrorReporter, compiler: *const Compiler, err: Compiler.Error, node: Node, message: []const u8) void {
        const reporting_module: ReportingModule = .{ .Compiler = compiler };

        var scanner: Scanner = compiler.ast.scanner.*;

        self.error_output.reportError(.{
            .reporting_module = reporting_module,
            .reported_error = .{ .compiler_error = err },
            .error_code = self.calcErrorCode(reporting_module, @intFromError(err)),
            .source_info = .{
                .file_path = compiler.ast.scanner.token_stream.getFilePath(),
                .token = scanner.token_stream.scanPosition(node.token_position) catch unreachable,
            },
            .message = message,
        });
    }

    pub fn virtualMachineError(self: *const ErrorReporter, vm: *VirtualMachine, err: VirtualMachine.Error, message: []const u8) void {
        const reporting_module: ReportingModule = .{ .VirtualMachine = vm };

        self.error_output.reportError(.{
            .reporting_module = reporting_module,
            .reported_error = .{ .vm_error = err },
            .error_code = self.calcErrorCode(reporting_module, @intFromError(err)),
            .source_info = .{
                .file_path = null,
                // TODO get a reference to the token
                .token = Token{
                    .tag = .synthetic,
                    .location = .{ .start = 0, .end = 0 },
                },
            },
            .message = message,
        });
    }

    fn buildReport(self: *const ErrorReporter, module: ReportingModule, err: ReportedError, token_start: usize, token_end: usize, message: []const u8) ErrorReport {
        return .{
            .reporting_module = module,
            .reported_error = err,
            .error_code = self.calcErrorCode(module, err),
            .source_location = self.calcSourceLocation(token_start, token_end - token_start),
            .message = message,
        };
    }

    fn calcErrorCode(_: *const ErrorReporter, module: ReportingModule, err_no: u32) u32 {
        var code: u32 = err_no * 10;
        code += @intFromEnum(module);
        return code;
    }
};

const as = @import("as");

const ErrorOutput = as.common.reporting.ErrorOutput;

const Token = as.frontend.Token;
const Node = as.frontend.ast.Node;

const Scanner = as.frontend.Scanner;
const TokenStream = as.frontend.TokenStream;
const Parser = as.frontend.Parser;
const SemanticAnalyser = as.frontend.SemanticAnalyzer;
const Compiler = as.compiler.Compiler;
const VirtualMachine = as.runtime.VirtualMachine;

/// provisional ErrorOutput to stay compatible with integration tests
pub const IntegrationTestErrorOutput = struct {
    terminal: *const Terminal,

    pub fn init(terminal: *const Terminal) IntegrationTestErrorOutput {
        return .{
            .terminal = terminal,
        };
    }

    pub fn output(self: *IntegrationTestErrorOutput) ErrorOutput {
        return .{
            .ptr = self,
            .outputFn = printError,
        };
    }

    fn printError(ptr: *anyopaque, report: ErrorReport) void {
        const self: *IntegrationTestErrorOutput = @ptrCast(@alignCast(ptr));
        const source = source_helper.sourceFromReportingModule(report.reporting_module);
        const location = source_helper.calcTokenLocation(source, report.source_info.token);
        const token = report.source_info.token;

        self.terminal.print("[line {d}] Error at '{s}': {s}\n", .{
            location.line,
            source[token.location.start..token.location.end],
            report.message,
        });
    }
};

const as = @import("as");
const ErrorOutput = as.common.reporting.ErrorOutput;
const ErrorReport = as.common.reporting.ErrorReport;
const SourceInfo = as.common.reporting.SourceInfo;
const source_helper = as.common.reporting.source_helper;
const SourceLocation = as.common.reporting.source_helper.SourceLocation;

const Terminal = as.common.Terminal;

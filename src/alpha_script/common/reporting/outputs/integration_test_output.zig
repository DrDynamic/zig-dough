/// provisional ErrorOutput to stay compatible with integration tests
pub const IntegrationTestErrorOutput = struct {
    terminal: *Terminal,

    pub fn init(terminal: *Terminal) IntegrationTestErrorOutput {
        return .{
            .terminal = terminal,
        };
    }

    pub fn output(self: *IntegrationTestErrorOutput) ErrorOutput {
        return .{
            .ptr = self,
            .errorFn = printError,
            .hintFn = printHint,
        };
    }

    fn printError(ptr: *anyopaque, report: ErrorReport) void {
        const self: *IntegrationTestErrorOutput = @ptrCast(@alignCast(ptr));
        const source = source_helper.sourceFromReportingModule(report.reporting_module);
        const location = source_helper.calcSourceLocation(source, report.source_info.location.start, report.source_info.location.end);

        self.terminal.print("[line {d}] Error at '{s}': {s}\n", .{
            location.line,
            source[report.source_info.location.start..report.source_info.location.end],
            report.message,
        });
    }

    fn printHint(_: *anyopaque, _: HintReport) void {}
};

const as = @import("as");
const ErrorOutput = as.common.reporting.ErrorOutput;
const ErrorReport = as.common.reporting.ErrorReport;
const HintReport = as.common.reporting.HintReport;
const SourceInfo = as.common.reporting.SourceInfo;
const source_helper = as.common.reporting.source_helper;
const SourceLocation = as.common.reporting.source_helper.SourceLocation;

const Terminal = as.common.Terminal;

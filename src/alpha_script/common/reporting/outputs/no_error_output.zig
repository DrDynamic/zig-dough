pub const NoErrorOutput = struct {
    pub fn output(self: *NoErrorOutput) ErrorOutput {
        return .{
            .ptr = self,
            .errorFn = *const fn (ptr: *anyopaque, report: ErrorReport) void{},
            .hintFn = *const fn (ptr: *anyopaque, report: HintReport) void{},
        };
    }
};

const as = @import("as");
const ErrorOutput = as.common.reporting.ErrorOutput;
const ErrorReport = as.common.reporting.ErrorReport;
const HintReport = as.common.reporting.HintReport;

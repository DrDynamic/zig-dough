pub const NoErrorOutput = struct {
    pub fn output(self: *NoErrorOutput) ErrorOutput {
        return .{
            .ptr = self,
            .outputFn = *const fn (ptr: *anyopaque, report: ErrorReport) void{},
        };
    }
};

const as = @import("as");
const ErrorOutput = as.common.reporting.ErrorOutput;
const ErrorReport = as.common.reporting.ErrorReport;

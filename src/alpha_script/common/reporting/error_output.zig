pub const ErrorOutput = struct {
    ptr: *anyopaque,
    outputFn: *const fn (ptr: *anyopaque, report: ErrorReport) void,

    pub fn reportError(self: *const ErrorOutput, report: ErrorReport) void {
        self.outputFn(self.ptr, report);
    }
};

const as = @import("as");
const ErrorReport = as.common.reporting.ErrorReport;

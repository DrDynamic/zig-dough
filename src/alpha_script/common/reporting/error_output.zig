pub const ErrorOutput = struct {
    ptr: *anyopaque,
    errorFn: *const fn (ptr: *anyopaque, report: ErrorReport) void,
    hintFn: *const fn (ptr: *anyopaque, report: HintReport) void,

    pub fn reportError(self: *const ErrorOutput, report: ErrorReport) void {
        self.errorFn(self.ptr, report);
    }

    pub fn reportHint(self: *const ErrorOutput, report: HintReport) void {
        self.hintFn(self.ptr, report);
    }
};

const as = @import("as");
const ErrorReport = as.common.reporting.ErrorReport;
const HintReport = as.common.reporting.HintReport;

const location_label_options: Terminal.PrintOptions = .{
    .styles = &.{Terminal.Style.bold},
};

const error_label_options: Terminal.PrintOptions = .{
    .color = .{ .ansi = .red },
    .styles = &.{.bold},
};

const marker_options: Terminal.PrintOptions = .{
    .color = .{ .ansi = .green },
};

pub const PrettyErrorOutput = struct {
    terminal: *const Terminal,

    pub fn init(terminal: *const Terminal) PrettyErrorOutput {
        return .{
            .terminal = terminal,
        };
    }

    pub fn output(self: *PrettyErrorOutput) ErrorOutput {
        return .{
            .ptr = self,
            .outputFn = printError,
        };
    }

    fn printError(ptr: *anyopaque, report: ErrorReport) void {
        const self: *PrettyErrorOutput = @ptrCast(@alignCast(ptr));
        const source = source_helper.sourceFromReportingModule(report.reporting_module);
        const location = source_helper.calcSourceLocation(source, report.source_info.token);

        self.printMessage(report.error_code, report.source_info, location, report.message);
        self.printMarkedSource(source, location);
    }

    fn printMarkedSource(self: *const PrettyErrorOutput, source: []const u8, location: SourceLocation) void {
        // print source
        const source_line = source[location.line_start..location.line_end];
        self.terminal.print("{s}\n", .{source_line});

        // print marker (^~~~)
        self.terminal.setStyle(marker_options);
        for (0..location.column - 1) |_| self.terminal.print(" ", .{});
        self.terminal.print("{s}", .{"^"});
        for (0..location.width - 1) |_| self.terminal.print("~", .{});
        self.terminal.printWithOptions("\n", .{}, Terminal.reset_options);
    }

    fn printMessage(self: *const PrettyErrorOutput, error_code: u32, source_info: SourceInfo, location: SourceLocation, message: []const u8) void {
        self.terminal.printWithOptions("{?s}:{d}:{d} ", .{ source_info.file_path, location.line, location.column }, location_label_options);
        self.terminal.printWithOptions("error[{d}]: ", .{error_code}, error_label_options);
        self.terminal.printWithOptions("{s}\n", .{message}, location_label_options);
        self.terminal.setStyle(Terminal.reset_options);
    }
};

const as = @import("as");
const ErrorOutput = as.common.reporting.ErrorOutput;
const ErrorReport = as.common.reporting.ErrorReport;
const SourceInfo = as.common.reporting.SourceInfo;
const source_helper = as.common.reporting.source_helper;
const SourceLocation = as.common.reporting.source_helper.SourceLocation;

const Terminal = as.common.Terminal;

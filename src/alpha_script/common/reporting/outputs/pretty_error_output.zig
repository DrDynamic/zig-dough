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
            .errorFn = printError,
            .hintFn = printHint,
        };
    }

    fn printError(ptr: *anyopaque, report: ErrorReport) void {
        const self: *PrettyErrorOutput = @ptrCast(@alignCast(ptr));

        const source = source_helper.sourceFromReportingModule(report.reporting_module);
        const location = self.getSourceLocation(source, report.reporting_module, report.source_info);

        self.printErrorMessage(report.error_code, report.source_info, location, report.message);
        self.printMarkedSource(source, location);
    }

    fn printHint(ptr: *anyopaque, report: HintReport) void {
        const self: *PrettyErrorOutput = @ptrCast(@alignCast(ptr));

        if (report.source_info) |source_info| {
            const source = source_helper.sourceFromReportingModule(report.reporting_module);
            const location = self.getSourceLocation(source, report.reporting_module, source_info);

            self.printHintMessage(source_info, location, report.message);
            self.printMarkedSource(source, location);
        } else {
            self.printHintMessage(null, null, report.message);
        }
    }

    fn getSourceLocation(self: *const PrettyErrorOutput, source: []const u8, reporting_module: ReportingModule, source_info: SourceInfo) SourceLocation {
        _ = self;

        var location: SourceLocation = undefined;
        if (source_info.node) |node| {
            const ast = source_helper.astFromReportingModule(reporting_module);
            location = source_helper.calcNodeLocation(source, node, ast.?) catch
                source_helper.calcTokenLocation(source, source_info.token);
        } else {
            location = source_helper.calcTokenLocation(source, source_info.token);
        }

        return location;
    }

    fn printErrorMessage(self: *const PrettyErrorOutput, error_code: u32, source_info: SourceInfo, location: SourceLocation, message: []const u8) void {
        self.terminal.printWithOptions("{?s}:{d}:{d} ", .{ source_info.file_path, location.line, location.column }, location_label_options);
        self.terminal.printWithOptions("error[{d}]: ", .{error_code}, error_label_options);
        self.terminal.printWithOptions("{s}\n", .{message}, location_label_options);
        self.terminal.setStyle(Terminal.reset_options);
    }

    fn printHintMessage(self: *const PrettyErrorOutput, maybe_source_info: ?SourceInfo, location: ?SourceLocation, message: []const u8) void {
        if (maybe_source_info) |source_info| {
            self.terminal.printWithOptions("{?s}:{d}:{d} ", .{ source_info.file_path, location.?.line, location.?.column }, location_label_options);
        }
        self.terminal.printWithOptions("note: ", .{}, error_label_options);
        self.terminal.printWithOptions("{s}\n", .{message}, location_label_options);
        self.terminal.setStyle(Terminal.reset_options);
    }

    fn printMarkedSource(self: *const PrettyErrorOutput, source: []const u8, location: SourceLocation) void {
        // print source
        const source_line = source[location.line_start..location.line_end];
        self.terminal.print("{s}\n", .{source_line});

        // print marker (^~~~)
        self.terminal.setStyle(marker_options);
        for (1..location.marker_end) |index| {
            if (index < location.marker_start) {
                self.terminal.print(" ", .{});
            } else if (index == location.column) {
                self.terminal.print("^", .{});
            } else {
                self.terminal.print("~", .{});
            }
        }
        self.terminal.printWithOptions("\n", .{}, Terminal.reset_options);
    }
};

const as = @import("as");
const ErrorOutput = as.common.reporting.ErrorOutput;
const ErrorReport = as.common.reporting.ErrorReport;
const HintReport = as.common.reporting.HintReport;
const ReportingModule = as.common.reporting.ReportingModule;
const SourceInfo = as.common.reporting.SourceInfo;
const source_helper = as.common.reporting.source_helper;
const SourceLocation = as.common.reporting.source_helper.SourceLocation;

const Terminal = as.common.Terminal;

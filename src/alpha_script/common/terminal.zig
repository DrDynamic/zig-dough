pub const Terminal = struct {
    pub const Style = enum(u32) {
        reset = 0,
        bold = 1,
        faint = 2,
        italic = 3,
        underline = 4,
        slow_blink = 5,
        rapid_blink = 6,
        invert = 7,
        //        hide =8, // not widely supported
        crossed_out = 9,
    };

    pub const AnsiColor = enum(u32) {
        reset = 0,
        black = 30,
        red,
        green,
        yellow,
        blue,
        magenta,
        cyan,
        white,
        brightBlack = 90,
        brightRed,
        brightGreen,
        brightYellow,
        brightBlue,
        brightMagenta,
        brightCyan,
        brightWhite,
    };

    pub const RGBColor = struct {
        r: u8,
        g: u8,
        b: u8,
    };

    pub const Color = union(enum) {
        ansi: AnsiColor,
        rgb: RGBColor,
    };

    pub const PrintOptions = struct {
        color: ?Color = null,
        background: ?Color = null,
        styles: []const Style = &.{},
    };

    pub const reset_options: PrintOptions = .{
        .color = .{ .ansi = .reset },
        .background = null,
        .styles = &.{},
    };

    supports_color: bool,
    writer: std.fs.File.Writer,

    pub fn init(io: std.fs.File) Terminal {
        return .{
            .supports_color = io.isTty(),
            .writer = io.writer(),
        };
    }

    pub fn print(self: *const Terminal, comptime fmt: []const u8, args: anytype) void {
        self.writer.print(fmt, args) catch {};
    }

    pub fn printWithOptions(self: *const Terminal, comptime fmt: []const u8, args: anytype, options: PrintOptions) void {
        if (self.supports_color) {
            printOptions(self.writer, options) catch {};
        }

        self.writer.print(fmt, args) catch {};

        if (self.supports_color) {
            printReset(self.writer) catch {};
        }
    }

    pub fn setStyle(self: *const Terminal, options: PrintOptions) void {
        if (self.supports_color) {
            printOptions(self.writer, options) catch {};
        }
    }

    // private

    fn printReset(writer: std.fs.File.Writer) !void {
        try writer.print("\x1b[0m", .{});
    }

    fn printOptions(writer: std.fs.File.Writer, options: PrintOptions) !void {
        try writer.print("\x1b[", .{});

        if (options.color) |color| {
            switch (color) {
                .ansi => |c| try writer.print("{d}", .{@intFromEnum(c)}),
                .rgb => |c| try writer.print("38;2;{d};{d};{d}", .{ c.r, c.g, c.b }),
            }
        }

        if (options.background) |color| {
            switch (color) {
                .ansi => |c| try writer.print(";{d}", .{@intFromEnum(c)}),
                .rgb => |c| try writer.print("48;2;{d};{d};{d}", .{ c.r, c.g, c.b }),
            }
        }

        for (options.styles) |style| {
            try writer.print(";{d}", .{@intFromEnum(style)});
        }

        try writer.print("m", .{});
    }
};

const std = @import("std");

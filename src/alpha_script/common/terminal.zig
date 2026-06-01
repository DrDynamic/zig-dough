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

    allocator: std.mem.Allocator,
    supports_color: bool,
    io: std.fs.File.Writer,
    writer: *std.io.Writer,
    buffer: [4096]u8,

    pub fn init(io: std.fs.File, allocator: std.mem.Allocator) std.mem.Allocator.Error!*Terminal {
        var terminal = try allocator.create(Terminal);
        terminal.allocator = allocator;
        terminal.supports_color = io.isTty();
        terminal.io = io.writer(&terminal.buffer);
        terminal.writer = &terminal.io.interface;

        //std.debug.print("---------- init ----------\n", .{});
        //std.debug.print("io: {p}\n", .{&terminal.io});
        //std.debug.print("writer: {p}\n", .{&terminal.writer});

        return terminal;
    }

    pub fn deinit(self: *Terminal) void {
        self.allocator.destroy(self);
    }

    pub fn print(self: *Terminal, comptime fmt: []const u8, args: anytype) void {
        //std.debug.print("---------- pre print ----------\n", .{});
        //std.debug.print("io: {p}\n", .{&self.io});
        //std.debug.print("writer: {p}\n", .{&self.writer});

        self.writer.print(fmt, args) catch @panic("WriteFailed");
        //std.debug.print("---------- post print ----------\n", .{});
        //std.debug.print("io: {p}\n", .{&self.io});
        //std.debug.print("writer: {p}\n", .{&self.writer});

        self.writer.flush() catch @panic("WriteFailed");
    }

    pub fn printWithOptions(self: *Terminal, comptime fmt: []const u8, args: anytype, options: PrintOptions) void {
        if (self.supports_color) {
            printOptions(self.writer, options) catch @panic("WriteFailed");
        }

        self.writer.print(fmt, args) catch @panic("WriteFailed");

        if (self.supports_color) {
            printReset(self.writer) catch @panic("WriteFailed");
        }
        self.writer.flush() catch @panic("WriteFailed");
    }

    pub fn setStyle(self: *Terminal, options: PrintOptions) void {
        if (self.supports_color) {
            printOptions(self.writer, options) catch @panic("WriteFailed");
        }
    }

    // private

    fn printReset(writer: *std.io.Writer) std.io.Writer.Error!void {
        try writer.print("\x1b[0m", .{});
    }

    fn printOptions(writer: *std.io.Writer, options: PrintOptions) std.io.Writer.Error!void {
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

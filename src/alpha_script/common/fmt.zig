pub fn fmt(T: type) type {
    const PadOptions = struct {
        data: T,
        width: u8,
        padding_char: u8 = ' ',

        fn format_pad_right(self: @This(), writer: *std.io.Writer) error{WriteFailed}!void {
            var buffer: [255]u8 = undefined;
            const value = std.fmt.bufPrint(&buffer, "{f}", .{self.data}) catch return error.WriteFailed;

            var result = buffer[0..self.width];
            if (value.len > self.width) {
                // shorten the result
                result[self.width - 1] = '.';
                result[self.width - 2] = '.';
                result[self.width - 3] = '.';
            } else {
                for (value.len..self.width) |index| {
                    result[index] = self.padding_char;
                }
            }

            try writer.print("{s}", .{result});
        }
    };

    return struct {
        pub fn padRight(data: T, width: u8) std.fmt.Alt(PadOptions, PadOptions.format_pad_right) {
            return .{ .data = .{ .data = data, .width = width } };
        }
        pub fn padRightChar(data: T, width: u8, char: u8) std.fmt.Alt(PadOptions, PadOptions.format_pad_right) {
            return .{ .data = .{ .data = data, .width = width, .padding_char = char } };
        }
    };
}

const std = @import("std");

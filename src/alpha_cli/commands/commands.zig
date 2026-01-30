pub const Command = union(enum) {
    run: RunCommand.Options,
    help: void,

    pub fn fromArgs(args: [][:0]u8) Command {
        if (args.len < 2) return error.MissingCommand;

        const cmd_name = args[1];

        if (RunCommand.shouldRun(cmd_name)) {
            return .{ .run = RunCommand.buildOptions(args[1..]) };
        } else {
            return .{.help};
        }
    }

    pub fn run() !void {}
};

const std = @import("std");
const RunCommand = @import("./run_command.zig").RunCommand;

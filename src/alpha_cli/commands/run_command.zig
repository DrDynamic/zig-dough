pub const RunCommand = struct {
    pub const Options = struct {
        script_path: []const u8,
        print_tokens: bool,
        print_ast: bool,
        print_asm: bool,
    };

    pub fn shouldRun(command_arg: []const u8) bool {
        return std.mem.eql(u8, command_arg, "run");
    }

    pub fn buildOptions(args: [][]u8) !Options {
        if (args.len < 1) {
            return error.MissinArgument;
        }

        var options: Options = .{
            .script_path = args[0],
            .print_ast = false,
            .print_asm = false,
        };

        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--print-tokens")) {
                options.print_tokens = true;
            } else if (std.mem.eql(u8, arg, "--print-ast")) {
                options.print_ast = true;
            } else if (std.mem.eql(u8, arg, "--print-asm")) {
                options.print_asm = true;
            }
        }

        return options;
    }
};

const std = @import("std");

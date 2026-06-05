const EXIT_CODE_COMPILER_ERROR = 65; // EX_DATAERR
const EXIT_CODE_RUNTIME_ERROR = 70; // EX_SOFTWARE

const StartOptions = struct {
    path: ?[]const u8,
    print_tokens: bool,
    print_ast: bool,
    print_asm: bool,
    debug_vm: bool,
    error_output: OutputType,
};

const OutputType = enum {
    pretty,
    integration_test,
};

fn makeStartOptions(iterator: *std.process.ArgIterator) !StartOptions {
    var options: StartOptions = .{
        .path = null,
        .print_tokens = false,
        .print_ast = false,
        .print_asm = false,
        .debug_vm = false,
        .error_output = .pretty,
    };

    // Skip executable
    _ = iterator.next();

    while (iterator.next()) |arg| {
        if (arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--print-tokens")) {
                options.print_tokens = true;
            } else if (std.mem.eql(u8, arg, "--print-ast")) {
                options.print_ast = true;
            } else if (std.mem.eql(u8, arg, "--print-asm")) {
                options.print_asm = true;
            } else if (std.mem.eql(u8, arg, "--debug-vm")) {
                options.debug_vm = true;
            } else if (std.mem.eql(u8, arg, "--errors=test")) {
                options.error_output = .integration_test;
            } else {
                return error.UnknownOption;
            }
        } else {
            options.path = arg;
        }
    }

    return options;
}

fn getFile(path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const source = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    return source;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const stdout_terminal = try as.common.Terminal.init(std.fs.File.stdout(), allocator);
    defer stdout_terminal.deinit();
    const stderr_terminal = try as.common.Terminal.init(std.fs.File.stderr(), allocator);
    defer stderr_terminal.deinit();

    var argsIterator = try std.process.ArgIterator.initWithAllocator(allocator);
    defer argsIterator.deinit();

    const start_options = try makeStartOptions(&argsIterator);

    if (start_options.path) |path| {
        const output: as.common.reporting.ErrorOutput = switch (start_options.error_output) {
            .pretty => case: {
                var pretty_output = as.common.reporting.outputs.PrettyErrorOutput.init(stderr_terminal);
                break :case pretty_output.output();
            },
            .integration_test => case: {
                var pretty_output = as.common.reporting.outputs.IntegrationTestErrorOutput.init(stderr_terminal);
                break :case pretty_output.output();
            },
        };

        const error_reporter = as.common.reporting.ErrorReporter.init(output);
        var interpreter = try as.Interpreter.init(error_reporter, allocator);
        defer interpreter.deinit();

        try interpreter.registerBuildinFunction(.{
            .name_id = try interpreter.string_table.add("print"),
            .parameter_type_ids = &[_]as.frontend.TypeId{
                as.frontend.TypePool.ANY,
            },
            .return_type_id = as.frontend.TypePool.VOID,
            .function = as.runtime.values.natives.nativePrint,
        });

        const module = interpreter.compileModule(path, .{
            .terminal = stdout_terminal,
            .print_tokens = start_options.print_tokens,
            .print_ast = start_options.print_ast,
        }) catch {
            std.process.exit(EXIT_CODE_COMPILER_ERROR);
        };

        if (start_options.print_asm) {
            var disassambler = as.frontend.debug.Disassambler.init(stdout_terminal);
            disassambler.disassambleChunk(&module.function.chunk, "root");

            for (module.function.chunk.constants.items) |constant| {
                if (constant.isObject()) {
                    if (constant.toObject().is(.function)) {
                        const function = constant.toObject().as(as.runtime.values.ObjFunction);
                        disassambler.disassambleChunk(&function.chunk, if (function.name) |name| name.data else "anonymous");
                    }
                }
            }
        }

        if (start_options.print_tokens or start_options.print_ast or start_options.print_asm) {
            return;
        }

        if (start_options.debug_vm) {
            interpreter.runModule(module, true) catch |err| {
                std.debug.panic("{t}", .{err});
                std.process.exit(EXIT_CODE_RUNTIME_ERROR);
            };
        } else {
            interpreter.runModule(module, false) catch |err| {
                std.debug.panic("{t}", .{err});
                std.process.exit(EXIT_CODE_RUNTIME_ERROR);
            };
        }
    } else {
        stderr_terminal.print("no file specified!\n", .{});
    }
}

const std = @import("std");
const as = @import("as");
const commands = @import("./commands/commands.zig");

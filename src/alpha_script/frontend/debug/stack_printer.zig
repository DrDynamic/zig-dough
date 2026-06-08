const register_style: Terminal.PrintOptions = .{
    .styles = &.{.faint},
};
const register_mutated_style: Terminal.PrintOptions = .{
    .color = .{ .ansi = .red },
};
const register_read_style: Terminal.PrintOptions = .{
    .color = .{ .ansi = .blue },
};

pub const StackPrinter = struct {
    terminal: *Terminal,
    disassambler: Disassambler,
    stack: []Value,
    frames: []CallFrame,
    frame_count: *usize,

    pub fn init(terminal: *Terminal, stack: []Value, frames: []CallFrame, frame_count: *usize) StackPrinter {
        return .{
            .terminal = terminal,
            .disassambler = Disassambler.init(terminal),
            .stack = stack,
            .frames = frames,
            .frame_count = frame_count,
        };
    }

    fn printCallframe(self: *StackPrinter, terminal: *Terminal, register: usize, used_frame_count: usize, color: ?Terminal.Color) void {
        const frame_style: as.common.Terminal.PrintOptions = .{
            .color = color,
            .styles = &.{.faint},
        };

        const active_frame_style: as.common.Terminal.PrintOptions = .{
            .color = color,
        };

        var style: as.common.Terminal.PrintOptions = undefined;
        for (0.., self.frames[0..used_frame_count]) |index, frame| {
            const reg_frame_start = frame.base_pointer;
            const reg_frame_end = frame.base_pointer + (frame.function.max_registers -| 1);

            style = if (index == used_frame_count - 1)
                active_frame_style
            else
                frame_style;

            if (register == frame.base_pointer) {
                const local_address = register - frame.base_pointer;

                // start of callframe ┐
                terminal.printWithOptions(" {d:0>2}┐", .{local_address}, style);
            } else if (register > reg_frame_start and register < reg_frame_end) {
                const local_address = register - frame.base_pointer;

                // inside callframe   │
                terminal.printWithOptions(" {d:0>2}│", .{local_address}, style);
            } else if (register == reg_frame_end) {
                const local_address = register - frame.base_pointer;

                // end of callframe   ┘
                terminal.printWithOptions(" {d:0>2}┘", .{local_address}, style);
            } else {
                // outside of callframe
                terminal.printWithOptions("    ", .{}, style);
            }
        }
    }

    pub fn printStack(self: *StackPrinter, used_stack_top: usize, used_frame_count: usize, used_frame: *const CallFrame) void {
        const stack = self.stack;

        const chunk = used_frame.function.chunk;
        var instruction = chunk.code.items[used_frame.ip - 1];
        var instruction_extra: ?Instruction = null;
        const current_frame = self.frames[self.frame_count.* - 1];

        var description: InstructionDescription = undefined;
        var description_extra: ?InstructionDescription = null;

        var ip: usize = used_frame.ip - 1;
        var ip_extra: ?usize = null;

        if (instruction.ab.opcode == .op_call_args) {
            ip = used_frame.ip - 2;
            ip_extra = used_frame.ip - 1;

            instruction = chunk.code.items[ip];
            instruction_extra = chunk.code.items[ip_extra.?];
        }

        description = self.disassambler.disassambleInstruction(&chunk, instruction, ip);
        if (instruction_extra) |extra| {
            description_extra = self.disassambler.disassambleInstruction(&chunk, extra, ip_extra.?);
        }

        for (stack[0..used_stack_top], 0..) |value, register| {
            const local_address = if (register >= used_frame.base_pointer)
                register - used_frame.base_pointer
            else
                std.math.maxInt(usize);

            const mutate_a = description.parameter_type_a == .mutate_register_id and instruction.abc.a == local_address;
            const mutate_b = description.parameter_type_b == .mutate_register_id and instruction.abc.b == local_address;
            const mutate_c = description.parameter_type_c == .mutate_register_id and instruction.abc.c == local_address;
            const is_register_mutated = mutate_a or mutate_b or mutate_c;

            const read_a = description.parameter_type_a == .register_id and instruction.abc.a == local_address;
            const read_b = description.parameter_type_b == .register_id and instruction.abc.b == local_address;
            const read_c = description.parameter_type_c == .register_id and instruction.abc.c == local_address;
            const is_register_read = read_a or read_b or read_c;

            var call_callee: bool = false;
            var call_arg: bool = false;
            var call_return: bool = false;
            if (instruction.abc.opcode == .op_call) {
                call_callee = instruction.abc.b == local_address;

                const arg_index = if (instruction_extra) |extra| extra.ab.b else 0;
                const arg_count = if (instruction_extra) |extra| extra.ab.a else 0;

                call_arg = is_arg: for (chunk.arguments.items[arg_index .. arg_index + arg_count]) |reg_arg| {
                    if (local_address == reg_arg) {
                        break :is_arg true;
                    }
                } else false;

                if (register > current_frame.base_pointer and register - current_frame.base_pointer == instruction.abc.a) {
                    call_return = true;
                }
            }

            const style = if (call_callee)
                register_read_style
            else if (call_arg)
                as.common.Terminal.PrintOptions{ .color = .{ .ansi = .brightCyan } }
            else if (call_return)
                register_mutated_style
            else if (is_register_mutated)
                register_mutated_style
            else if (is_register_read)
                register_read_style
            else
                register_style;

            self.terminal.printWithOptions("{d:0>4}: ", .{register}, style);
            self.terminal.printWithOptions("[{f}]", .{as.common.fmt(as.runtime.values.UnionValue).padRightChar(value, 35, '_')}, style);

            self.printCallframe(self.terminal, register, used_frame_count, style.color);

            self.terminal.print("\n", .{});
        }
        self.terminal.print("\n", .{});
    }
};

const std = @import("std");
const as = @import("as");

const CallFrame = as.runtime.CallFrame;
const Disassambler = as.frontend.debug.Disassambler;
const Instruction = as.compiler.Instruction;
const InstructionDescription = as.frontend.debug.InstructionDescription;
const RegisterId = as.runtime.RegisterId;
const Terminal = as.common.Terminal;
const Value = as.runtime.values.Value;
const VirtualMachine = as.runtime.VirtualMachine;

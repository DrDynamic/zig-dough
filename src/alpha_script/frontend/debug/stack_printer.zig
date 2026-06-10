const register_style_default: Terminal.PrintOptions = .{
    .styles = &.{.faint},
};
const register_style_mutated: Terminal.PrintOptions = .{
    .color = .{ .ansi = .red },
};
const register_style_read: Terminal.PrintOptions = .{
    .color = .{ .ansi = .blue },
};
const register_style_arg: Terminal.PrintOptions = .{
    .color = .{ .ansi = .brightCyan },
};

const InstrictionInfo = struct {
    instruction: Instruction,
    description: InstructionDescription,
    instruction_extra: ?Instruction,
    description_extra: ?InstructionDescription,

    pub fn init(disassambler: *Disassambler, used_frame: *const CallFrame) InstrictionInfo {
        const chunk = used_frame.function.chunk;
        const code = used_frame.function.chunk.code.items;

        var ip: usize = used_frame.ip - 1;
        var ip_extra: ?usize = null;

        var info: InstrictionInfo = .{
            .instruction = code[ip],
            .description = undefined,
            .instruction_extra = null,
            .description_extra = null,
        };

        if (info.instruction.ab.opcode == .op_call_args) {
            ip = used_frame.ip - 2;
            ip_extra = used_frame.ip - 1;

            info.instruction = code[ip];
            info.instruction_extra = code[ip_extra.?];
        }

        info.description = disassambler.disassambleInstruction(&chunk, info.instruction, ip);
        if (info.instruction_extra) |instruction_extra| {
            info.description_extra = disassambler.disassambleInstruction(&chunk, instruction_extra, ip_extra.?);
        }

        return info;
    }

    pub fn mutatesRegister(self: *const InstrictionInfo, local_address: usize) bool {
        const mutate_a = self.description.parameter_type_a == .mutate_register_id and self.instruction.abc.a == local_address;
        const mutate_b = self.description.parameter_type_b == .mutate_register_id and self.instruction.abc.b == local_address;
        const mutate_c = self.description.parameter_type_c == .mutate_register_id and self.instruction.abc.c == local_address;
        return mutate_a or mutate_b or mutate_c;
    }

    pub fn readsRegister(self: *const InstrictionInfo, local_address: usize) bool {
        const read_a = self.description.parameter_type_a == .register_id and self.instruction.abc.a == local_address;
        const read_b = self.description.parameter_type_b == .register_id and self.instruction.abc.b == local_address;
        const read_c = self.description.parameter_type_c == .register_id and self.instruction.abc.c == local_address;
        return read_a or read_b or read_c;
    }

    pub fn isCallee(self: *const InstrictionInfo, local_address: usize) bool {
        if (self.instruction.abc.opcode == .op_call) {
            return self.instruction.abc.b == local_address;
        }
        return false;
    }

    pub fn isCallArg(self: *const InstrictionInfo, local_address: usize, argument_list: []const RegisterId) bool {
        if (self.instruction.abc.opcode == .op_call) {
            const arg_index = if (self.instruction_extra) |extra| extra.ab.b else 0;
            const arg_count = if (self.instruction_extra) |extra| extra.ab.a else 0;

            return is_arg: for (argument_list[arg_index .. arg_index + arg_count]) |reg_arg| {
                if (local_address == reg_arg) {
                    break :is_arg true;
                }
            } else false;
        }
        return false;
    }

    pub fn isCallReturn(self: *const InstrictionInfo, register: usize, current_frame: *const CallFrame) bool {
        if (self.instruction.abc.opcode == .op_call) {
            if (register > current_frame.base_pointer and register - current_frame.base_pointer == self.instruction.abc.a) {
                return true;
            }
        }
        return false;
    }

    pub fn operatesOnUpvalues(self: *const InstrictionInfo) bool {
        return switch (self.instruction.abc.opcode) {
            .close_upvalue, .store_upvalue, .load_upvalue => true,
            else => false,
        };
    }
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

    pub fn printStack(self: *StackPrinter, used_stack_top: usize, used_frame_count: usize, used_frame: *const CallFrame) void {
        const current_frame = &self.frames[self.frame_count.* - 1];

        const instruction_info = InstrictionInfo.init(&self.disassambler, used_frame);

        for (self.stack[0..used_stack_top], 0..) |value, register| {
            const register_style = self.resolveRegisterStyle(register, used_frame, current_frame, instruction_info);

            self.printRegister(register, value, register_style);
            self.printCallframe(self.terminal, register, used_frame_count, register_style.color);

            if (instruction_info.operatesOnUpvalues()) {
                const upvalue_style = self.resolveUpValueStyle(instruction_info, used_frame, register);

                self.terminal.print(" │ ", .{});

                self.printUpvalue(register, used_frame, upvalue_style);
            }

            self.terminal.print("\n", .{});
        }
        self.terminal.print("\n", .{});
    }

    fn resolveRegisterStyle(self: *StackPrinter, register: usize, used_frame: *const CallFrame, current_frame: *const CallFrame, instruction_info: InstrictionInfo) Terminal.PrintOptions {
        _ = self;
        const local_address: usize = if (register >= used_frame.base_pointer)
            register - used_frame.base_pointer
        else
            std.math.maxInt(usize);

        const is_register_mutated = instruction_info.mutatesRegister(local_address);
        const is_register_read = instruction_info.readsRegister(local_address);

        const call_callee: bool = instruction_info.isCallee(local_address);
        const call_arg: bool = instruction_info.isCallArg(local_address, used_frame.function.chunk.arguments.items);
        const call_return: bool = instruction_info.isCallReturn(register, current_frame);

        return if (call_callee)
            register_style_read
        else if (call_arg)
            register_style_arg
        else if (call_return)
            register_style_mutated
        else if (is_register_mutated)
            register_style_mutated
        else if (is_register_read)
            register_style_read
        else
            register_style_default;
    }

    fn resolveUpValueStyle(self: *StackPrinter, instruction_info: InstrictionInfo, used_frame: *const CallFrame, index: usize) Terminal.PrintOptions {
        const upvalues = used_frame.closure.?.upvalues;
        return switch (instruction_info.instruction.abc.opcode) {
            .close_upvalue => case: {
                // get the upvalue index of the given register
                const reg = instruction_info.instruction.abc.b;
                const value = &self.stack[reg];
                const close_index = search: for (upvalues, 0..) |upvalue, i| {
                    if (upvalue.?.location == value) {
                        break :search i;
                    }
                } else 255;

                break :case if (index >= close_index)
                    register_style_mutated
                else
                    register_style_default;
            },
            .load_upvalue => case: {
                break :case if (index == instruction_info.instruction.ab.b)
                    register_style_read
                else
                    register_style_default;
            },
            .store_upvalue => case: {
                break :case if (index == instruction_info.instruction.ab.b)
                    register_style_mutated
                else
                    register_style_default;
            },
            else => register_style_default,
        };
    }

    fn printRegister(self: *StackPrinter, register: usize, value: Value, style: Terminal.PrintOptions) void {
        self.terminal.printWithOptions("{d:0>4}: ", .{register}, style);
        self.terminal.printWithOptions("[{f}]", .{as.common.fmt(Value).padRightChar(value, 30, '_')}, style);
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

    fn printUpvalue(self: *StackPrinter, index: usize, frame: *const CallFrame, style: Terminal.PrintOptions) void {
        if (frame.closure) |closure| {
            if (index < closure.upvalues.len) {
                const value = closure.upvalues[index].?.location.*;
                self.terminal.printWithOptions("[{f}]", .{as.common.fmt(as.runtime.values.UnionValue).padRightChar(value, 30, '_')}, style);
            } else {
                self.terminal.print("{s: >30}", .{""});
            }
        }
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

const FRAMES_MAX = 128;
const STACK_MAX = FRAMES_MAX * 256;

pub const RegisterId = u8;

pub const ExecutionContext = struct {
    string_table: *const StringTable,
    error_pool: *const ErrorPool,
};

pub const CallFrame = struct {
    closure: ?*ObjClosure,
    function: *ObjFunction,
    ip: usize,
    base_pointer: usize,
    reg_return: RegisterId, // id of the register in the calling CallFrame
};

pub const VirtualMachine = struct {
    pub const Error = error{
        ArgumentCount,
        StackOverflow,
    };

    allocator: std.mem.Allocator,
    garbage_collector: *GarbageCollector,
    error_reporter: *const ErrorReporter,

    frames: [FRAMES_MAX]CallFrame,
    frame_count: usize,

    stack: [STACK_MAX]Value,
    stack_top: usize,

    open_upvalues: ?*ObjUpValue,

    current_module: ?*ObjModule,

    string_table: *StringTable,
    error_pool: *ErrorPool,
    execution_context: ExecutionContext,

    pub fn init(string_table: *StringTable, error_pool: *ErrorPool, error_reporter: *const ErrorReporter, garbage_collector: *GarbageCollector, allocator: std.mem.Allocator) VirtualMachine {
        return .{
            .allocator = allocator,
            .garbage_collector = garbage_collector,
            .error_reporter = error_reporter,

            .frames = undefined,
            .frame_count = 0,

            .stack = undefined,
            .stack_top = 0,

            .open_upvalues = null,

            .current_module = null,

            .string_table = string_table,
            .error_pool = error_pool,
            .execution_context = undefined,
        };
    }

    pub fn execute(self: *VirtualMachine, module: *ObjModule, buildin_functions: []BuildinFunction) !void {
        self.current_module = module;
        for (buildin_functions) |buildin| {
            const native_obj = as.runtime.values.ObjNative.init(buildin.name_id, buildin.function, self.garbage_collector);

            self.stack[self.stack_top] = as.runtime.values.Value.fromObject(&native_obj.header);
            self.stack_top += 1;
        }

        self.execution_context = .{
            .string_table = self.string_table,
            .error_pool = self.error_pool,
        };

        if (true) {
            for (1..255) |index| {
                self.stack[index] = Value.makeNull();
            }
        }

        _ = try self.callFunction(module.function, 0, 0);
        try self.run();
    }

    fn printCallframe(self: *const VirtualMachine, terminal: *as.common.Terminal, register: usize, used_frame_count: usize, color: ?as.common.Terminal.Color) void {
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
            const reg_frame_end = frame.base_pointer + (frame.function.max_registers - 1);

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

    fn printStack(self: *const VirtualMachine, disassambler: *as.frontend.debug.Disassambler, used_tack_top: usize, used_frame_count: usize, used_frame: *const CallFrame) void {
        const Terminal = as.common.Terminal;

        const register_style: Terminal.PrintOptions = .{
            .styles = &.{.faint},
        };
        const register_mutated_style: Terminal.PrintOptions = .{
            .color = .{ .ansi = .red },
        };
        const register_read_style: Terminal.PrintOptions = .{
            .color = .{ .ansi = .blue },
        };

        const stack = self.stack;

        const chunk = used_frame.function.chunk;
        const instruction = chunk.code.items[used_frame.ip - 1];
        const current_frame = self.frames[self.frame_count - 1];

        const description = disassambler.disassambleInstruction(&chunk, instruction, used_frame.ip - 1);

        for (stack[0..used_tack_top], 0..) |value, register| {
            const local_address = if (register >= used_frame.base_pointer)
                register - used_frame.base_pointer
            else
                std.math.maxInt(usize);

            const mutate_a = description.parameter_type_a == .mutate_register_id and instruction.abc.a == local_address;
            const mutate_b = description.parameter_type_b == .mutate_register_id and instruction.abc.b == local_address;
            const mutate_c = description.parameter_type_c == .mutate_register_id and instruction.abc.c == local_address;

            const read_a = description.parameter_type_a == .register_id and instruction.abc.a == local_address;
            const read_b = description.parameter_type_b == .register_id and instruction.abc.b == local_address;
            const read_c = description.parameter_type_c == .register_id and instruction.abc.c == local_address;

            const call_callee = instruction.ab.opcode == as.compiler.OpCode.call and instruction.abc.b == local_address;
            const call_args = instruction.ab.opcode == as.compiler.OpCode.call and local_address > instruction.abc.b and local_address <= instruction.abc.b + instruction.abc.c;

            const call_return = instruction.ab.opcode == as.compiler.OpCode.call_return and register > current_frame.base_pointer and used_frame.reg_return == register - current_frame.base_pointer;

            const style = if (call_callee)
                register_read_style
            else if (call_args)
                as.common.Terminal.PrintOptions{ .color = .{ .ansi = .brightCyan } }
            else if (call_return)
                register_mutated_style
            else if (mutate_a or mutate_b or mutate_c)
                register_mutated_style
            else if (read_a or read_b or read_c)
                register_read_style
            else
                register_style;

            disassambler.terminal.printWithOptions("{d:0>4}: ", .{register}, style);
            disassambler.terminal.printWithOptions("[{f}]", .{as.common.fmt(as.runtime.values.UnionValue).padRightChar(value, 35, '_')}, style);

            self.printCallframe(disassambler.terminal, register, used_frame_count, style.color);

            disassambler.terminal.print("\n", .{});
        }
        disassambler.terminal.print("\n", .{});
    }

    fn run(self: *VirtualMachine) !void {
        const debug: bool = true;

        var current_frame = &self.frames[self.frame_count - 1];

        var used_stack_top: usize = undefined;
        var used_frame_count: usize = undefined;
        var used_frame: *CallFrame = undefined;

        var chunk = current_frame.function.chunk;
        var code = chunk.code.items;
        var stack = &self.stack;
        var base = current_frame.base_pointer;

        const terminal = try as.common.Terminal.init(std.fs.File.stdout(), self.allocator);
        defer terminal.deinit();

        var disassambler = as.frontend.debug.Disassambler.init(terminal);

        while (true) {
            if (current_frame.ip >= code.len) return;
            const instruction = code[current_frame.ip];
            current_frame.ip += 1;

            if (debug) {
                used_stack_top = self.stack_top;
                used_frame_count = self.frame_count;
                used_frame = current_frame;
            }

            switch (instruction.abc.opcode) {
                .load_const => {
                    const reg_dest = base + instruction.ab.a;
                    const constant_id = instruction.ab.b;
                    stack[reg_dest] = chunk.constants.items[constant_id];
                },
                .move => {
                    const reg_dest = base + instruction.abc.a;
                    const reg_src = base + instruction.abc.b;
                    stack[reg_dest] = stack[reg_src];
                },
                // math
                .add => try self.numericMath(instruction, MathOps.add),
                .sub => try self.numericMath(instruction, MathOps.sub),
                .multiply => try self.numericMath(instruction, MathOps.mul),
                .divide => {
                    const reg_a = base + instruction.abc.a;
                    const val_b = stack[base + instruction.abc.b];
                    const val_c = stack[base + instruction.abc.c];

                    const float_b = val_b.castToF64() catch 0;
                    const float_c = val_c.castToF64() catch 0;

                    const result = float_b / float_c;
                    if (val_b.isInteger() and val_c.isInteger() and result == @floor(result)) {
                        stack[reg_a] = Value.makeInteger(@intFromFloat(result));
                    } else {
                        stack[reg_a] = Value.makeFloat(result);
                    }
                },
                .negate => {
                    const reg_a = base + instruction.abc.a;
                    const val_b = stack[base + instruction.abc.b];

                    if (val_b.isFloat()) {
                        stack[reg_a] = Value.makeFloat(-val_b.toF64());
                    } else {
                        stack[reg_a] = Value.makeInteger(-val_b.toI64());
                    }
                },
                // compare
                .equal => {
                    const reg_a = base + instruction.abc.a;
                    const val_b = stack[base + instruction.abc.b];
                    const val_c = stack[base + instruction.abc.c];

                    stack[reg_a] = Value.makeBool(val_b.equals(val_c));
                },
                .not_equal => {
                    const reg_a = base + instruction.abc.a;
                    const val_b = stack[base + instruction.abc.b];
                    const val_c = stack[base + instruction.abc.c];

                    stack[reg_a] = Value.makeBool(!val_b.equals(val_c));
                },
                .greater => {
                    const reg_a = base + instruction.abc.a;
                    const float_b = try stack[base + instruction.abc.b].castToF64();
                    const float_c = try stack[base + instruction.abc.c].castToF64();

                    stack[reg_a] = Value.makeBool(float_b > float_c);
                },
                .greater_equal => {
                    const reg_a = base + instruction.abc.a;
                    const float_b = try stack[base + instruction.abc.b].castToF64();
                    const float_c = try stack[base + instruction.abc.c].castToF64();

                    stack[reg_a] = Value.makeBool(float_b >= float_c);
                },
                .less => {
                    const reg_a = base + instruction.abc.a;
                    const float_b = try stack[base + instruction.abc.b].castToF64();
                    const float_c = try stack[base + instruction.abc.c].castToF64();

                    stack[reg_a] = Value.makeBool(float_b < float_c);
                },
                .less_equal => {
                    const reg_a = base + instruction.abc.a;
                    const float_b = try stack[base + instruction.abc.b].castToF64();
                    const float_c = try stack[base + instruction.abc.c].castToF64();

                    stack[reg_a] = Value.makeBool(float_b <= float_c);
                },
                .logical_not => {
                    const reg_a = base + instruction.abc.a;
                    const val_b = stack[base + instruction.abc.b];

                    stack[reg_a] = Value.makeBool(val_b.isFalsey());
                },
                // string
                .string_concat => {
                    const reg_a = base + instruction.abc.b;
                    const str_b = stack[base + instruction.abc.b].toObject().as(ObjString);
                    const str_c = stack[base + instruction.abc.c].toObject().as(ObjString);

                    var result = self.garbage_collector.allocator().alloc(u8, str_b.data.len + str_c.data.len) catch {
                        @panic("alloc failed!");
                    };

                    @memcpy(result[0..str_b.data.len], str_b.data);
                    @memcpy(result[str_b.data.len..], str_c.data);

                    const str_result = ObjString.init(result, self.garbage_collector);
                    stack[reg_a] = Value.fromObject(str_result.asObject());
                },
                // interaction
                .load_upvalue => {
                    const reg_dest = base + instruction.abc.a;
                    const upvalue = current_frame.closure.?.upvalues[instruction.abc.b].?;
                    stack[reg_dest] = upvalue.location.*;
                },
                .store_upvalue => {
                    const upvalue = current_frame.closure.?.upvalues[instruction.abc.a].?;
                    const reg_source = base + instruction.abc.b;
                    upvalue.location.* = stack[reg_source];
                },
                .call => {
                    const reg_dest = base + instruction.abc.a;
                    const reg_callee = base + instruction.abc.b;
                    const arg_count = instruction.abc.c;

                    const callee = stack[reg_callee];

                    if (callee.isObject()) {
                        switch (callee.object.tag) {
                            .closure => {
                                const callee_fn = callee.toObject().as(values.ObjClosure);
                                _ = try self.callClosure(callee_fn, reg_callee + 1, instruction.abc.a);
                            },
                            .function => {
                                const callee_fn = callee.toObject().as(values.ObjFunction);
                                _ = try self.callFunction(callee_fn, reg_callee + 1, instruction.abc.a);
                            },
                            .native_function => {
                                const native = callee.object.as(values.ObjNative);

                                const reg_args_start = reg_callee + 1;
                                const args = stack[reg_args_start .. reg_args_start + arg_count];

                                const result = native.function(&self.execution_context, args);
                                stack[reg_dest] = result;
                            },

                            else => unreachable,
                        }
                    }

                    current_frame = &self.frames[self.frame_count - 1];
                    chunk = current_frame.function.chunk;
                    code = chunk.code.items;
                    base = current_frame.base_pointer;
                },

                .call_return => {
                    if (self.frame_count == 1) {
                        // return from main module
                        self.stack_top = 0;
                        self.frame_count = 0;
                        return;
                    }

                    const offset_return = current_frame.reg_return;
                    const reg_value = base + instruction.abc.b;
                    const return_value_count = instruction.abc.c;

                    var return_value: Value = undefined;
                    if (return_value_count > 0) {
                        return_value = stack[reg_value];
                    }

                    self.frame_count -= 1;

                    current_frame = &self.frames[self.frame_count - 1];
                    chunk = current_frame.function.chunk;
                    code = chunk.code.items;
                    base = current_frame.base_pointer;

                    if (return_value_count > 0) {
                        stack[base + offset_return] = return_value;
                    }

                    self.stack_top = base + current_frame.function.max_registers;
                },
                .create_closure => {
                    const reg_dest = base + instruction.ab.a;
                    const value_function = chunk.constants.items[instruction.ab.b];
                    const obj_function = value_function.toObject().as(ObjFunction);

                    const closure = ObjClosure.init(self.garbage_collector, obj_function);
                    stack[reg_dest] = Value.fromObject(closure.asObject());

                    for (closure.upvalues, 0..) |*upvalue, index| {
                        const location = obj_function.upvalue_locations[index];
                        if (location.is_local) {
                            upvalue.* = try self.captureUpvalue(&stack[@intCast(location.index)]);
                        } else {
                            upvalue.* = current_frame.closure.?.upvalues[location.index];
                        }
                    }
                },
                .close_upvalue => {
                    const reg_b = base + instruction.abc.b;
                    self.closeUpvalue(&stack[reg_b]);
                },

                // control flow
                .jump => {
                    const offset = instruction.ab.b;
                    current_frame.ip += offset - 1;
                },
                .jump_if_false => {
                    const reg_condition = base + instruction.ab.a;
                    if (stack[reg_condition].isFalsey()) {
                        const offset = instruction.ab.b;
                        current_frame.ip += offset - 1;
                    }
                },
                .jump_if_true => {
                    const reg_condition = base + instruction.ab.a;
                    if (!stack[reg_condition].isFalsey()) {
                        const offset = instruction.ab.b;
                        current_frame.ip += offset - 1;
                    }
                },
            }

            if (debug) {
                self.printStack(&disassambler, used_stack_top, used_frame_count, used_frame);
            }
        }
    }

    inline fn callClosure(self: *VirtualMachine, closure: *ObjClosure, first_arg_id: usize, reg_return: RegisterId) Error!*CallFrame {
        const frame = try self.callFunction(closure.function, first_arg_id, reg_return);
        frame.closure = closure;
        return frame;
    }

    inline fn callFunction(self: *VirtualMachine, function: *ObjFunction, first_arg_id: usize, reg_return: RegisterId) Error!*CallFrame {
        if (self.frame_count >= FRAMES_MAX) {
            self.error_reporter.virtualMachineError(self, Error.StackOverflow, "Stack overflow");
            return Error.StackOverflow;
        }

        var frame: *CallFrame = &self.frames[self.frame_count];
        self.frame_count += 1;

        frame.function = function;
        frame.ip = 0;
        frame.base_pointer = first_arg_id;
        frame.reg_return = reg_return;

        var index = self.stack_top;
        while (index < frame.base_pointer + function.max_registers) : (index += 1) {
            self.stack[index] = Value.makeUninitialized();
        }

        self.stack_top = frame.base_pointer + function.max_registers;

        return frame;
    }

    inline fn captureUpvalue(self: *VirtualMachine, local: *Value) !*ObjUpValue {
        var prev_upvalue: ?*ObjUpValue = null;
        var maybe_upvalue = self.open_upvalues;

        // search upvalue
        while (maybe_upvalue) |up_value| {
            if (@intFromPtr(up_value.location) <= @intFromPtr(local)) {
                break;
            }

            prev_upvalue = up_value;
            maybe_upvalue = up_value.next_open;
        }

        if (maybe_upvalue) |upvalue| {
            if (upvalue.location == local) {
                return upvalue;
            }
        }

        // Not found - Inert new upvalue in list
        const created_upvalue = ObjUpValue.init(self.garbage_collector, local);
        created_upvalue.next_open = maybe_upvalue;

        if (prev_upvalue) |prev| {
            prev.next_open = created_upvalue;
        } else {
            self.open_upvalues = created_upvalue;
        }

        return created_upvalue;
    }

    inline fn closeUpvalue(self: *VirtualMachine, last: *Value) void {
        while (self.open_upvalues) |upvalue| {
            if (@intFromPtr(upvalue.location) < @intFromPtr(last)) {
                break;
            }

            // close upvalue
            upvalue.closed = upvalue.location.*;
            upvalue.location = &upvalue.closed;

            // remove from list
            self.open_upvalues = upvalue.next_open;
        }
    }

    const MathOps = struct {
        fn add(comptime T: type, a: T, b: T) T {
            return a + b;
        }
        fn sub(comptime T: type, a: T, b: T) T {
            return a - b;
        }
        fn mul(comptime T: type, a: T, b: T) T {
            return a * b;
        }
    };

    inline fn numericMath(self: *VirtualMachine, instruction: Instruction, comptime op: anytype) !void {
        const current_frame = &self.frames[self.frame_count - 1];

        const base = current_frame.base_pointer;
        const reg_a = base + instruction.abc.a;
        const val_b = self.stack[base + instruction.abc.b];
        const val_c = self.stack[base + instruction.abc.c];

        if (val_b.isInteger() and val_c.isInteger()) {
            const res = op(i64, val_b.toI64(), val_c.toI64());
            self.stack[reg_a] = Value.makeInteger(res);
        } else {
            const float_b = try val_b.castToF64();
            const float_c = try val_c.castToF64();
            const res = op(f64, float_b, float_c);
            self.stack[reg_a] = Value.makeFloat(res);
        }
    }
};

const std = @import("std");
const as = @import("as");
const values = as.runtime.values;

const BuildinFunction = as.BuildinFunction;
const Chunk = as.compiler.Chunk;
const ErrorPool = as.frontend.ErrorPool;
const ErrorReporter = as.common.reporting.ErrorReporter;
const GarbageCollector = as.common.memory.GarbageCollector;
const Instruction = as.compiler.Instruction;
const ObjClosure = as.runtime.values.ObjClosure;
const ObjFunction = as.runtime.values.ObjFunction;
const ObjModule = as.runtime.values.ObjModule;
const ObjString = as.runtime.values.ObjString;
const ObjUpValue = as.runtime.values.ObjUpValue;
const StringTable = as.common.StringTable;
const TypePool = as.frontend.TypePool;
const Value = as.runtime.values.Value;

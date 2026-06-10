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
        InvalidInstruction,
        InvalidCallee,
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

    pub fn execute(self: *VirtualMachine, module: *ObjModule, buildin_functions: []BuildinFunction, comptime print_stack: bool) !void {
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
        try self.run(print_stack);
    }

    fn run(self: *VirtualMachine, comptime debug: bool) !void {
        //        const debug: bool = true;

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

        var stack_printer: ?StackPrinter = null;
        if (debug) {
            stack_printer = StackPrinter.init(terminal, stack, &self.frames, &self.frame_count, &self.open_upvalues);
        }

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
                    const reg_a = base + instruction.abc.a;
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
                .op_call => case: {
                    const callee = stack[base + instruction.abc.b];
                    var function: *ObjFunction = undefined;
                    var closure: ?*ObjClosure = null;

                    // TODO: create constant for max_args
                    var arg_buffer: [32]Value = undefined;
                    var args: []Value = &.{};
                    // init args if there is an op_call_args instruction
                    const next_instruction = code[current_frame.ip];
                    if (next_instruction.ab.opcode == as.compiler.OpCode.op_call_args) {
                        current_frame.ip += 1;

                        const arg_count = next_instruction.ab.a;
                        const arg_index = next_instruction.ab.b;

                        const arg_regs = chunk.arguments.items[arg_index .. arg_index + arg_count];

                        for (arg_regs, 0..) |arg_reg, index| {
                            arg_buffer[index] = stack[base + arg_reg];
                        }
                        args = arg_buffer[0..arg_count];
                    }

                    if (callee.isObject()) {
                        switch (callee.object.tag) {
                            .closure => {
                                closure = callee.toObject().as(values.ObjClosure);
                                function = closure.?.function;
                            },
                            .function => {
                                function = callee.toObject().as(values.ObjFunction);
                            },
                            .native_function => {
                                const native = callee.object.as(values.ObjNative);
                                const result = native.function(&self.execution_context, args);
                                // TODO: check return type (don't mutate stack if void)
                                stack[base + instruction.abc.a] = result;
                                break :case;
                            },

                            else => return Error.InvalidCallee,
                        }
                    } else return Error.InvalidCallee;

                    const reg_return: RegisterId = @intCast(base + instruction.abc.a);

                    const new_base = current_frame.base_pointer + current_frame.function.max_registers;
                    const new_top = new_base + function.max_registers;

                    if (new_top > STACK_MAX) {
                        // we are out of registers
                        self.error_reporter.virtualMachineError(self, Error.StackOverflow, "Stack overflow");
                        return Error.StackOverflow;
                    }

                    // init registers for call frame
                    var index = new_base;
                    while (index < new_top) : (index += 1) {
                        if (index <= new_base + args.len - 1) {
                            stack[index] = args[index - new_base];
                        } else {
                            stack[index] = Value.makeUninitialized();
                        }
                    }

                    self.stack_top = new_top;

                    // setup call frame
                    if (self.frame_count >= FRAMES_MAX) {
                        // we are out of call frames
                        self.error_reporter.virtualMachineError(self, Error.StackOverflow, "Stack overflow");
                        return Error.StackOverflow;
                    }

                    var frame: *CallFrame = &self.frames[self.frame_count];

                    frame.closure = closure;
                    frame.function = function;
                    frame.ip = 0;
                    frame.base_pointer = new_base;
                    frame.reg_return = reg_return;

                    self.frame_count += 1;

                    // update run loop
                    current_frame = &self.frames[self.frame_count - 1];
                    chunk = current_frame.function.chunk;
                    code = chunk.code.items;
                    base = current_frame.base_pointer;
                },
                .op_call_args => unreachable, // read in op_call
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
                            upvalue.* = try self.captureUpvalue(&stack[@intCast(base + location.index)]);
                        } else {
                            upvalue.* = current_frame.closure.?.upvalues[location.index];
                        }
                    }

                    const c = stack[reg_dest];

                    for (c.toObject().as(ObjClosure).upvalues, 0..) |upvalue, i| {
                        if (upvalue) |assured| {
                            std.debug.print("{d:0>2} | {f}\n", .{ i, assured.location });
                        } else {
                            std.debug.print("{d:0>2} | NULL\n", .{i});
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
                stack_printer.?.printStack(used_stack_top, used_frame_count, used_frame);
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

        frame.closure = null;
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
        var maybe_open = self.open_upvalues;

        // search upvalue
        while (maybe_open) |open| {
            if (@intFromPtr(open.location) <= @intFromPtr(local)) {
                break;
            }

            prev_upvalue = open;
            maybe_open = open.next_open;
        }

        if (maybe_open) |open| {
            if (open.location == local) {
                return open;
            }
        }

        // Not found - Inert new upvalue in list
        const created_upvalue = ObjUpValue.init(self.garbage_collector, local);
        created_upvalue.next_open = maybe_open;

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
const StackPrinter = as.frontend.debug.StackPrinter;
const StringTable = as.common.StringTable;
const TypePool = as.frontend.TypePool;
const Value = as.runtime.values.Value;

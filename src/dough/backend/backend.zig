const vm = @import("./vm.zig");
pub const VirtualMachine = vm.VirtualMachine;
pub const InterpretError = vm.InterpretError;
pub const CallFrame = vm.CallFrame;

const opcodes = @import("./opcodes.zig");
pub const OpCode = opcodes.OpCode;

pub const debug = @import("./debug.zig");

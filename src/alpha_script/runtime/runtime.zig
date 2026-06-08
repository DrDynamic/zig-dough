const virtual_machine = @import("virtual_machine.zig");
pub const CallFrame = virtual_machine.CallFrame;
pub const ExecutionContext = virtual_machine.ExecutionContext;
pub const RegisterId = virtual_machine.RegisterId;
pub const VirtualMachine = virtual_machine.VirtualMachine;

pub const values = @import("values/values.zig");

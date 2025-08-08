pub const OpCode = enum(u8) {
    // Slot actions
    DefineSlot,
    GetSlot,
    SetSlot,

    // Constants
    GetConstant,

    // Value interaction
    Call,

    LogicalNot,
    Negate,

    NotEqual,
    Equal,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,

    Add,
    Subtract,
    Multiply,
    Divide,

    // Jumps
    Jump,
    JumpIfTrue,
    JumpIfFalse,

    // Stack Actions
    //// Listerals
    PushNull, // push the value <null>
    PushTrue, // push the value <true>
    PushFalse, // push the value <false>
    PushUninitialized, // push the value <uninitialized>

    Pop, // pop a value

    Return,
};

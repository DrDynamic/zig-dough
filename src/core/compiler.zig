const std = @import("std");

const objects = @import("../values/objects.zig");
const ObjModule = objects.ObjModule;
const ObjFunction = objects.ObjFunction;

const VirtualMachine = @import("./vm.zig").VirtualMachine;
const TokenType = @import("./token.zig").TokenType;
const Scanner = @import("./scanner.zig").Scanner;

const Precedence = enum {
    NONE,
    ASSIGNMENT, // =
    OR, // or
    AND, // and
    EQUALITY, // == !=
    COMPARISON, // < > <= >=
    TERM, // + -
    FACTOR, // * /
    UNARY, // ! -
    CALL, // . ()
    PRIMARY,
};

pub const FunctionCompiler = struct {
    enclosing: ?*FunctionCompiler,
    function: *ObjFunction,
};

const CompilationContext = struct {};

pub const ModuleCompiler = struct {
    const ParseFn = fn (self: *ModuleCompiler, context: CompilationContext) void;
    const ParseRule = struct {
        prefix: ?*const ParseFn = null,
        infix: ?*const ParseFn = null,
        precedence: Precedence = .NONE,
    };
    const ParseRules = std.EnumArray(TokenType, ParseRule);

    vm: *VirtualMachine,
    scanner: Scanner,
    current_compiler: *FunctionCompiler,
    had_error: bool = false,
    panic_mode: bool = false,

    parse_rules: ParseRules = ParseRules.init(.{
        // Single-character tokens.
        .LeftParen = ParseRule{},
        .RightParen = ParseRule{},
        .LeftBrace = ParseRule{},
        .RightBrace = ParseRule{},
        .LeftBracket = ParseRule{},
        .RightBracket = ParseRule{},
        .Comma = ParseRule{},
        .Dot = ParseRule{},
        .Minus = ParseRule{},
        .Plus = ParseRule{},
        .Semicolon = ParseRule{},
        .Slash = ParseRule{},
        .Star = ParseRule{},
        // One or two character tokens.
        .Bang = ParseRule{},
        .BangEqual = ParseRule{},
        .Equal = ParseRule{},
        .EqualEqual = ParseRule{},
        .Greater = ParseRule{},
        .GreaterEqual = ParseRule{},
        .Less = ParseRule{},
        .LessEqual = ParseRule{},
        .LogicalAnd = ParseRule{},
        .LogicalOr = ParseRule{},
        // Literals.
        .Identifier = ParseRule{},
        .String = ParseRule{},
        .Number = ParseRule{},
        // Keywords.
        .Const = ParseRule{},
        .Else = ParseRule{},
        .False = ParseRule{},
        .For = ParseRule{},
        .Function = ParseRule{},
        .If = ParseRule{},
        .Null = ParseRule{},
        .Return = ParseRule{},
        .True = ParseRule{},
        .Var = ParseRule{},
        .While = ParseRule{},

        // Special tokens
        .Synthetic = ParseRule{},
        .Error = ParseRule{},
        .Eof = ParseRule{},
    }),

    pub fn init(
        vm: *VirtualMachine,
        source: []const u8,
    ) !ModuleCompiler {}
};

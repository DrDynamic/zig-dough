const std = @import("std");

const objects = @import("../values/objects.zig");
const ObjModule = objects.ObjModule;
const ObjFunction = objects.ObjFunction;

const Vm = @import("./vm.zig").Vm;
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

    vm: *Vm,
    scanner: Scanner,
    currentCompiler: *FunctionCompiler,
    hadError: bool = false,
    panicMode: bool = false,
};

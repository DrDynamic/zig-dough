const std = @import("std");

const objects = @import("../values/objects.zig");
const ObjModule = objects.ObjModule;

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

const Parser = struct {};

pub fn compile(self: *Compiler, source: []u8) !*ObjModule {
    self._scanner.init(source);
}

pub const Compiler = struct {
    hadError: bool = false,
    panicMode: bool = false,

    _scanner: Scanner = Scanner{},
    _module: ObjModule = ObjModule{},

    pub fn init(vm: *Vm) !*Compiler {
        const compiler = vm.allocator.create(Compiler);
        compiler.* = Compiler{};
    }
};

const CompilationContext = struct {};

pub const ModuleCompiler = struct {
    const ParseFn = fn (*Parser, CompilationContext) void;
    const ParseRule = struct {
        prefix: ?*const ParseFn = null,
        infix: ?*const ParseFn = null,
        precedence: Precedence = .NONE,
    };
    const ParseRules = std.EnumArray(TokenType, ParseRule);

    vm: *Vm,
    scanner: Scanner,
    currentCompiler: *Compiler,
    hadError: bool = false,
    panicMode: bool = false,
};

const std = @import("std");

const core = @import("./core.zig");
const Chunk = core.chunk.Chunk;
const GarbageColletingAllocator = core.memory.GarbageColletingAllocator;
const InterpretError = core.vm.InterpretError;
const OpCode = core.chunk.OpCode;
const Scanner = core.scanner.Scanner;
const Token = core.token.Token;
const TokenType = core.token.TokenType;
const VirtualMachine = core.vm.VirtualMachine;

const objects = @import("../values/objects.zig");
const DoughModule = objects.DoughModule;
const DoughFunction = objects.DoughFunction;

const Precedence = enum {
    None,
    Assignment, // =
    Or, // or
    And, // and
    Equality, // == !=
    Comparison, // < > <= >=
    Term, // + -
    Factor, // * /
    Unary, // ! -
    Call, // . ()
    Primary,
};

pub const FunctionCompiler = struct {
    function: *DoughFunction,
    scanner: *Scanner,
    enclosing: ?*FunctionCompiler = null,
    panic_mode: bool = false,

    pub fn init(vm: *VirtualMachine, scanner: *Scanner) !FunctionCompiler {
        return FunctionCompiler{
            .function = try objects.DoughFunction.init(vm),
            .scanner = scanner,
        };
    }

    pub fn emitByte(self: *FunctionCompiler, byte: u8) void {
        self.function.chunk.writeByte(byte, self.scanner.previous.line) catch {
            self.err("Could not write to chunk!", .{});
            return;
        };
    }

    pub fn emitReturn(self: *FunctionCompiler) void {
        self.emitByte(@intFromEnum(OpCode.Null));
        self.emitByte(@intFromEnum(OpCode.Return));
    }

    pub fn err(self: *FunctionCompiler, comptime message: []const u8, args: anytype) void {
        self.errAt(&self.scanner.previous, message, args);
    }

    pub fn errAtCurrent(self: *FunctionCompiler, comptime message: []const u8, args: anytype) void {
        self.errAt(&self.scanner.current, message, args);
    }

    pub fn errAt(self: *FunctionCompiler, token: *const Token, comptime message: []const u8, args: anytype) void {
        // Compiler is already in panic. We shouldn't make him anymore nervous than he already is...
        if (self.panic_mode) return;

        // something went wrong! Oh no oh no ... panic!!!
        self.panic_mode = true;

        // TODO: find a more gracefull handling than 'catch return;' when error printing failes!

        if (token.token_type == TokenType.Error) {
            self._printError(token, "Error", message, args) catch return;
        } else if (token.token_type == TokenType.Eof) {
            self._printError(token, "Error at end", message, args) catch return;
        } else {
            const config = @import("../config.zig");
            const label = std.fmt.allocPrint(config.allocator, "Error at '{?s}'", .{token.lexeme}) catch |allocErr| @errorName(allocErr);
            defer config.allocator.free(label);

            self._printError(token, label, message, args) catch return;
        }
    }

    fn _printError(_: FunctionCompiler, token: *const Token, label: []const u8, comptime message: []const u8, args: anytype) !void {
        const stdout_file = std.io.getStdErr().writer();
        var bw = std.io.bufferedWriter(stdout_file);
        const stderr = bw.writer();

        try stderr.print("[line {d: >4}] {s}", .{ token.line, label });
        try stderr.print(message, args);
        try stderr.print("\n", .{});

        try bw.flush(); // Don't forget to flush!
    }
};

const CompilationContext = struct {
    pub fn init() CompilationContext {
        return .{};
    }
};

pub const ModuleCompiler = struct {
    const ParseFn = fn (self: *ModuleCompiler, context: CompilationContext) void;
    const ParseRule = struct {
        prefix: ?*const ParseFn = null,
        infix: ?*const ParseFn = null,
        precedence: Precedence = .None,
    };
    const ParseRules = std.EnumArray(TokenType, ParseRule);

    vm: *VirtualMachine,
    scanner: Scanner,
    current_compiler: ?*FunctionCompiler = null,
    had_error: bool = false,

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
    ) ModuleCompiler {
        return ModuleCompiler{
            .vm = vm,
            .scanner = Scanner.init(source),
        };
    }

    pub fn compile(self: *ModuleCompiler) !*DoughFunction {
        var compiler = try FunctionCompiler.init(self.vm, &self.scanner);
        self.current_compiler = &compiler;

        self.advance();

        while (!self.match(TokenType.Eof)) {
            self.declaration();
        }

        const function = self.endCompiler();

        if (self.had_error) {
            return InterpretError.CompileError;
        } else {
            return function;
        }
    }

    fn endCompiler(self: *ModuleCompiler) *DoughFunction {
        self.current_compiler.?.emitReturn();

        const function = self.current_compiler.?.function;

        if (@import("../config.zig").debug_print_code) {
            // TODO: set module name / function name
            @import("./debug.zig").disassemble_chunk(&function.chunk, "<script>");
        }

        if (self.current_compiler.?.enclosing) |enclosing| {
            self.current_compiler = enclosing;
        }

        return function;
    }

    fn declaration(self: *ModuleCompiler) void {
        if (self.match(TokenType.Var)) {} else {
            self.statement();
        }
    }

    fn statement(self: *ModuleCompiler) void {
        if (self.match(TokenType.Return)) {
            self.returnStatement();
        } else {
            self.expressionStatement();
        }
    }

    fn returnStatement(self: *ModuleCompiler) void {
        if (self.match(TokenType.Semicolon)) {
            // TODO: make semikolons optionals (check for new line instead?)
            self.current_compiler.?.emitReturn();
        } else {
            self.expression();
            _ = self.match(TokenType.Semicolon);
            self.current_compiler.?.emitByte(@intFromEnum(OpCode.Return));
        }
    }

    fn expressionStatement(self: *ModuleCompiler) void {
        self.expression();
        _ = self.match(TokenType.Semicolon);
        self.current_compiler.?.emitByte(@intFromEnum(OpCode.Pop));
    }

    fn expression(self: *ModuleCompiler) void {
        self.parsePrecedence(Precedence.Assignment);
    }

    fn parsePrecedence(self: *ModuleCompiler, precedence: Precedence) void {
        self.advance();
        const parse_rule: *const ParseRule = self.parse_rules.getPtrConst(self.scanner.previous.token_type.?);
        const prefix_rule: *const ParseFn = parse_rule.prefix orelse {
            // The last parsed token doesn't have a prefix rule
            self.current_compiler.?.err("expect expression.", .{});
            return;
        };

        const context = CompilationContext.init();

        // Compile the prefix
        prefix_rule(self, context);

        // Compile the infix
        while (@intFromEnum(precedence) <= @intFromEnum(self.parse_rules.getPtrConst(self.scanner.current.token_type.?).precedence)) {
            self.advance();
            const infix_rule = self.parse_rules.getPtrConst(self.scanner.previous.token_type.?).infix orelse {
                self.current_compiler.?.err("Expect expression.", .{});
                return;
            };
            infix_rule(self, context);
        }
    }

    fn advance(self: *ModuleCompiler) void {
        var scanner = &self.scanner;
        while (true) {
            scanner.scanToken();
            if (scanner.current.token_type != TokenType.Error) break;

            self.current_compiler.?.errAtCurrent("{?s}", .{scanner.current.lexeme});
        }
    }

    fn consume(self: ModuleCompiler, token_type: TokenType, message: []const u8, args: anytype) void {
        if (self.check(token_type)) {
            self.advance();
        } else {
            self.current_compiler.?.errAtCurrent(message, args);
        }
    }

    fn match(self: *ModuleCompiler, token_type: TokenType) bool {
        if (!self.check(token_type)) {
            return false;
        }
        self.advance();
        return true;
    }

    fn check(self: ModuleCompiler, token_type: TokenType) bool {
        return (self.scanner.current.token_type.? == token_type);
    }

    fn getCurrentChunk(self: ModuleCompiler) *Chunk {
        return &self.current_compiler.function.chunk;
    }
};

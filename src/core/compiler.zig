const std = @import("std");

const types = @import("../types.zig");

const core = @import("./core.zig");
const Chunk = core.chunk.Chunk;
const GarbageColletingAllocator = core.memory.GarbageColletingAllocator;
const InterpretError = core.vm.InterpretError;
const OpCode = core.chunk.OpCode;
const Scanner = core.scanner.Scanner;
const Token = core.token.Token;
const TokenType = core.token.TokenType;
const VirtualMachine = core.vm.VirtualMachine;

const values = @import("../values/values.zig");
const objects = values.objects;
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
    enclosing: ?*FunctionCompiler = null,
    function: *DoughFunction,
    panic_mode: bool = false,
    had_error: bool = false,
    scanner: *Scanner,
    scopeDepth: u24 = 0,

    pub fn init(scanner: *Scanner) !FunctionCompiler {
        return FunctionCompiler{
            .function = try objects.DoughFunction.init(),
            .scanner = scanner,
        };
    }

    pub fn declareIdentifier(self: *FunctionCompiler, identifier: ?[]const u8, readonly: bool) ?types.SlotAddress {
        if (identifier) |safeAnIdentifierAndNotNull| {
            const props = self.function.slots.getProperties(safeAnIdentifierAndNotNull);

            if (props != null and props.?.depth == self.scopeDepth) {
                self.err("Name already in use in this scope", .{});
                return null;
            }
        }

        return self.function.slots.push(
            .{
                .depth = self.scopeDepth,
                .identifier = identifier,
                .readonly = readonly,
            },
        ) catch |stackError| {
            self.err("Creating Identifier failed ({s}).", .{@errorName(stackError)});
            return null;
        };
    }

    pub fn readIdentifier(self: *FunctionCompiler, identifier: []const u8) void {
        const maybeAddress = self.function.slots.addresses.get(identifier);

        if (maybeAddress) |address| {
            self.emitOpCode(.GetSlot);
            self.emitSlotAddress(address);
            return;
        }

        self.function.slots.debugPrint();

        self.err("Can not access identifier '{s}' (not defined).", .{identifier});
    }

    pub fn writeIdentifier(self: *FunctionCompiler, identifier: []const u8) void {
        const maybeAddress = self.function.slots.addresses.get(identifier);

        if (maybeAddress) |address| {
            self.emitOpCode(.SetSlot);
            self.emitSlotAddress(address);
        }

        self.err("Can not access identifier '{s}' (not defined).", .{identifier});
    }

    pub fn emitByte(self: *FunctionCompiler, byte: u8) void {
        self.function.chunk.writeByte(byte, self.scanner.previous.line) catch |write_error| {
            self.err("Could not write to chunk: {s}", .{@errorName(write_error)});
            return;
        };
    }

    pub fn emitOpCode(self: *FunctionCompiler, op_code: OpCode) void {
        self.emitByte(@intFromEnum(op_code));
    }

    pub fn emitSlotAddress(self: *FunctionCompiler, address: types.SlotAddress) void {
        const bytes: [3]u8 = @bitCast(address);

        self.emitByte(bytes[0]);
        self.emitByte(bytes[1]);
        self.emitByte(bytes[2]);
    }

    pub fn emitConstantAddress(self: *FunctionCompiler, address: types.ConstantAddress) void {
        const bytes: [3]u8 = @bitCast(address);

        self.emitByte(bytes[0]);
        self.emitByte(bytes[1]);
        self.emitByte(bytes[2]);
    }

    pub fn emitReturn(self: *FunctionCompiler) void {
        self.emitByte(@intFromEnum(OpCode.PushNull));
        self.emitByte(@intFromEnum(OpCode.Return));
    }

    pub fn addConstant(self: *FunctionCompiler, value: values.Value) types.ConstantAddress {
        return self.function.chunk.writeConstant(value) catch |write_error| {
            self.err("Could nor write constant: {s}", .{@errorName(write_error)});
            return types.CONSTANT_ADDRESS_INVALID;
        };
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
        self.had_error = true;

        // TODO: find a more gracefull handling than 'catch return;' when error printing failes!

        if (token.token_type == TokenType.Error) {
            self._printError(token, "Error", message, args) catch return;
        } else if (token.token_type == TokenType.Eof) {
            self._printError(token, "Error at end", message, args) catch return;
        } else {
            const config = @import("../config.zig");
            const label = std.fmt.allocPrint(config.allocator, "Error at '{?s}' ", .{token.lexeme}) catch |allocErr| @errorName(allocErr);
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
    can_assign: bool = false,
    pub fn init(can_assign: bool) CompilationContext {
        return .{
            .can_assign = can_assign,
        };
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

    module: *DoughModule = undefined,
    scanner: Scanner,
    current_compiler: ?*FunctionCompiler = null,
    had_error: bool = false,

    parse_rules: ParseRules = ParseRules.init(.{
        // Single-character tokens.
        .LeftParen = ParseRule{ .infix = call, .precedence = Precedence.Call },
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
        .Identifier = ParseRule{ .prefix = identifier },
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

    pub fn init(source: []const u8) ModuleCompiler {
        return ModuleCompiler{
            .scanner = Scanner.init(source),
        };
    }

    pub fn compile(self: *ModuleCompiler, natives: []*objects.DoughNativeFunction) !*DoughModule {
        self.module = try DoughModule.init();

        var compiler = try FunctionCompiler.init(&self.scanner);
        self.current_compiler = &compiler;

        _ = compiler.declareIdentifier(null, true);

        // declare natives (workaround till we have a better solution)
        for (natives) |native| {
            const address = compiler.addConstant(values.Value.fromObject(native.asObject()));
            compiler.emitOpCode(.GetConstant);
            compiler.emitConstantAddress(address);
            _ = compiler.declareIdentifier(native.name, true);
        }

        self.advance();

        while (!self.match(TokenType.Eof)) {
            self.declaration();
        }

        self.module.function = self.endCompiler();

        if (compiler.had_error) {
            return InterpretError.CompileError;
        } else {
            return self.module;
        }
    }

    fn endCompiler(self: *ModuleCompiler) *DoughFunction {
        // TODO: check for not defined identifiers

        self.current_compiler.?.emitReturn();

        const function = self.current_compiler.?.function;

        if (@import("../config.zig").debug_print_code) {
            // TODO: set module name / function name
            @import("./debug.zig").disassemble_function(function);
        }

        if (self.current_compiler.?.enclosing) |enclosing| {
            self.current_compiler = enclosing;
        }

        return function;
    }

    fn declaration(self: *ModuleCompiler) void {
        if (self.match(.Var)) {
            _ = self.parseIdentifier("Expect variable name.", false);
            self.varDeclaration();
        } else if (self.match(.Const)) {
            _ = self.parseIdentifier("Expect constant name.", true);
            self.varDeclaration();
        } else {
            self.statement();
        }
    }

    fn varDeclaration(self: *ModuleCompiler) void {
        if (self.match(TokenType.Equal)) {
            self.expression();
        } else {
            self.current_compiler.?.emitOpCode(OpCode.PushUninitialized);
        }

        // TODO: or consume newLine
        _ = self.match(TokenType.Semicolon);
    }

    // Consumes an Identifier and reserve a slot in the current scope
    fn parseIdentifier(self: *ModuleCompiler, message: []const u8, readonly: bool) ?u24 {
        self.consume(TokenType.Identifier, "{s}", .{message});
        const name = &self.scanner.previous;

        return self.current_compiler.?.declareIdentifier(name.lexeme.?, readonly);
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

    fn expressionList(self: *ModuleCompiler, endToken: TokenType, comptime too_many_error: []const u8) u8 {
        var arg_count: u8 = 0;

        while (!self.check(endToken)) {
            self.expression();
            if (arg_count == 255) {
                self.current_compiler.?.err(too_many_error, .{});
            }
            arg_count += 1;
            if (!self.match(TokenType.Comma)) {
                break;
            }
        }
        return arg_count;
    }

    fn parsePrecedence(self: *ModuleCompiler, precedence: Precedence) void {
        self.advance();
        const parse_rule: *const ParseRule = self.parse_rules.getPtrConst(self.scanner.previous.token_type.?);
        const prefix_rule: *const ParseFn = parse_rule.prefix orelse {
            // The last parsed token doesn't have a prefix rule
            self.current_compiler.?.err("expect expression.", .{});
            return;
        };

        const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.Assignment);
        const context = CompilationContext.init(can_assign);

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

    fn identifier(self: *ModuleCompiler, context: CompilationContext) void {
        const name = self.scanner.previous;

        if (context.can_assign and self.match(TokenType.Equal)) {
            // TODO: check access intent (can write ?)
            self.expression();
            self.current_compiler.?.writeIdentifier(name.lexeme.?);
        } else {
            self.current_compiler.?.readIdentifier(name.lexeme.?);
        }
    }

    fn call(self: *ModuleCompiler, _: CompilationContext) void {
        const arg_count = self.expressionList(TokenType.RightParen, "Can't have more than 255 arguments.");
        self.consume(TokenType.RightParen, "Expect ')' after arguments.", .{});
        self.current_compiler.?.emitOpCode(.Call);
        self.current_compiler.?.emitByte(arg_count);
    }

    fn advance(self: *ModuleCompiler) void {
        var scanner = &self.scanner;
        while (true) {
            scanner.scanToken();
            if (scanner.current.token_type != TokenType.Error) break;

            self.current_compiler.?.errAtCurrent("{?s}", .{scanner.current.lexeme});
        }
    }

    fn consume(self: *ModuleCompiler, token_type: TokenType, comptime message: []const u8, args: anytype) void {
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

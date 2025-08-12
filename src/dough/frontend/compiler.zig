const std = @import("std");

const dough = @import("dough");
const types = dough.types;
const frontend = dough.frontend;
const backend = dough.backend;

const Scanner = frontend.Scanner;
const Token = frontend.Token;
const TokenType = frontend.TokenType;

const VirtualMachine = backend.VirtualMachine;
const OpCode = backend.OpCode;
const InterpretError = backend.InterpretError;

const values = dough.values;
const Chunk = values.Chunk;
const objects = values.objects;

const DoughModule = objects.DoughModule;
const DoughFunction = objects.DoughFunction;

const ReferenceStack = @import("./reference_stack.zig").ReferenceStack;

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

    references: ReferenceStack,

    pub fn init(scanner: *Scanner) !FunctionCompiler {
        return FunctionCompiler{
            .function = objects.DoughFunction.init(),
            .scanner = scanner,
            .references = ReferenceStack.init(),
        };
    }

    pub fn deinit(self: *FunctionCompiler) void {
        self.references.deinit();
    }

    fn beginScope(self: *FunctionCompiler) void {
        self.scopeDepth += 1;
    }

    fn endScope(self: *FunctionCompiler) void {
        self.assertIdentifiers();

        self.scopeDepth -= 1;

        var references = &self.references;

        if (references.properties.items.len == 0) return;

        while (references.properties.getLast().depth > self.scopeDepth) {
            references.pop() catch |e| {
                self.err("Unexpectd error occured: {s}\n", .{@errorName(e)});
            };
            self.emitOpCode(.Pop);
        }
    }

    fn assertIdentifiers(self: *FunctionCompiler) void {
        const props = self.references.properties.items;
        for (props) |prop| {
            if (!prop.isRead) {
                // TODO: add warning: Variable not used
                continue;
            }

            if (!prop.isWritten) {
                if (prop.token) |token| {
                    self.errAt(&token, "Variable not initialized", .{});
                } else {
                    self.err("Variable not initialized", .{});
                }
            }

            if (prop.type == null) {
                if (prop.token) |token| {
                    self.errAt(&token, "Type could not be inferred", .{});
                } else {
                    self.err("Type could not be inferred", .{});
                }
            }
        }
    }

    pub fn declareIdentifier(self: *FunctionCompiler, identifier: ?[]const u8, readonly: bool, token: ?Token) ?types.SlotAddress {
        if (identifier) |safeAnIdentifierAndNotNull| {
            const props = self.references.getProperties(safeAnIdentifierAndNotNull);

            if (props != null and props.?.depth == self.scopeDepth) {
                self.err("Name already in use in this scope", .{});
                return null;
            }
        }

        return self.references.push(
            .{
                .token = token,
                .depth = self.scopeDepth,
                .identifier = identifier,
                .readonly = readonly,
            },
        ) catch |stackError| {
            self.err("Creating Identifier failed ({s}).", .{@errorName(stackError)});
            return null;
        };
    }

    pub fn readIdentifier(self: *FunctionCompiler, identifier: []const u8, maybe_value_type: ?values.Type) ?values.Type {
        const maybeAddress = self.references.addresses.get(identifier);

        if (maybeAddress) |address| {
            var props = &self.references.properties.items[address];

            if (!props.isDeclared) {
                self.err("Can't read variable in its own initializer.", .{});
            }

            if (maybe_value_type) |value_type| {
                if (props.type) |var_type| {
                    if (!value_type.equals(var_type)) {
                        self.err("mixing types is not allowed", .{});
                    }
                } else {
                    self.err("variable not initialized", .{});
                }
            }

            self.emitOpCode(.GetSlot);
            self.emitSlotAddress(address);
            props.isRead = true;
            return props.type;
        }

        self.err("Undefined identifier.", .{});
        return null;
    }

    pub fn writeIdentifier(self: *FunctionCompiler, identifier: []const u8, maybe_value_type: ?values.Type) void {
        const maybeAddress = self.references.addresses.get(identifier);

        if (maybeAddress) |address| {
            var props = &self.references.properties.items[address];

            if (maybe_value_type) |value_type| {
                if (props.type) |varType| {
                    if (!varType.equals(value_type)) {
                        self.err("can not assign {} to {}", .{ value_type, varType });
                    }
                } else {
                    props.type = value_type;
                }
            } else {
                self.err("Variable not initialized", .{});
            }

            self.emitOpCode(.SetSlot);
            self.emitSlotAddress(address);

            props.isWritten = true;
            return;
        }

        self.err("Undefined identifier '{s}'.", .{identifier});
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
        self.emitU24(address);
    }

    pub fn emitConstantAddress(self: *FunctionCompiler, address: types.ConstantAddress) void {
        self.emitU24(address);
    }

    pub fn emitU24(self: *FunctionCompiler, value: u24) void {
        const bytes: [3]u8 = @bitCast(value);

        self.emitByte(bytes[0]);
        self.emitByte(bytes[1]);
        self.emitByte(bytes[2]);
    }

    pub fn emitReturn(self: *FunctionCompiler) void {
        self.emitByte(@intFromEnum(OpCode.PushNull));
        self.emitByte(@intFromEnum(OpCode.Return));
    }

    pub fn emitJump(self: *FunctionCompiler, opcode: OpCode) usize {
        self.emitOpCode(opcode);

        self.emitByte(0xFF);
        self.emitByte(0xFF);

        return self.function.chunk.code.items.len - 2;
    }

    pub fn patchJump(self: *FunctionCompiler, offset: usize) void {
        // -2 is for the 2-byte offset of the jump operand. See `emitJump`.
        const jump = self.function.chunk.code.items.len - offset - 2;

        if (jump > std.math.maxInt(u16)) {
            self.err("Too much code to jump over.", .{});
        }

        //        const jump_u16: u16 = @intCast(jump);
        const bytes: [2]u8 = @bitCast(@as(u16, @intCast(jump)));

        self.function.chunk.code.items[offset] = bytes[0];
        self.function.chunk.code.items[offset + 1] = bytes[1];
    }

    pub fn addConstant(self: *FunctionCompiler, value: values.Value) types.ConstantAddress {
        return self.function.chunk.writeConstant(value) catch |write_error| {
            self.err("Could nor write constant: {s}", .{@errorName(write_error)});
            return types.CONSTANT_ADDRESS_INVALID;
        };
    }

    pub fn assertType(self: *FunctionCompiler, a: values.Type, b: ?values.Type, comptime wrongType: []const u8) void {
        if (b) |assured_b| {
            if (!a.equals(assured_b)) {
                self.err(wrongType, .{});
            }
        }
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

        dough.config.io_config.compileErrorReporter(token, message, args);
    }
};

const SharedContext = struct {
    type: ?values.Type = null,
};

const CompilationContext = struct {
    can_assign: bool = false,
    shared: *SharedContext = undefined,
};

pub const ModuleCompiler = struct {
    const ParseFn = fn (self: *ModuleCompiler, context: CompilationContext) void;
    const ParseRule = struct {
        prefix: ?*const ParseFn = null,
        infix: ?*const ParseFn = null,
        precedence: Precedence = .None,
    };
    const ParseRules = std.EnumArray(TokenType, ParseRule);

    vm: *VirtualMachine = undefined,
    scanner: Scanner = undefined,
    current_compiler: ?*FunctionCompiler = null,
    had_error: bool = false,

    parse_rules: ParseRules = ParseRules.init(.{
        // Single-character tokens.
        .LeftParen = ParseRule{ .prefix = grouping, .infix = call, .precedence = .Call },
        .RightParen = ParseRule{},
        .LeftBrace = ParseRule{},
        .RightBrace = ParseRule{},
        .LeftBracket = ParseRule{},
        .RightBracket = ParseRule{},
        .Colon = ParseRule{},
        .Comma = ParseRule{},
        .Dot = ParseRule{ .prefix = null, .infix = dot, .precedence = .Call },
        .Minus = ParseRule{ .prefix = unary, .infix = binary, .precedence = .Term },
        .Plus = ParseRule{ .prefix = null, .infix = binary, .precedence = .Term },
        .Semicolon = ParseRule{},
        .Slash = ParseRule{ .prefix = null, .infix = binary, .precedence = .Factor },
        .Star = ParseRule{ .prefix = null, .infix = binary, .precedence = .Factor },
        // One or two character tokens.
        .Bang = ParseRule{ .prefix = unary },
        .BangEqual = ParseRule{ .prefix = null, .infix = binary, .precedence = .Equality },
        .Equal = ParseRule{},
        .EqualEqual = ParseRule{ .prefix = null, .infix = binary, .precedence = .Equality },
        .Greater = ParseRule{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .GreaterEqual = ParseRule{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .Less = ParseRule{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .LessEqual = ParseRule{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .LogicalAnd = ParseRule{ .prefix = null, .infix = and_, .precedence = .And },
        .LogicalOr = ParseRule{ .prefix = null, .infix = or_, .precedence = .Or },
        // Literals.
        .Identifier = ParseRule{ .prefix = identifier },
        .String = ParseRule{ .prefix = string },
        .Number = ParseRule{ .prefix = number },
        // Keywords.
        .Const = ParseRule{},
        .Else = ParseRule{},
        .False = ParseRule{ .prefix = literal },
        .For = ParseRule{},
        .Function = ParseRule{},
        .If = ParseRule{},
        .Null = ParseRule{ .prefix = literal },
        .Return = ParseRule{},
        .True = ParseRule{ .prefix = literal },
        .Var = ParseRule{},
        .While = ParseRule{},

        // Special tokens
        .Synthetic = ParseRule{},
        .Error = ParseRule{},
        .Eof = ParseRule{},
    }),

    pub fn init(vm: *VirtualMachine) ModuleCompiler {
        return ModuleCompiler{
            .vm = vm,
        };
    }

    pub fn compile(self: *ModuleCompiler, source: []const u8, natives: []*objects.DoughNativeFunction) !*DoughModule {
        self.scanner = Scanner.init(source);

        var compiler = try FunctionCompiler.init(&self.scanner);
        const properties = &compiler.references.properties;

        self.current_compiler = &compiler;

        const rootAddress = compiler.declareIdentifier(null, true, null).?;
        properties.items[rootAddress].isWritten = true;
        properties.items[rootAddress].type = .{ .Module = {} };

        self.current_compiler.?.beginScope();

        // declare natives (workaround until we have a better solution)
        for (natives) |native| {
            const address = compiler.addConstant(values.Value.fromObject(native.asObject()));
            compiler.emitOpCode(.GetConstant);
            compiler.emitConstantAddress(address);

            const nativeAddress = compiler.declareIdentifier(native.name, true, null).?;
            properties.items[nativeAddress].isDeclared = true;
            properties.items[nativeAddress].isWritten = true;
            properties.items[nativeAddress].type = .{ .Void = {} };
        }

        self.advance();

        while (!self.match(TokenType.Eof)) {
            self.declaration();
        }

        const function = self.endCompiler();
        try dough.tmpObjects.append(function.asObject());

        const module = DoughModule.init(function);

        _ = dough.tmpObjects.pop();

        if (compiler.had_error) {
            return InterpretError.CompileError;
        } else {
            return module;
        }
    }

    fn endCompiler(self: *ModuleCompiler) *DoughFunction {
        self.current_compiler.?.endScope();
        self.current_compiler.?.emitReturn();

        const function = self.current_compiler.?.function;

        if (dough.config.debug_print_code) {
            // TODO: set module name / function name
            backend.debug.disassemble_function(function);
        }

        var compiler = self.current_compiler.?;
        self.current_compiler = compiler.enclosing;

        compiler.deinit();

        //        if (self.current_compiler.?.enclosing) |enclosing| {
        //            self.current_compiler = enclosing;
        //        }

        return function;
    }

    fn declaration(self: *ModuleCompiler) void {
        if (self.match(.Var)) {
            const maybe_address = self.parseIdentifier("Expect variable name.", false);
            if (maybe_address) |address| {
                self.varDeclaration(address);
            }
        } else if (self.match(.Const)) {
            const maybe_address = self.parseIdentifier("Expect constant name.", true);
            if (maybe_address) |address| {
                self.varDeclaration(address);
            }
        } else {
            self.statement();
        }
    }

    fn varDeclaration(self: *ModuleCompiler, address: types.SlotAddress) void {
        var props = &self.current_compiler.?.references.properties.items[address];

        if (self.match(.Colon)) {
            props.type = self.typeDefinition();
        }

        if (self.match(.Equal)) {
            props.isWritten = true;

            var context = SharedContext{};
            self.expression(&context);

            if (props.type) |propType| {
                if (context.type != null and !propType.equals(context.type.?)) {
                    self.current_compiler.?.err("can not assign {} to {}", .{ context.type.?, propType });
                }
            } else {
                props.type = context.type;
            }
        } else {
            self.current_compiler.?.emitOpCode(OpCode.PushUninitialized);
        }

        props.isDeclared = true;

        // TODO: or consume newLine
        _ = self.match(.Semicolon);
    }

    fn typeDefinition(self: *ModuleCompiler) values.Type {
        if (self.match(.Identifier)) {
            return values.Type.fromToken(self.scanner.previous) catch {
                self.current_compiler.?.err("unknown type", .{});
                return values.Type.makeVoid();
            };
        }

        self.current_compiler.?.err("unknown type", .{});
        return values.Type.makeVoid();
    }

    // Consumes an Identifier and reserve a slot in the current scope
    fn parseIdentifier(self: *ModuleCompiler, message: []const u8, readonly: bool) ?types.SlotAddress {
        self.consume(TokenType.Identifier, "{s}", .{message});
        const name = &self.scanner.previous;

        return self.current_compiler.?.declareIdentifier(name.lexeme.?, readonly, name.*) orelse null;
    }

    fn statement(self: *ModuleCompiler) void {
        if (self.match(.Return)) {
            self.returnStatement();
        } else if (self.match(.LeftBrace)) {
            self.current_compiler.?.beginScope();
            self.block();
            self.current_compiler.?.endScope();
        } else {
            self.expressionStatement();
        }
    }

    fn returnStatement(self: *ModuleCompiler) void {
        if (self.match(TokenType.Semicolon)) {
            // TODO: make semikolons optionals (check for new line instead?)
            self.current_compiler.?.emitReturn();
        } else {
            self.expression(null);
            _ = self.match(TokenType.Semicolon);
            self.current_compiler.?.emitByte(@intFromEnum(OpCode.Return));
        }
    }

    fn expressionStatement(self: *ModuleCompiler) void {
        self.expression(null);
        _ = self.match(TokenType.Semicolon);
        self.current_compiler.?.emitByte(@intFromEnum(OpCode.Pop));
    }

    fn expression(self: *ModuleCompiler, shared_context: ?*SharedContext) void {
        self.parsePrecedence(.Assignment, shared_context);
    }

    fn expressionList(self: *ModuleCompiler, endToken: TokenType, comptime too_many_error: []const u8) u8 {
        var arg_count: u8 = 0;

        while (!self.check(endToken)) {
            self.expression(null);
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

    fn dot(self: *ModuleCompiler, _: CompilationContext) void {
        self.consume(TokenType.Identifier, "Expect property name after '.'.", .{});
    }

    fn literal(self: *ModuleCompiler, context: CompilationContext) void {
        switch (self.scanner.previous.token_type.?) {
            .Null => {
                if (context.shared.type) |value_type| {
                    if (value_type != .Null) {
                        self.current_compiler.?.err("mixing types is not allowed", .{});
                    }
                } else {
                    context.shared.type = values.Type.makeNull();
                }
                self.current_compiler.?.emitOpCode(.PushNull);
            },
            .True => {
                if (context.shared.type) |value_type| {
                    if (value_type != .Bool) {
                        self.current_compiler.?.err("mixing types is not allowed", .{});
                    }
                } else {
                    context.shared.type = values.Type.makeBool();
                }
                self.current_compiler.?.emitOpCode(.PushTrue);
            },
            .False => {
                if (context.shared.type) |value_type| {
                    if (value_type != .Bool) {
                        self.current_compiler.?.err("mixing types is not allowed", .{});
                    }
                } else {
                    context.shared.type = values.Type.makeBool();
                }
                self.current_compiler.?.emitOpCode(.PushFalse);
            },
            else => return,
        }
    }

    fn grouping(self: *ModuleCompiler, _: CompilationContext) void {
        self.expression(null);
        self.consume(.RightParen, "Expect ')' after expression", .{});
    }

    fn number(self: *ModuleCompiler, context: CompilationContext) void {
        if (context.shared.type) |value_type| {
            if (value_type != .Number) {
                self.current_compiler.?.err("mixing types is not allowed", .{});
            }
        } else {
            context.shared.type = values.Type.makeNumber();
        }

        if (std.fmt.parseFloat(f64, self.scanner.previous.lexeme.?)) |value| {
            const address = self.current_compiler.?.addConstant(values.Value.fromNumber(value));
            self.current_compiler.?.emitOpCode(.GetConstant);
            self.current_compiler.?.emitConstantAddress(address);
        } else |e| switch (e) {
            error.InvalidCharacter => {
                self.current_compiler.?.err("failed to parse number", .{});
                return;
            },
        }
    }

    fn unary(self: *ModuleCompiler, context: CompilationContext) void {
        const operatorType = self.scanner.previous.token_type.?;

        self.parsePrecedence(.Unary, context.shared);

        switch (operatorType) {
            .Bang => {
                self.current_compiler.?.emitOpCode(.LogicalNot);
                context.shared.type = values.Type.makeBool();
            },
            .Minus => {
                if (context.shared.type) |value_type| {
                    if (value_type != .Number) {
                        self.current_compiler.?.err("Operand must be a number.", .{});
                    }
                }
                self.current_compiler.?.emitOpCode(.Negate);
            },
            else => return,
        }
    }

    fn binary(self: *ModuleCompiler, context: CompilationContext) void {
        const operator_type = self.scanner.previous.token_type.?;
        const rule = self.parse_rules.getPtrConst(operator_type);

        self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1), context.shared);

        switch (operator_type) {
            .BangEqual => self.current_compiler.?.emitOpCode(.NotEqual),
            .EqualEqual => self.current_compiler.?.emitOpCode(.Equal),

            .Greater => {
                self.current_compiler.?.assertType(
                    .Number,
                    context.shared.type,
                    "Unsupported operand types: must both be numbers",
                );
                self.current_compiler.?.emitOpCode(.Greater);
            },
            .GreaterEqual => {
                self.current_compiler.?.assertType(
                    .Number,
                    context.shared.type,
                    "Unsupported operand types: must both be numbers",
                );
                self.current_compiler.?.emitOpCode(.GreaterEqual);
            },
            .Less => {
                self.current_compiler.?.assertType(
                    .Number,
                    context.shared.type,
                    "Unsupported operand types: must both be numbers",
                );
                self.current_compiler.?.emitOpCode(.Less);
            },
            .LessEqual => {
                self.current_compiler.?.assertType(
                    .Number,
                    context.shared.type,
                    "Unsupported operand types: must both be numbers",
                );
                self.current_compiler.?.emitOpCode(.LessEqual);
            },

            .Plus => {
                if (context.shared.type) |value_type| {
                    if (value_type == .String) {
                        self.current_compiler.?.emitOpCode(.ConcatString);
                    } else if (value_type == .Number) {
                        self.current_compiler.?.emitOpCode(.Add);
                    } else {
                        self.current_compiler.?.err("Unsupported operand types: must both be numbers or strings", .{});
                    }
                }
            },
            .Minus => {
                self.current_compiler.?.assertType(
                    .Number,
                    context.shared.type,
                    "Unsupported operand types: must both be numbers",
                );
                self.current_compiler.?.emitOpCode(.Subtract);
            },
            .Star => {
                self.current_compiler.?.assertType(
                    .Number,
                    context.shared.type,
                    "Unsupported operand types: must both be numbers",
                );
                self.current_compiler.?.emitOpCode(.Multiply);
            },
            .Slash => {
                self.current_compiler.?.assertType(
                    .Number,
                    context.shared.type,
                    "Unsupported operand types: must both be numbers",
                );
                self.current_compiler.?.emitOpCode(.Divide);
            },
            else => return,
        }
    }

    fn and_(self: *ModuleCompiler, _: CompilationContext) void {
        const end_jump = self.current_compiler.?.emitJump(.JumpIfFalse);

        self.current_compiler.?.emitOpCode(.Pop);
        self.parsePrecedence(.And, null);

        self.current_compiler.?.patchJump(end_jump);
    }

    fn or_(self: *ModuleCompiler, _: CompilationContext) void {
        const end_jump = self.current_compiler.?.emitJump(.JumpIfTrue);

        self.current_compiler.?.emitOpCode(.Pop);
        self.parsePrecedence(.Or, null);

        self.current_compiler.?.patchJump(end_jump);
    }

    fn block(self: *ModuleCompiler) void {
        while (!self.check(.RightBrace) and !self.check(.Eof)) {
            self.declaration();
        }

        self.consume(.RightBrace, "Expect '}}' after block.", .{});
    }

    fn parsePrecedence(self: *ModuleCompiler, precedence: Precedence, shared_context: ?*SharedContext) void {
        self.advance();
        const parse_rule: *const ParseRule = self.parse_rules.getPtrConst(self.scanner.previous.token_type.?);
        const prefix_rule: *const ParseFn = parse_rule.prefix orelse {
            // The last parsed token doesn't have a prefix rule
            self.current_compiler.?.err("Expect expression.", .{});
            return;
        };

        var context = CompilationContext{
            .can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.Assignment),
        };
        if (shared_context) |assured| {
            context.shared = assured;
        } else {
            var shared = SharedContext{};
            context.shared = &shared;
        }

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

        if (context.can_assign and self.match(.Equal)) {
            self.current_compiler.?.err("Invalid assignment target.", .{});
        }
    }

    fn identifier(self: *ModuleCompiler, context: CompilationContext) void {
        const name = self.scanner.previous;

        if (context.can_assign and self.match(TokenType.Equal)) {
            // TODO: check access intent (can write ?)
            self.expression(context.shared);
            self.current_compiler.?.writeIdentifier(name.lexeme.?, context.shared.type);
        } else {
            const maybe_var_type = self.current_compiler.?.readIdentifier(name.lexeme.?, context.shared.type);
            if (maybe_var_type) |var_type| {
                context.shared.type = var_type;
            }
        }
    }

    fn stringValue(_: *ModuleCompiler, source: []const u8) values.Value {
        const dstring = objects.DoughString.copy(source);
        return values.Value.fromObject(dstring.asObject());
    }

    fn string(self: *ModuleCompiler, context: CompilationContext) void {
        if (context.shared.type) |value_type| {
            if (value_type != .String) {
                self.current_compiler.?.err("mixing types is not allowed", .{});
            }
        } else {
            context.shared.type = values.Type.makeString();
        }

        const chars = self.scanner.previous.lexeme.?[0..self.scanner.previous.lexeme.?.len];
        const dstring = self.stringValue(chars);
        const address = self.current_compiler.?.addConstant(dstring);
        self.current_compiler.?.emitOpCode(OpCode.GetConstant);
        self.current_compiler.?.emitConstantAddress(address);
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

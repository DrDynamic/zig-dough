pub const Parser = struct {
    allocator: Allocator,
    scanner: Scanner,
    ast: *AST,
    error_reporter: *const ErrorReporter,

    pub fn init(scanner: Scanner, ast_: *AST, error_reporter: *const ErrorReporter, allocator: Allocator) Parser {
        return .{
            .scanner = scanner,
            .ast = ast_,
            .error_reporter = error_reporter,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) !void {
        while (!self.match(.eof)) {
            try self.ast.addRoot(try self.declaration());
        }
    }

    fn declaration(self: *Parser) !ast.NodeId {
        if (self.match(.var_)) {
            return try self.varDeclaration();
        }
        return try self.statement();
    }

    fn varDeclaration(self: *Parser) !ast.NodeId {
        const name_id: StringId = self.parseIdentifier() catch |err| switch (err) {
            error.TokenMissMatch => {
                // TODO report error
                return error.ParserError;
            },
            else => {
                return err;
            },
        };
        const identifier_token = self.scanner.previous();

        var type_id: ?TypeId = TypePool.UNRESOLVED;
        if (self.match(.colon)) {
            // TODO parse type
            _ = self.consume(.identifier) catch |err| switch (err) {
                error.TokenMissMatch => {
                    // TODO report error
                    return error.ParserError;
                },
            };
            type_id = null;
        }

        var assignment_node_id: ast.NodeId = undefined;
        if (self.match(.equal)) {
            // TODO parse assignment
            assignment_node_id = try self.expression();
        } else {
            // TODO: make singleton?
            assignment_node_id = try self.ast.addNode(.{
                .tag = .comptime_uninitialized,
                .token_position = identifier_token.location.start,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = undefined,
            });
        }

        _ = self.match(.semicolon);

        const extra_id = try self.ast.addExtra(ast.VarDeclarationData{
            .name_id = name_id,
            .explicit_type = TypePool.UNRESOLVED,
            .init_value = assignment_node_id,
        });

        return try self.ast.addNode(.{
            .tag = .declaration_var,
            .token_position = identifier_token.location.start,
            .resolved_type_id = TypePool.UNRESOLVED,
            .data = .{ .extra_id = extra_id },
        });
    }

    // statements
    fn statement(self: *Parser) !ast.NodeId {
        return try self.expression();
    }

    // expressions
    fn expression(self: *Parser) !ast.NodeId {
        return try self.assignment();
    }

    fn assignment(self: *Parser) !ast.NodeId {
        const assignment_target = self.ternary();
        // TODO implement assignment

        return assignment_target;
    }

    fn ternary(self: *Parser) !ast.NodeId {
        const condition = try self.or_();
        // TODO implement ternary
        return condition;
    }

    fn or_(self: *Parser) !ast.NodeId {
        const lhs = try self.and_();
        // TODO implement or
        return lhs;
    }

    fn and_(self: *Parser) !ast.NodeId {
        const lhs = try self.equality();
        // TODO implement and
        return lhs;
    }

    fn equality(self: *Parser) !ast.NodeId {
        var lhs = try self.comparsion();
        search_equality: while (true) {
            const token = self.scanner.current();
            const tag: ast.NodeType = switch (token.tag) {
                .equal_equal => .binary_equal,
                .bang_equal => .binary_not_equal,
                else => break :search_equality,
            };
            _ = try self.advance();

            const rhs: ast.NodeId = try self.comparsion();
            const extra_id = try self.ast.addExtra(ast.BinaryOpData{
                .lhs = lhs,
                .rhs = rhs,
            });

            lhs = try self.ast.addNode(.{
                .tag = tag,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .extra_id = extra_id },
            });
        }
        return lhs;
    }

    fn comparsion(self: *Parser) !ast.NodeId {
        var lhs = try self.term();

        search_comparsion: while (true) {
            const token = self.scanner.current();
            const tag: ast.NodeType = switch (token.tag) {
                .greater => .binary_greater,
                .greater_equal => .binary_greater_equal,
                .less => .binary_less,
                .less_equal => .binary_less_equal,
                else => break :search_comparsion,
            };
            _ = try self.advance();

            const rhs: ast.NodeId = try self.term();
            const extra_id = try self.ast.addExtra(ast.BinaryOpData{
                .lhs = lhs,
                .rhs = rhs,
            });

            lhs = try self.ast.addNode(.{
                .tag = tag,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .extra_id = extra_id },
            });
        }

        return lhs;
    }

    fn term(self: *Parser) !ast.NodeId {
        var lhs = try self.factor();
        search_term: while (true) {
            const token = self.scanner.current();
            const tag: ast.NodeType = switch (token.tag) {
                .plus => .binary_add,
                .minus => .binary_sub,
                else => break :search_term,
            };
            _ = try self.advance();

            const rhs: ast.NodeId = try self.factor();
            const extra_id = try self.ast.addExtra(ast.BinaryOpData{
                .lhs = lhs,
                .rhs = rhs,
            });

            lhs = try self.ast.addNode(.{
                .tag = tag,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .extra_id = extra_id },
            });
        }
        return lhs;
    }

    fn factor(self: *Parser) !ast.NodeId {
        var lhs = try self.unary();
        search_factor: while (true) {
            const token = self.scanner.current();
            const tag: ast.NodeType = switch (token.tag) {
                .star => .binary_mul,
                .slash => .binary_div,
                else => break :search_factor,
            };
            _ = try self.advance();

            const rhs: ast.NodeId = try self.unary();
            const extra_id = try self.ast.addExtra(ast.BinaryOpData{
                .lhs = lhs,
                .rhs = rhs,
            });

            lhs = try self.ast.addNode(.{
                .tag = tag,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .extra_id = extra_id },
            });
        }
        return lhs;
    }

    fn unary(self: *Parser) !ast.NodeId {
        // TODO implement unary
        return try self.call();
    }

    fn call(self: *Parser) !ast.NodeId {
        const callee = try self.primary();
        // TODO implement call
        return callee;
    }

    fn primary(self: *Parser) !ast.NodeId {
        const token = try self.advance();
        return switch (token.tag) {
            .null_ => try self.ast.addNode(.{
                .tag = .literal_null,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.NULL,
                .data = undefined,
            }),
            .true_ => try self.ast.addNode(.{
                .tag = .literal_bool,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.BOOL,
                .data = .{ .bool_value = true },
            }),
            .false_ => try self.ast.addNode(.{
                .tag = .literal_bool,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.BOOL,
                .data = .{ .bool_value = false },
            }),
            .number => |_| number_case: {
                const lexeme = self.scanner.getLexeme(self.scanner.previous());
                if (std.mem.indexOfScalar(u8, lexeme, '.') != null) {
                    const val = try std.fmt.parseFloat(f64, lexeme);
                    break :number_case try self.ast.addNode(.{
                        .tag = .literal_float,
                        .token_position = token.location.start,
                        .resolved_type_id = TypePool.FLOAT,
                        .data = .{ .float_value = val },
                    });
                } else {
                    const val = try std.fmt.parseInt(i64, lexeme, 10);
                    break :number_case self.ast.addNode(.{
                        .tag = .literal_int,
                        .token_position = token.location.start,
                        .resolved_type_id = TypePool.INT,
                        .data = .{ .int_value = val },
                    });
                }
            },
            .string => |_| string_case: {
                // TODO safe string literal in extra
                break :string_case try self.ast.addNode(.{
                    .tag = .object_string,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.STRING,
                    .data = undefined,
                });
            },
            else => |tag| {
                std.debug.print("unexpected token in primary(): {s}\n", .{@tagName(tag)});
                // TODO report error
                return error.ParserError;
            },
        };
    }

    // string table
    pub fn parseIdentifier(self: *Parser) !StringId {
        const token = try self.consume(.identifier);
        const lexeme = self.scanner.getLexeme(token);
        return self.ast.string_table.add(lexeme);
    }

    // scanner interactions
    pub fn advance(self: *Parser) !Token {
        var scanner = &self.scanner;

        while (true) {
            const did_advance = scanner.advance();

            if (did_advance) {
                break;
            } else |scanner_error| {
                self.error_reporter.reportScannerError(scanner_error, self.scanner.peek());
            }
        }

        return scanner.previous();
    }

    pub fn consume(self: *Parser, token_type: TokenType) !Token {
        if (self.check(token_type)) {
            return self.advance();
        } else {
            return error.TokenMissMatch;
        }
    }

    pub fn match(self: *Parser, token_type: TokenType) bool {
        if (!self.check(token_type)) {
            return false;
        }
        _ = self.advance() catch {};
        return true;
    }

    pub fn check(self: Parser, token_type: TokenType) bool {
        return (self.scanner.current().tag == token_type);
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;

const as = @import("as");
const ErrorReporter = as.frontend.ErrorReporter;
const Scanner = as.frontend.Scanner;
const TokenType = as.frontend.TokenType;
const Token = as.frontend.Token;
const TypeId = as.frontend.TypeId;
const TypePool = as.frontend.TypePool;

const ast = as.frontend.ast;
const AST = as.frontend.AST;

const StringId = as.common.StringId;

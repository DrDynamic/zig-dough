pub const Parser = struct {
    pub const Error = error{
        UnexpectedToken,
        //
        OutOfMemory,
        ScannerError,
        TokenMissMatch,
        ListOverflow,
        InvalidCharacter,
        Overflow,
        ParserError,
    };

    allocator: Allocator,
    scanner: *Scanner,
    ast: *AST,
    error_reporter: *const ErrorReporter,

    pub fn init(scanner: *Scanner, ast_: *AST, error_reporter: *const ErrorReporter, allocator: Allocator) Parser {
        return .{
            .scanner = scanner,
            .ast = ast_,
            .error_reporter = error_reporter,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) !void {
        while (!self.check(.eof)) {
            const maybe_node_id = self.declaration();
            if (maybe_node_id) |node_id| {
                try self.ast.addRoot(node_id);
            } else |_| {
                // this statement is broken.
                self.ast.invalidate();
            }
        }
    }

    fn declaration(self: *Parser) !ast.NodeId {
        if (try self.match(.var_)) {
            return try self.varDeclaration();
        }
        return try self.statement();
    }

    fn varDeclaration(self: *Parser) !ast.NodeId {
        const name_id: StringId = self.parseIdentifier() catch |err| switch (err) {
            error.TokenMissMatch => {
                self.error_reporter.parserError(self, Error.UnexpectedToken, self.scanner.current(), "Expect variable name");
                return error.ParserError;
            },
            else => {
                return err;
            },
        };
        const identifier_token = self.scanner.previous();

        var type_id: ?TypeId = TypePool.UNRESOLVED;
        if (try self.match(.colon)) {
            _ = self.consume(.identifier) catch |err| switch (err) {
                error.TokenMissMatch => {
                    self.error_reporter.parserError(self, Error.UnexpectedToken, self.scanner.current(), "Exprect type name");
                    return error.ParserError;
                },
                else => {
                    return err;
                },
            };

            // TODO parse Type
            type_id = null;
        }

        var assignment_node_id: ast.NodeId = undefined;
        if (try self.match(.equal)) {
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

        _ = try self.match(.semicolon);

        const extra_id = try self.ast.addExtra(ast.VarDeclarationExtra{
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
        if (try self.match(.return_)) {
            return try self.returnStatement();
        }
        const node_id = try self.expression();
        _ = try self.match(.semicolon);
        return node_id;
    }

    fn returnStatement(self: *Parser) !ast.NodeId {
        const token = self.scanner.previous();
        const expr = try self.expression();
        _ = try self.match(.semicolon);
        return try self.ast.addNode(.{
            .tag = .stack_return,
            .token_position = token.location.start,
            .resolved_type_id = TypePool.UNRESOLVED,
            .data = .{ .node_id = expr },
        });
    }

    // expressions
    fn expression(self: *Parser) Error!ast.NodeId {
        return try self.assignment();
    }

    fn assignment(self: *Parser) Error!ast.NodeId {
        const assignment_target = self.ternary();
        // TODO implement assignment

        return assignment_target;
    }

    fn ternary(self: *Parser) Error!ast.NodeId {
        const condition = try self.or_();
        // TODO implement ternary
        return condition;
    }

    fn or_(self: *Parser) Error!ast.NodeId {
        const lhs = try self.and_();
        // TODO implement or
        return lhs;
    }

    fn and_(self: *Parser) Error!ast.NodeId {
        const lhs = try self.equality();
        // TODO implement and
        return lhs;
    }

    fn equality(self: *Parser) Error!ast.NodeId {
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
            const extra_id = try self.ast.addExtra(ast.BinaryOpExtra{
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

    fn comparsion(self: *Parser) Error!ast.NodeId {
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
            const extra_id = try self.ast.addExtra(ast.BinaryOpExtra{
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

    fn term(self: *Parser) Error!ast.NodeId {
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
            const extra_id = try self.ast.addExtra(ast.BinaryOpExtra{
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

    fn factor(self: *Parser) Error!ast.NodeId {
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
            const extra_id = try self.ast.addExtra(ast.BinaryOpExtra{
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

    fn unary(self: *Parser) Error!ast.NodeId {
        // TODO implement unary
        return try self.call();
    }

    fn call(self: *Parser) Error!ast.NodeId {
        var callee = try self.primary();

        while (true) {
            if (try self.match(.left_paren)) {
                const token = self.scanner.previous();
                // finish Call
                const list = try self.expressionList(.right_paren);

                const extra_id = try self.ast.addExtra(ast.CallExtra{
                    .callee = callee,
                    .args_count = list.count,
                    .args_start = list.list_start,
                });
                callee = try self.ast.addNode(.{
                    .tag = .call,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.UNRESOLVED,
                    .data = .{ .extra_id = extra_id },
                });
            } else if (try self.match(.dot)) {
                // TODO implement get expression
            } else {
                break;
            }
        }

        return callee;
    }

    /// parses a comma seperated list of expressions until end_token is found
    /// returns the number of found expressions and the start of a node_list with all expressions
    fn expressionList(self: *Parser, end_token: TokenType) Error!struct { count: u8, list_start: ast.NodeId } {
        var expression_ids: [255]ast.NodeId = undefined;
        var count: u8 = 0;
        while (!self.check(end_token)) {
            expression_ids[count] = try self.expression();

            if (count == 255) {
                return error.ListOverflow;
            }
            count += 1;
            if (!try self.match(.comma)) {
                break;
            }
        }
        _ = try self.consume(end_token);

        var list_node: ast.NodeId = undefined;
        var index: usize = count;
        while (index > 0) {
            index -= 1;
            const extra_id = try self.ast.addExtra(ast.NodeListExtra{
                .node_id = expression_ids[index],
                .next = list_node,
            });

            list_node = try self.ast.addNode(.{
                .tag = .node_list,
                .token_position = 0,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .extra_id = extra_id },
            });
        }

        return .{
            .count = count,
            .list_start = list_node,
        };
    }

    fn primary(self: *Parser) Error!ast.NodeId {
        const token = self.scanner.current();
        return switch (token.tag) {
            .null_ => |_| case: {
                _ = try self.advance();

                break :case try self.ast.addNode(.{
                    .tag = .literal_null,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.NULL,
                    .data = undefined,
                });
            },
            .true_ => |_| case: {
                _ = try self.advance();

                break :case try self.ast.addNode(.{
                    .tag = .literal_bool,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.BOOL,
                    .data = .{ .bool_value = true },
                });
            },
            .false_ => |_| case: {
                _ = try self.advance();

                break :case try self.ast.addNode(.{
                    .tag = .literal_bool,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.BOOL,
                    .data = .{ .bool_value = false },
                });
            },
            .number => |_| case: {
                _ = try self.advance();

                const lexeme = self.scanner.getLexeme(token);
                if (std.mem.indexOfScalar(u8, lexeme, '.') != null) {
                    const val = try std.fmt.parseFloat(f64, lexeme);
                    break :case try self.ast.addNode(.{
                        .tag = .literal_float,
                        .token_position = token.location.start,
                        .resolved_type_id = TypePool.FLOAT,
                        .data = .{ .float_value = val },
                    });
                } else {
                    const val = try std.fmt.parseInt(i64, lexeme, 10);
                    break :case self.ast.addNode(.{
                        .tag = .literal_int,
                        .token_position = token.location.start,
                        .resolved_type_id = TypePool.INT,
                        .data = .{ .int_value = val },
                    });
                }
            },
            .string => |_| case: {
                _ = try self.advance();

                const lexeme = self.scanner.getLexeme(token);
                const string_id = try self.ast.string_table.add(lexeme);

                // TODO safe string lexeme in extra
                break :case try self.ast.addNode(.{
                    .tag = .object_string,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.STRING,
                    .data = .{ .string_id = string_id },
                });
            },
            .identifier => |_| identifier_case: {
                const string_id = try self.parseIdentifier();
                break :identifier_case try self.ast.addNode(.{
                    .tag = .identifier_expr,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.UNRESOLVED,
                    .data = .{ .string_id = string_id },
                });
            },
            else => |tag| {
                std.debug.print("unexpected token in primary(): {s} '{s}'\n", .{ @tagName(tag), self.scanner.getLexeme(token) });
                // TODO report error
                return error.ParserError;
            },
        };
    }

    // string table
    pub fn parseIdentifier(self: *Parser) Error!StringId {
        const token = try self.consume(.identifier);
        const lexeme = self.scanner.getLexeme(token);
        return self.ast.string_table.add(lexeme);
    }

    // scanner interactions
    pub fn advance(self: *Parser) Error!Token {
        var scanner = self.scanner;

        scanner.advance() catch {
            // read tokens until the scanner finds a valid one
            // (we dont need to check for the end because at least eof is valid)
            while (true) {
                // if advance failes, the token read into scanner.next() could not be read.
                // so we need to advance two times, in order to jump over the failed token
                scanner.advance() catch continue;
                scanner.advance() catch continue;
                break;
            }
            return error.ScannerError;
        };

        return scanner.previous();
    }

    pub fn consume(self: *Parser, token_type: TokenType) Error!Token {
        if (self.check(token_type)) {
            return self.advance();
        } else {
            return error.TokenMissMatch;
        }
    }

    pub fn match(self: *Parser, token_type: TokenType) Error!bool {
        if (!self.check(token_type)) {
            return false;
        }
        _ = try self.advance();
        return true;
    }

    pub fn check(self: Parser, token_type: TokenType) bool {
        return (self.scanner.current().tag == token_type);
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;

const as = @import("as");
const ErrorReporter = as.common.reporting.ErrorReporter;
const Scanner = as.frontend.Scanner;
const TokenType = as.frontend.TokenType;
const Token = as.frontend.Token;
const TypeId = as.frontend.TypeId;
const TypePool = as.frontend.TypePool;
const ErrorType = as.frontend.ErrorType;
const ast = as.frontend.ast;
const AST = as.frontend.AST;

const StringId = as.common.StringId;

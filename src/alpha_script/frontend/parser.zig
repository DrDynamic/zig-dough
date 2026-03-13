pub const Parser = struct {
    pub const Error = error{
        UnexpectedToken,
        UndefinedType,
        UnexpectedType,
        TypeRedeclaration,
        //
        OutOfMemory,
        ScannerError,
        TokenMissMatch,
        ListOverflow,
        Overflow,
        ParserError,
    };

    allocator: Allocator,
    scanner: *Scanner,
    ast: *AST,
    error_reporter: *const ErrorReporter,

    pub fn init(scanner: *Scanner, ast: *AST, error_reporter: *const ErrorReporter, allocator: Allocator) Parser {
        return .{
            .scanner = scanner,
            .ast = ast,
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
                self.synchronize();
            }
        }
    }

    fn declaration(self: *Parser) !NodeId {
        if (try self.match(.error_)) {
            return self.declarationErrorSet();
        } else if (try self.match(.type)) {
            return self.declarationType();
        } else if (try self.match(.var_)) {
            return try self.declarationVar();
        }
        return try self.statement();
    }

    fn declarationErrorSet(self: *Parser) Error!NodeId {
        const start_token = self.scanner.previous();
        const set_name_id = try self.parseIdentifier();

        _ = self.consume(.left_brace) catch {
            self.error_reporter.parserError(self, Error.UnexpectedToken, self.scanner.current(), "expect '{{' after ErrorSet name");
            return Error.UnexpectedToken;
        };

        var error_list = std.ArrayList(TypeId).init(self.allocator);
        while (!self.check(.right_brace)) {
            const error_name_id = try self.parseIdentifier();
            const error_id = try self.ast.type_pool.getOrCreateErrorType(error_name_id);
            try error_list.append(error_id);

            if (!try self.match(.comma)) break;
        }

        _ = self.consume(.right_brace) catch {
            self.error_reporter.parserError(self, Error.UnexpectedToken, self.scanner.previous(), "expecting ',' after error name");
            return Error.UnexpectedToken;
        };

        const set_id = try self.ast.type_pool.getOrCreateErrorSet(error_list.items);
        self.ast.type_pool.declareNamedType(set_name_id, set_id) catch {
            const set_name = self.ast.string_table.get(set_name_id);
            const error_message = try std.fmt.allocPrint(self.allocator, "redaclaraction of type '{s}'", .{set_name});
            defer self.allocator.free(error_message);

            self.reportError(Error.TypeRedeclaration, start_token, error_message);
            self.reportHintToTypeDeclaration(set_name_id, "type is already declared here:");

            return Error.TypeRedeclaration;
        };

        const extra_id = try self.ast.addExtra(VarDeclarationExtra{
            .name_id = set_name_id,
            .explicit_type = set_id,
            .init_value = null,
        });
        return try self.ast.addNode(.{
            .tag = .declaration_error_set,
            .token_position = start_token.location.start,
            .resolved_type_id = set_id,
            .data = .{ .extra_id = extra_id },
        });
    }

    fn declarationType(self: *Parser) !NodeId {
        const type_token = self.scanner.previous();
        const identifier_token = self.scanner.current();

        const name_id = self.parseIdentifier() catch {
            self.reportError(Error.UnexpectedToken, self.scanner.current(), "typename must not be a keyword and start with a character or '_'");
            return Error.UnexpectedToken;
        };

        _ = self.consume(.equal) catch {
            self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect '=' after typename");
            return Error.UnexpectedToken;
        };

        const type_id = self.parseTypeDeclaration() catch |err| {
            // omit consequential errors because this type is not declared
            self.ast.type_pool.declareNamedType(name_id, TypePool.UNRESOLVED) catch undefined;
            return err;
        };

        self.ast.type_pool.declareNamedType(name_id, type_id) catch {
            const error_message = try std.fmt.allocPrint(self.allocator, "type '{s}' has already been declared", .{self.ast.string_table.get(name_id)});
            defer self.allocator.free(error_message);
            self.reportError(Error.TypeRedeclaration, identifier_token, error_message);
            self.reportHintToTypeDeclaration(name_id, "type is already declared here:");

            return Error.TypeRedeclaration;
        };

        _ = try self.match(.semicolon);

        const extra_id = try self.ast.addExtra(VarDeclarationExtra{
            .name_id = name_id,
            .explicit_type = type_id,
            .init_value = null,
        });
        return try self.ast.addNode(.{
            .tag = .declaration_type,
            .token_position = type_token.location.start,
            .resolved_type_id = type_id,
            .data = .{ .extra_id = extra_id },
        });
    }

    fn declarationVar(self: *Parser) !NodeId {
        const name_id: StringId = self.parseIdentifier() catch |err| switch (err) {
            error.TokenMissMatch => {
                self.reportError(Error.UnexpectedToken, self.scanner.current(), "Expect variable name");
                _ = try self.advance();
                _ = try self.match(.colon);
                _ = try self.match(.equal);
                return error.ParserError;
            },
            else => {
                return err;
            },
        };
        const identifier_token = self.scanner.previous();

        var type_id: TypeId = TypePool.UNRESOLVED;
        if (try self.match(.colon)) {
            type_id = try self.parseTypeReference();
        }

        var assignment_node_id: ?NodeId = null;
        if (try self.match(.equal)) {
            assignment_node_id = try self.expression();
        }

        _ = try self.match(.semicolon);

        const extra_id = try self.ast.addExtra(VarDeclarationExtra{
            .name_id = name_id,
            .explicit_type = type_id,
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
    fn statement(self: *Parser) !NodeId {
        if (try self.match(.return_)) {
            return try self.returnStatement();
        } else if (try self.match(.left_brace)) {
            const left_brace = self.scanner.previous();
            const node_id = try self.blockStatement();
            _ = self.consume(.right_brace) catch {
                self.reportError(Error.UnexpectedToken, left_brace, "expect '}' after code block");
                return Error.UnexpectedToken;
            };
            return node_id;
        }

        const node_id = try self.expression();
        _ = try self.match(.semicolon);
        return node_id;
    }

    fn blockStatement(self: *Parser) Error!NodeId {
        const left_brace = self.scanner.previous();

        var statements = std.ArrayList(NodeId).init(self.allocator);
        defer statements.deinit();

        while (!self.check(.right_brace)) {
            try statements.append(try self.declaration());
        }

        const list_start = try self.nodeListFromArray(statements.items);
        return self.ast.addNode(.{
            .tag = .expression_block,
            .token_position = left_brace.location.start,
            .resolved_type_id = TypePool.UNRESOLVED,
            .data = .{ .node_id = list_start },
        });
    }

    fn returnStatement(self: *Parser) !NodeId {
        const token = self.scanner.previous();
        const expr = try self.expression();
        _ = try self.match(.semicolon);
        return try self.ast.addNode(.{
            .tag = .call_return,
            .token_position = token.location.start,
            .resolved_type_id = TypePool.UNRESOLVED,
            .data = .{ .node_id = expr },
        });
    }

    // expressions
    fn expression(self: *Parser) Error!NodeId {
        if (try self.match(.if_)) {
            return try self.ifExpression();
        }
        return try self.assignment();
    }

    fn ifExpression(self: *Parser) Error!NodeId {
        const token_start = self.scanner.previous();
        _ = self.consume(.left_paren) catch {
            self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect '(' after 'if'");
            return Error.UnexpectedToken;
        };

        const condition = try self.expression();

        _ = self.consume(.right_paren) catch {
            self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect ')' after condition");
            return Error.UnexpectedToken;
        };

        var then_capture: ?NodeId = null;
        if (try self.match(.pipe)) {
            then_capture = try self.capture();
        }

        const then_branch = try self.statement();

        var else_capture: ?NodeId = null;
        var else_branch: ?NodeId = null;
        if (try self.match(.else_)) {
            if (try self.match(.pipe)) {
                else_capture = try self.capture();
            }
            else_branch = try self.statement();
        }

        const extra_id = try self.ast.addExtra(IfExtra{
            .condition = condition,

            .then_capture = then_capture,
            .then_branch = then_branch,

            .else_capture = else_capture,
            .else_branch = else_branch,
        });

        return try self.ast.addNode(.{
            .tag = .expression_if,
            .token_position = token_start.location.start,
            .resolved_type_id = TypePool.UNRESOLVED,
            .data = .{ .extra_id = extra_id },
        });
    }

    fn capture(self: *Parser) Error!NodeId {
        const capture_name = self.parseIdentifier() catch |err| switch (err) {
            error.TokenMissMatch => {
                self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect capture name");
                _ = try self.advance();
                return error.ParserError;
            },
            else => {
                return err;
            },
        };

        const extra_id = try self.ast.addExtra(VarDeclarationExtra{
            .name_id = capture_name,
            .explicit_type = TypePool.UNRESOLVED,
            .init_value = null,
        });

        const node_id = try self.ast.addNode(.{
            .tag = .declaration_const,
            .token_position = self.scanner.previous().location.start,
            .resolved_type_id = TypePool.UNRESOLVED,
            .data = .{ .extra_id = extra_id },
        });
        _ = self.consume(.pipe) catch {
            self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect '|' after capture");
            return Error.UnexpectedToken;
        };
        return node_id;
    }

    fn assignment(self: *Parser) Error!NodeId {
        const assignment_target_id = try self.or_();

        if (try self.match(.equal)) {
            const token_equal = self.scanner.previous();

            // TODO: allow or deny chaning assignments?
            const source_id = try self.assignment();

            const extra_id = try self.ast.addExtra(AssignmentExtra{
                .target = assignment_target_id,
                .source = source_id,
            });

            return try self.ast.addNode(.{
                .tag = .assignment,
                .token_position = token_equal.location.start,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .extra_id = extra_id },
            });
        }

        return assignment_target_id;
    }

    fn or_(self: *Parser) Error!NodeId {
        const lhs = try self.and_();

        // TODO implement or
        return lhs;
    }

    fn and_(self: *Parser) Error!NodeId {
        const lhs = try self.equality();
        // TODO implement and
        return lhs;
    }

    fn equality(self: *Parser) Error!NodeId {
        var lhs = try self.comparsion();
        search_equality: while (true) {
            const token = self.scanner.current();
            const tag: NodeType = switch (token.tag) {
                .equal_equal => .binary_equal,
                .bang_equal => .binary_not_equal,
                else => break :search_equality,
            };
            _ = try self.advance();

            const rhs: NodeId = try self.comparsion();
            const extra_id = try self.ast.addExtra(BinaryOpExtra{
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

    fn comparsion(self: *Parser) Error!NodeId {
        var lhs = try self.term();

        search_comparsion: while (true) {
            const token = self.scanner.current();
            const tag: NodeType = switch (token.tag) {
                .greater => .binary_greater,
                .greater_equal => .binary_greater_equal,
                .less => .binary_less,
                .less_equal => .binary_less_equal,
                else => break :search_comparsion,
            };
            _ = try self.advance();

            const rhs: NodeId = try self.term();
            const extra_id = try self.ast.addExtra(BinaryOpExtra{
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

    fn term(self: *Parser) Error!NodeId {
        var lhs = try self.factor();
        search_term: while (true) {
            const token = self.scanner.current();
            const tag: NodeType = switch (token.tag) {
                .plus => .binary_add,
                .minus => .binary_sub,
                else => break :search_term,
            };
            _ = try self.advance();

            const rhs: NodeId = try self.factor();
            const extra_id = try self.ast.addExtra(BinaryOpExtra{
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

    fn factor(self: *Parser) Error!NodeId {
        var lhs = try self.unary();
        search_factor: while (true) {
            const token = self.scanner.current();
            const tag: NodeType = switch (token.tag) {
                .star => .binary_mul,
                .slash => .binary_div,
                else => break :search_factor,
            };
            _ = try self.advance();

            const rhs: NodeId = try self.unary();
            const extra_id = try self.ast.addExtra(BinaryOpExtra{
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

    fn unary(self: *Parser) Error!NodeId {
        if (try self.match(.bang)) {
            const token = self.scanner.previous();
            return try self.ast.addNode(.{
                .tag = .logical_not,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .node_id = try self.unary() },
            });
        } else if (try self.match(.minus)) {
            const token = self.scanner.previous();
            return try self.ast.addNode(.{
                .tag = .negate,
                .token_position = token.location.start,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .node_id = try self.unary() },
            });
        }
        // TODO implement unary
        return try self.call();
    }

    fn call(self: *Parser) Error!NodeId {
        var callee = try self.primary();

        while (true) {
            if (try self.match(.left_paren)) {
                const token = self.scanner.previous();
                // finish Call
                const list = try self.expressionList(.right_paren);

                const extra_id = try self.ast.addExtra(CallExtra{
                    .callee = callee,
                    .args_start = list.list_start,
                });
                callee = try self.ast.addNode(.{
                    .tag = .call,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.UNRESOLVED,
                    .data = .{ .extra_id = extra_id },
                });
            } else if (try self.match(.dot)) {
                _ = self.consume(.identifier) catch {
                    self.reportError(Error.UnexpectedToken, self.scanner.current(), "Expect property name after '.'");
                    _ = try self.advance();
                    return Error.UnexpectedToken;
                };
            } else {
                break;
            }
        }

        return callee;
    }

    /// parses a comma seperated list of expressions until end_token is found
    /// returns the number of found expressions and the start of a node_list with all expressions
    fn expressionList(self: *Parser, end_token: TokenType) Error!struct { count: u8, list_start: NodeId } {
        var expression_ids: [255]NodeId = undefined;
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

        const list_start: NodeId = try self.nodeListFromArray(expression_ids[0..count]);

        return .{
            .count = count,
            .list_start = list_start,
        };
    }

    fn primary(self: *Parser) Error!NodeId {
        const token = self.scanner.current();
        return switch (token.tag) {
            .error_ => case: {
                _ = try self.advance();
                _ = self.consume(.dot) catch {
                    self.error_reporter.parserError(self, Error.UnexpectedToken, self.scanner.current(), "expect '.' after error expression");
                    return Error.UnexpectedToken;
                };

                const error_name_id = self.parseIdentifier() catch {
                    self.error_reporter.parserError(self, Error.UnexpectedToken, self.scanner.current(), "expect identifier for error expression");
                    return Error.UnexpectedToken;
                };

                const error_type_id = try self.ast.type_pool.getOrCreateErrorType(error_name_id);

                break :case self.ast.addNode(.{
                    .tag = .literal_error,
                    .token_position = self.scanner.previous().location.start,
                    .resolved_type_id = error_type_id,
                    .data = .{ .error_value = error_type_id },
                });
            },
            .null => case: {
                _ = try self.advance();

                break :case try self.ast.addNode(.{
                    .tag = .literal_null,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.NULL,
                    .data = undefined,
                });
            },
            .true => |_| case: {
                _ = try self.advance();

                break :case try self.ast.addNode(.{
                    .tag = .literal_bool,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.BOOL,
                    .data = .{ .bool_value = true },
                });
            },
            .false => |_| case: {
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
                    const val = std.fmt.parseFloat(f64, lexeme) catch {
                        self.reportError(Error.UnexpectedToken, token, "Invalid float literal");
                        return Error.UnexpectedToken;
                    };
                    break :case try self.ast.addNode(.{
                        .tag = .literal_float,
                        .token_position = token.location.start,
                        .resolved_type_id = TypePool.FLOAT,
                        .data = .{ .float_value = val },
                    });
                } else {
                    const val = std.fmt.parseInt(i64, lexeme, 10) catch {
                        self.reportError(Error.UnexpectedToken, token, "Invalid integer literal");
                        return Error.UnexpectedToken;
                    };
                    break :case self.ast.addNode(.{
                        .tag = .literal_int,
                        .token_position = token.location.start,
                        .resolved_type_id = TypePool.INT,
                        .data = .{ .int_value = val },
                    });
                }
            },
            .string_double_quote => |_| case: {
                _ = try self.advance();

                const lexeme = self.scanner.getLexeme(token);
                const string_id = try self.ast.string_table.add(lexeme);

                break :case try self.ast.addNode(.{
                    .tag = .object_string,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.STRING,
                    .data = .{ .string_id = string_id },
                });
            },
            .left_paren => |_| case: {
                const left_paren = try self.advance();
                const group = try self.ast.addNode(.{
                    .tag = .expression_grouping,
                    .token_position = left_paren.location.start, //self.scanner.previous().location.start,
                    .resolved_type_id = TypePool.UNRESOLVED,
                    .data = .{ .node_id = try self.expression() },
                });

                _ = self.consume(.right_paren) catch {
                    self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect ')' after group");
                    return Error.UnexpectedToken;
                };

                break :case group;
            },
            .identifier => |_| identifier_case: {
                const string_id = self.parseIdentifier() catch unreachable; // switch ensures that the next token is an identifier

                if (self.ast.type_pool.getType(string_id)) |set_id| {
                    if (self.ast.type_pool.isErrorSet(set_id)) {
                        _ = self.consume(.dot) catch {
                            self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect '.' in ErrorSet expression");
                            self.reportHintToTypeDeclaration(string_id, "ErrorSet is declared here:");

                            return Error.UnexpectedToken;
                        };
                        const error_name_id = self.parseIdentifier() catch {
                            self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect identifier as error name");
                            return Error.UnexpectedToken;
                        };
                        const error_type_id = try self.ast.type_pool.getOrCreateErrorType(error_name_id);

                        if (!self.ast.type_pool.isErrorInSet(set_id, error_type_id)) {
                            const error_message = try std.fmt.allocPrint(self.allocator, "Error '{s}' does not exists in ErrorSet '{s}'", .{
                                self.ast.string_table.get(error_name_id),
                                self.ast.string_table.get(string_id),
                            });
                            defer self.allocator.free(error_message);

                            self.reportError(Error.UndefinedType, self.scanner.previous(), error_message);
                            self.reportHintToTypeDeclaration(string_id, "ErrorSet:");
                            return Error.UndefinedType;
                        }

                        break :identifier_case try self.ast.addNode(.{
                            .tag = .literal_error,
                            .token_position = token.location.start,
                            .resolved_type_id = error_type_id,
                            .data = .{ .error_value = error_type_id },
                        });
                    }
                }

                break :identifier_case try self.ast.addNode(.{
                    .tag = .identifier_expr,
                    .token_position = token.location.start,
                    .resolved_type_id = TypePool.UNRESOLVED,
                    .data = .{ .string_id = string_id },
                });
            },
            else => |_| {
                self.reportError(Error.UnexpectedToken, token, "expression expected");
                _ = try self.advance();
                return Error.UnexpectedToken;
            },
        };
    }

    // types

    fn parseTypeDeclaration(self: *Parser) !TypeId {
        return try self.parseTypeUnion();
    }

    fn parseTypeReference(self: *Parser) !TypeId {
        // const a:Error!?int
        // const a:Error!int|string
        return try self.parseTypeErrorUnion();
    }

    fn parseTypeErrorUnion(self: *Parser) !TypeId {
        var maybe_error_type: ?TypeId = null;

        if (self.scanner.current().tag == .bang) {
            maybe_error_type = TypePool.ANYERROR;
            _ = self.consume(.bang) catch unreachable;
        } else if (self.scanner.next().tag == .bang) {
            maybe_error_type = try self.parseTypeErrorSet();
            _ = self.consume(.bang) catch unreachable;
        }

        if (maybe_error_type) |error_type| {
            const members = [_]u32{
                error_type,
                try self.parseTypeUnion(),
            };

            return try self.ast.type_pool.getOrCreateUnionType(&members);
        } else {
            return try self.parseTypeUnion();
        }
    }

    fn parseTypeErrorSet(self: *Parser) !TypeId {
        const error_name_id = self.parseIdentifier() catch {
            self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect identifier or nothing as error type");
            return Error.UnexpectedToken;
        };

        const error_set_id = self.ast.type_pool.getType(error_name_id) orelse {
            self.reportError(Error.UndefinedType, self.scanner.previous(), "Undefined ErrorSet");
            return Error.UndefinedType;
        };

        if (self.ast.type_pool.types.items[error_set_id] != .error_set) {
            self.reportError(Error.UnexpectedType, self.scanner.previous(), "expect ErrorSet");
            return Error.UnexpectedType;
        }

        return error_set_id;
    }

    fn parseTypeUnion(self: *Parser) !TypeId {
        var members = std.ArrayList(TypeId).init(self.allocator);
        defer members.deinit();

        var nullable_token: ?Token = null;
        if (try self.match(.question_mark)) {
            nullable_token = self.scanner.previous();
        }
        try members.append(try self.parseTypePrimary());

        while (try self.match(.pipe)) {
            if (try self.match(.question_mark)) {
                nullable_token = self.scanner.previous();
            }
            try members.append(try self.parseTypePrimary());
        }

        if (members.items.len == 1) {
            // its a single type with nullable shorthand
            if (nullable_token != null) {
                try members.append(TypePool.NULL);
                return self.ast.type_pool.getOrCreateUnionType(members.items);
            }

            // its just a single type
            return members.items[0];
        } else {
            const union_type_id = try self.ast.type_pool.getOrCreateUnionType(members.items);

            // its a type union with nullable shorthand somewhere
            if (nullable_token) |token| {
                const union_name = try self.ast.type_pool.getTypeNameAlloc(self.allocator, union_type_id, self.ast.string_table);
                defer self.allocator.free(union_name);

                self.reportError(Error.UnexpectedToken, token, "nullable shorthand '?' cannot be applied to type unions");

                const hint_message = try std.fmt.allocPrint(self.allocator, "but you can just add the null type like: null|{s}", .{union_name});
                defer self.allocator.free(hint_message);

                self.reportHint(null, hint_message);

                return Error.UnexpectedToken;
            }

            return union_type_id;
        }
    }

    fn parseTypePrimary(self: *Parser) !TypeId {
        const token = self.scanner.current();

        return switch (token.tag) {
            .Void => case: {
                _ = try self.advance();
                break :case TypePool.VOID;
            },
            .Null => case: {
                _ = try self.advance();
                break :case TypePool.NULL;
            },
            .Bool => case: {
                _ = try self.advance();
                break :case TypePool.BOOL;
            },
            .Int => case: {
                _ = try self.advance();
                break :case TypePool.INT;
            },
            .Float => case: {
                _ = try self.advance();
                break :case TypePool.FLOAT;
            },
            .String => case: {
                _ = try self.advance();
                break :case TypePool.STRING;
            },
            .Anyerror => case: {
                _ = try self.advance();
                break :case TypePool.ANYERROR;
            },
            .identifier => case: {
                const name_id = try self.parseIdentifier();
                break :case self.ast.type_pool.getType(name_id) orelse {
                    self.reportError(Error.UndefinedType, self.scanner.previous(), "Undefined type");
                    return Error.UndefinedType;
                };
            },
            else => {
                self.reportError(Error.UnexpectedToken, self.scanner.current(), "expect type");
                return Error.UnexpectedToken;
            },
        };
    }

    // string table
    pub fn parseIdentifier(self: *Parser) Error!StringId {
        const token = try self.consume(.identifier);
        const lexeme = self.scanner.getLexeme(token);
        return self.ast.string_table.add(lexeme);
    }

    // node list
    pub fn nodeListFromArray(self: *const Parser, node_ids: []NodeId) Error!NodeId {
        assert(node_ids.len > 0);
        var list_node: ?NodeId = null;
        var index: usize = node_ids.len;
        while (index > 0) {
            index -= 1;
            const extra_id = try self.ast.addExtra(NodeListExtra{
                .node_id = node_ids[index],
                .next = list_node,
            });

            list_node = try self.ast.addNode(.{
                .tag = .node_list,
                .token_position = 0,
                .resolved_type_id = TypePool.UNRESOLVED,
                .data = .{ .extra_id = extra_id },
            });
        }

        return list_node.?;
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
        // TODO: schouldn't consume return Error!void?
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

    pub fn synchronize(self: *Parser) void {
        _ = self.advance() catch undefined;

        while (self.scanner.current().tag != .eof) {
            switch (self.scanner.current().tag) {
                .left_bracket,
                .const_,
                .for_,
                .function,
                .if_,
                .return_,
                .type,
                .var_,
                .while_,
                => return,
                .semicolon => {
                    _ = self.advance() catch undefined;
                    return;
                },
                else => {},
            }
            _ = self.advance() catch undefined;
        }
    }

    pub inline fn reportError(self: *const Parser, err: Error, token: Token, message: []const u8) void {
        self.error_reporter.parserError(self, err, token, message);
    }

    pub inline fn reportHint(self: *const Parser, token: ?Token, message: []const u8) void {
        self.error_reporter.parserHint(self, token, message);
    }

    pub inline fn reportHintToTypeDeclaration(self: *const Parser, type_name_id: StringId, message: []const u8) void {
        for (self.ast.nodes.items) |node| {
            if (node.tag == .declaration_type or node.tag == .declaration_error_set) {
                const extra = self.ast.getExtra(node.data.extra_id, VarDeclarationExtra);
                if (extra.name_id == type_name_id) {
                    const token = self.ast.scanner.token_stream.scanPosition(node.token_position) catch unreachable;
                    self.reportHint(token, message);
                }
            }
        }
    }
};

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const as = @import("as");
const ErrorReporter = as.common.reporting.ErrorReporter;
const Scanner = as.frontend.Scanner;
const TokenType = as.frontend.TokenType;
const Token = as.frontend.Token;
const TypeId = as.frontend.TypeId;
const TypePool = as.frontend.TypePool;
const ErrorType = as.frontend.ErrorType;
const AST = as.frontend.AST;
const NodeId = as.frontend.ast.NodeId;
const StringId = as.common.StringId;
const NodeType = as.frontend.ast.NodeType;

const VarDeclarationExtra = as.frontend.ast.VarDeclarationExtra;
const BinaryOpExtra = as.frontend.ast.BinaryOpExtra;
const CallExtra = as.frontend.ast.CallExtra;
const NodeListExtra = as.frontend.ast.NodeListExtra;
const IfExtra = as.frontend.ast.IfExtra;
const AssignmentExtra = as.frontend.ast.AssignmentExtra;

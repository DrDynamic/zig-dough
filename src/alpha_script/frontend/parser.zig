pub const Parser = struct {
    allocator: Allocator,
    scanner: Scanner,
    ast: *AST,

    pub fn init(scanner: Scanner, ast: *AST, allocator: Allocator) Parser {
        return .{
            .scanner = scanner,
            .ast = ast,
            .allocatior = allocator,
        };
    }

    pub fn parse(self: *Parser) void {
        while (!self.match(.Eof)) {
            self.declaration();
        }
    }

    fn decleration(self: Parser) !ast.NodeId {
        if (self.match(.Var)) {
            return self.varDeclaration();
        }
    }

    fn varDeclaration(self: Parser) !ast.NodeId {
        const name_id = self.parseIdentifier() catch |err| switch (err) {
            error.TokenMissMatch => {
                // TODO report error
                return;
            },
            else => err,
        };

        var type_id = TypePool.UNRESOLVED;
        if (self.match(.Colon)) {
            // TODO parse type
            type_id = null;
        }

        var assignment_node_id: ?ast.NodeId = null;
        if (self.match(.Equal)) {
            // TODO parse assignment
            assignment_node_id = null;
        }

        _ = self.match(.Semicolon);

        const extra_id = try self.ast.addExtra(ast.VarDeclarationData{
            .name_id = name_id,
            .init_value = assignment_node_id,
        });

        return self.ast.addNode(.{
            .tag = .var_declaration,
            .extra_id = extra_id,
        });
    }

    // expressions
    fn expression(self: *Parser) !ast.NodeId {
        return self.assignment();
    }

    fn assignment(self: *Parser) !ast.NodeId {
        const assignment_target = self.ternary();
        // TODO implement assignment

        return assignment_target;
    }

    fn ternary(self: *Parser) !ast.NodeId {
        const condition = self.or_();
        // TODO implement ternary
        return condition;
    }

    fn or_(self: *Parser) !ast.NodeId {
        const lhs = self.and_();
        // TODO implement or
        return lhs;
    }

    fn and_(self: *Parser) !ast.NodeId {
        const lhs = self.equality();
        // TODO implement and
        return lhs;
    }

    fn equality(self: *Parser) !ast.NodeId {
        const lhs = self.comparsion();
        // TODO implement equality
        return lhs;
    }

    fn comparsion(self: *Parser) !ast.NodeId {
        const lhs = self.term();
        // TODO implement comparsion
        return lhs;
    }

    fn term(self: *Parser) !ast.NodeId {
        const lhs = self.factor();
        // TODO implement term
        return lhs;
    }

    fn factor(self: *Parser) !ast.NodeId {
        const lhs = self.unary();
        // TODO implement factor
        return lhs;
    }

    fn unary(self: *Parser) !ast.NodeId {
        // TODO implement unary
        return self.call();
    }

    fn call(self: *Parser) !ast.NodeId {
        const callee = self.primary();
        // TODO implement call
        return callee;
    }

    fn primary(self: *Parser) !ast.NodeId {
        switch (true) {
            self.match(.null_) => self.ast.addNode(.{
                .tag = .null_literal,
            }),
            self.match(.true_) => self.ast.addNode(.{
                .tag = .bool_literal,
                .data = .{ .bool_value = true },
            }),
            self.match(.false_) => self.ast.addNode(.{
                .tag = .bool_literal,
                .data = .{ .bool_value = false },
            }),
        }
    }

    // string table
    pub fn parseIdentifier(self: *Parser) !StringId {
        const token = try self.consume(.identifier);
        return self.ast.string_table.add(token.lexeme);
    }

    // scanner interactions
    pub fn advance(self: *Parser) !Token {
        var scanner = &self.scanner;

        while (true) {
            scanner.scanToken();
            if (scanner.current.token_type != TokenType.ScannerError) break;

            return error.ScannerError;
        }

        return scanner.previous;
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
        _ = self.advance();
        return true;
    }

    pub fn check(self: Parser, token_type: TokenType) bool {
        return (self.scanner.current.tag.? == token_type);
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;

const as = @import("as");
const Scanner = as.frontend.Scanner;
const TokenType = as.frontend.TokenType;
const Token = as.frontend.Token;
const TypeId = as.frontend.TypeId;
const TypePool = as.frontend.TypePool;

const ast = as.frontend.ast;
const AST = as.frontend.AST;

const StringId = as.common.StringId;

// Debugging
pub const debug = @import("debug/debug.zig");
pub const AstPrinter = debug.ASTPrinter;

// Lexing (Sourcecode -> Tokens)
pub const Scanner = @import("scanner.zig").Scanner;

const token = @import("token.zig");
pub const TokenType = token.TokenType;
pub const Token = token.Token;

// Parsing (Tokens -> AST)
pub const Parser = @import("parser.zig").Parser;

pub const ast = @import("ast.zig");
pub const NodeInd = ast.NodeId;
pub const NodeType = ast.NodeType;
pub const Node = ast.Node;
pub const AST = ast.AST;

const type_pool = @import("type_pool.zig");
pub const TypeId = type_pool.TypeId;
pub const TypeTag = type_pool.TypeTag;
pub const Type = type_pool.Type;
pub const TypePool = type_pool.TypePool;

const scope = @import("scope.zig");
pub const Symbol = scope.Symbol;
pub const SymbolTable = scope.SymbolTable;

pub const SemanticAnalyzer = @import("semantic_analyzer.zig").SemanticAnalyzer;

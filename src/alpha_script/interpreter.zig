pub const CompilerOptions = struct {
    terminal: as.common.Terminal,
    print_tokens: bool = false,
    print_ast: bool = false,
};

pub const BuildinFunction = struct {
    name_id: StringId,
    type_id: TypeId,
    function: NativeFn,
};

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    error_reporter: ErrorReporter,
    garbage_collector: GarbageCollector,
    string_table: StringTable,
    error_pool: ErrorPool,

    parser: Parser,
    semantic_analyser: SemanticAnalyser,
    compiler: Compiler,
    virtual_machine: VirtualMachine,

    /// temporary workaround to insert natives without import system
    buildinFunctions: std.ArrayList(BuildinFunction),

    //    register_natives_hook: ?*const fn (ast: *AST, semantic_analyser: *SemanticAnalyser, compiler: *Compiler, vm: *VirtualMachine) void,

    pub fn init(error_reporter: ErrorReporter, allocator: std.mem.Allocator) !*Interpreter {
        var interpreter = try allocator.create(Interpreter);
        interpreter.* = .{
            .allocator = allocator,
            .error_reporter = error_reporter,
            .garbage_collector = GarbageCollector.init(allocator),
            .string_table = StringTable.init(allocator),
            .error_pool = ErrorPool.init(allocator),

            .parser = undefined,
            .semantic_analyser = undefined,
            .compiler = undefined,
            .virtual_machine = undefined,

            .buildinFunctions = std.ArrayList(BuildinFunction).init(allocator),
        };

        interpreter.garbage_collector.stress_mode = true;

        interpreter.parser = Parser.init(&interpreter.string_table, &interpreter.error_pool, &interpreter.error_reporter, allocator);
        interpreter.semantic_analyser = SemanticAnalyser.init(&interpreter.error_reporter, allocator);
        interpreter.compiler = Compiler.init(&interpreter.error_reporter, &interpreter.garbage_collector, allocator);
        interpreter.virtual_machine = VirtualMachine.init(&interpreter.string_table, &interpreter.error_pool, &interpreter.error_reporter, &interpreter.garbage_collector, allocator);

        interpreter.garbage_collector.watchCompiler(&interpreter.compiler);
        interpreter.garbage_collector.watchVirtualMachine(&interpreter.virtual_machine);

        return interpreter;
    }

    pub fn deinit(self: *Interpreter) void {
        self.string_table.deinit();
        self.error_pool.deinit();
        self.semantic_analyser.deinit();
        self.compiler.deinit();
        self.buildinFunctions.deinit();
    }

    pub fn registerBuildinFunction(self: *Interpreter, buildin: BuildinFunction) !void {
        try self.buildinFunctions.append(buildin);
    }

    pub fn compileModule(self: *Interpreter, filename: []const u8, compiler_options: CompilerOptions) !*ObjModule {
        const token_stream = try self.readFile(filename);
        defer self.allocator.free(token_stream.source);

        var scanner = try Scanner.init(token_stream, &self.error_reporter);

        if (compiler_options.print_tokens) {
            try as.frontend.debug.TokenPrinter.printTokens(&scanner, compiler_options.terminal.writer);
            try scanner.reset();
        }

        var ast = try self.parser.parse(&scanner);
        defer ast.deinit();
        if (!ast.is_valid) {
            return error.InvalidAST;
        }

        self.semantic_analyser.analyseAst(&ast, self.buildinFunctions.items);
        if (!ast.is_valid) {
            return error.InvalidAST;
        }

        if (compiler_options.print_ast) {
            try as.frontend.debug.ASTPrinter.printAST(&ast, &compiler_options.terminal);
        }

        return self.compiler.compile(&ast, self.buildinFunctions.items);
    }

    pub fn runModule(self: *Interpreter, module: *ObjModule) !void {
        try self.virtual_machine.execute(module, self.buildinFunctions.items);
    }

    pub fn readFile(self: *Interpreter, filename: []const u8) !TokenStream {
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const source = try file.readToEndAllocOptions(self.allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);

        return TokenStream.init(filename, source, self.error_reporter);
    }
};

const std = @import("std");
const as = @import("as");

const StringId = as.common.StringId;
const TypeId = as.frontend.TypeId;
const NativeFn = as.runtime.values.natives.NativeFn;

const ErrorReporter = as.common.reporting.ErrorReporter;
const GarbageCollector = as.common.memory.GarbageCollector;
const StringTable = as.common.StringTable;
const TokenStream = as.frontend.TokenStream;
const ErrorPool = as.frontend.ErrorPool;
const Scanner = as.frontend.Scanner;
const Parser = as.frontend.Parser;
const SemanticAnalyser = as.frontend.SemanticAnalyzer;
const Compiler = as.compiler.Compiler;
const VirtualMachine = as.runtime.VirtualMachine;

const AST = as.frontend.AST;
const ObjModule = as.runtime.values.ObjModule;

# THE OFFICIAL PAZ LANGUAGE SPECIFICATION (v1.1 STANDARD)

## 1. CORE PHILOSOPHY & GLOBAL DEFAULTS

PAZ combines the ergonomic ease and high development speed of modern scripting and typed languages (TypeScript, PHP 8+) with the uncompromising strictness, type safety, and predictability of modern systems languages (Zig, Rust).

### 1.1 Explicitness Over Magic

* There is no implicit `null`, `undefined`, or uninitialized memory.
* Any deviation from the standard control flow (errors, optional values, missing keys in structures) must be explicitly visible and handled both in the type system and the source code.

### 1.2 Closed by Default

* Maximum encapsulation at all levels.
* All symbols within a module, as well as all properties and methods within a class, are private (`priv`) by default.
* Global or external access is only possible if a symbol is explicitly exported or declared using the `pub` keyword.

### 1.3 Immutability by Default

* Data structures and variables declared with the `const` keyword are **deeply immutable (Deep Readonly)**. The compiler radically optimizes these structures.
* Only bindings explicitly declared with `var` allow mutations at runtime.

### 1.4 Avoiding Keyword Inflation

* PAZ keeps the parser lean and the syntax clean. Instead of introducing a new keyword for every new feature, existing constructs (such as attributes `[MyAttribute]` or type operators) are syntactically reused.

### 1.5 Memory Management (Runtime Core)

* PAZ utilizes a highly performant, modern **Generational Mark & Sweep Garbage Collector**.
* Since backend infrastructures generate massive amounts of short-lived objects when processing web requests or API calls, the collector's *Young Generation* cleans up the heap extremely fast, minimizing latencies (pause times) to the millisecond range.

---

## 2. VARIABLES, DATA TYPES & UNIVERSAL OPERATORS

### 2.1 Declaration & Mutability

```typescript
const x = 42       // Deeply immutable, optimized in memory.
var y = 100        // Mutable.
y = y + 5          // Valid mutation.

```

### 2.2 The All-Purpose Concatenation Operator (++)

The mathematical `+` is reserved exclusively for numerical calculations. The `++` operator is used for all operations involving merging, concatenation, and fusing.

* **Strict Type Homogeneity:** The operator demands strict type homogeneity ($T \text{ ++ } T \rightarrow T$). Implicit casting of different types is forbidden.

```typescript
// Strings
const greeting = "Hello " ++ "World" // Result: "Hello World"
// const err_log = "Status: " ++ 404 // COMPILE ERROR: Type mixing illegal!

// Arrays
const numbers = [1, 2] ++ [3, 4]   // Result: [1, 2, 3, 4]

// Shapes (Merging / Fusion)
// The right side overwrites the left side if keys match.
const final_config = defaults ++ user_config 

```

### 2.3 The Spread Operator (...)

Allows copying, extending, and partially overwriting shapes and arrays within an immutable context:

```typescript
const base = { id: 1, role: "guest" }
const admin = { ...base, role: "admin", permissions: ["all"] }

```

### 2.4 String Interpolation

Variables and expressions are evaluated directly inside strings using curly braces. This eliminates the need for casts when concatenating:

```typescript
const id = 404
const message = "Numeric ID: {id}" // Allowed and safe

```

---

## 3. THE TYPE SYSTEM & NULL-SAFETY

### 3.1 Optionals (?T)

Marks values that can either be present or be `null`. Unwrapping an optional is strictly mandated by the compiler and is done via the `orelse` keyword or Type Narrowing.

```typescript
const name: ?string = get_name()
const final_name = name orelse "Anonymous Guest"

```

### 3.2 Error Unions (!T)

Functions that can fail return an Error Union. Handling is enforced by the compiler. Two control flows are available:

* `try`: Directly passes the error up to the calling scope (Early Return).
* `catch`: Catches the error locally and opens a fallback block with safe access to the error object via the capture symbol `|err|`.

```typescript
// Option 1: Passing it up via try
const file = try open_file("config.json")

// Option 2: Catching it via catch
const data = open_file("config.json") catch |err| {
    log.error("Error opening file: {err}")
    return default_data
}

```

### 3.3 Union Types (|) & Type Narrowing (is)

Variables can hold values that span multiple types. Type checking and safe, compiler-verified unwrapping (Type Narrowing) are performed using the infix operator `is`. Within the scope of the conditional block, the compiler guarantees the narrowed type.

```typescript
type Id = u64 | string

fn process_id(id: Id) {
    if (id is string) {
        // 'id' is guaranteed to be of type string here
        print("String-UUID: {id.to_upper()}")
    } else {
        // 'id' is guaranteed to be u64 in the else branch
        print("Numeric ID: {id}")
    }
}

```

### 3.4 Intersection Types (&)

Merges existing structural types (Shapes) into a new, combined type:

```typescript
type Timestamps = { created_at: u64 }
type UserData = { name: string }
type UserRow = UserData & Timestamps

```

---

## 4. SHAPES (ANONYMOUS STRUCTURAL TYPES)

Shapes are extremely performant, anonymous, structural type definitions without class overhead. They work on the principle of compiler-checked *Duck Typing* and are optimized for DTOs, JSON parsing, and configurations.

### 4.1 Exact Symmetry with Optional Keys & Values

The syntax strictly distinguishes between a missing key and a key whose value is `null`. If a key is allowed to be missing, the compiler strictly requires an Error Union (`!`) in the type declaration, as accessing a non-existent key throws a controlled error.

* `key: string` $\rightarrow$ Key **must** exist, value **cannot** be `null`.
* `key: ?string` $\rightarrow$ Key **must** exist, value **can** be `null` (accessed via `orelse`).
* `?key: !string` $\rightarrow$ Key **can be missing**. If present, it's an error-free `string` (accessed via `catch`).
* `?key: !?string` $\rightarrow$ Key **can be missing**. If present, the value can also be `null` (accessed using a combination of `catch` and `orelse`).

```typescript
type UserPayload = {
    id: u64,
    bio: ?string,
    ?age: !u8,
    ?website: !?string,
}

fn parse_payload(p: UserPayload) {
    const bio = p.bio orelse "No bio available"
    const age = p.age catch 18
    const site = (p.website catch null) orelse "nexus.dev"
}

```

### 4.2 Methods in Shapes

Shapes can contain function signatures. Any class or object literal that structurally fulfills these signatures is fully compatible without explicit declaration (acting as an interface replacement).

```typescript
type Transactionable = {
    begin: fn(): void,
    commit: fn(): void,
    rollback: fn(): void,
}

```

---

## 5. FUNCTIONS, CLOSURES & FUNCTION PARAMETERS

Anonymous functions and closures strictly use the `fn` keyword as an unambiguous parser anchor and placeholder for generics.

### 5.1 Syntax Variants

* **Expression Body (Oneliners):** Uses the arrow `=>`. Curly braces are omitted, and the expression is **implicitly returned**.
* **Block Body (Multiliners):** Uses curly braces `{}` **without** an arrow. Requires an explicit `return`.

```rust
// Oneliner with implicit return
const doubled = numbers.map(fn(n) => n * 2)

// With generics and typing
const identity = fn<T>(val: T): T => val

// Multiliner with explicit block and return
const dynamic = numbers.filter(fn(n) {
    if (n < 0) return false
    return check_validity(n)
})

```

### 5.2 Function Parameters & References

* **Default Behavior:** Function parameters are always `const` (Deep Readonly) by default. Trying to mutate a parameter inside a function triggers a compiler error.
* **Explicit Reference Passing (&var):** If a function needs to directly manipulate or overwrite the caller's original source (Pass-by-Reference), the parameter must be explicitly declared as `&var`.

```rust
fn increment(&var counter: u32):void {
    counter += 1 // Directly manipulates the caller's variable
}

pub fn main():void {
    var my_counter = 10
    increment(&var my_counter) // Requires explicit marking at the call site
    // my_counter is now 11
}

```

---

## 6. OBJECT-ORIENTED PROGRAMMING (OOP)

### 6.1 Visibilities

* `priv` (Default case): Access exclusively within its own class or the current module.
* `pub`: Global, public access.
* `prot`: Access for its own class and all child classes inheriting via `extends`.

### 6.2 Constructor Property Promotion

The constructor is defined via the magic method `__construct`. If arguments in the constructor include a visibility keyword (`pub`, `priv`, `prot`), the compiler automatically declares and assigns them as instance properties.

```rust
class User {
    // Automatically generates fields 'id', 'email', and 'password_hash'
    pub fn __construct(
        pub id: u64,
        pub email: string,
        priv password_hash: string
    ) {}
}

```

### 6.3 Generics & Traits

Classes and methods support parametric polymorphism via `<T>`. Reusing behavioral building blocks without inheritance chains is done through the native concept of `traits`.

---

## 7. ENUMS (BACKED-ENUM MODEL)

Cases inside an enum must be separated by commas. Enums can contain their own methods.

* **Pure Enums:** Automatically handled by the compiler as sequential integers under the hood (`u32`, starting at 0).
* **Backed Enums:** Given an explicit scalar type annotation (`string`, `i32`, `u16`, etc.). Every case must be assigned manually.

### 7.1 Native API: .value and .from()

Every enum has a `.value` property (returns the raw value) and a static `.from(raw)` method. Since parsing a raw value can fail, `.from()` returns an **Error Union (!T)**.

```rust
pub enum HttpCode: u16 {
    ok = 200,
    created = 201,
    bad_request = 400,
}

fn handle(raw: u16) {
    // Catches parsing failures and falls back to a default
    const code = HttpCode.from(raw) catch HttpCode.bad_request
    print("Code is: {code.value}")
}

```

---

## 8. CONTROL FLOW & PATTERN MATCHING

### 8.1 If-Expressions

These replace the classic ternary operator. If both branches consist of a single expression, the curly braces are omitted and the assigned value is returned. Semicolons or `return` statements inside the expression are illegal.

```rust
const access = if (user.is_admin) "allowed" else "denied"

```

### 8.2 Block Labels & Value-Breaks

Blocks and loops can be named (`label:`). `break` and `continue` can target these labels specifically. Additionally, isolated blocks can return values as expressions via `break :label value`.

```rust
const fallback_url = blk: {
    log.warn("No URL defined, calculating fallback...")
    break :blk "http://localhost:8080"
}

```

### 8.3 Defer

Guarantees the execution of a statement or block when leaving the current scope—regardless of whether the scope exits normally, via an error, or through a system-wide panic. Perfect for closing resources.

```rust
const file = try open_file()
defer file.close() // Absolutely guaranteed to run at the end of the function

```

### 8.4 The Extended switch Expression (Pattern Matching & Narrowing)

In PAZ, `switch` and `match` are unified into a single powerful construct. A `switch` can return values as an expression, match exact values, and perform **Type Narrowing** using the `is` operator.

#### Compiler Behavior Rules for switch:

1. **Sequential Evaluation (Top-to-Bottom):** Conditions are evaluated strictly from top to bottom. The first match wins.
2. **Compiler-Enforced Specificity (Dead Code Detection):** To prevent logical bugs, the compiler forbids pattern shadowing. A general pattern (e.g., `is u64`) **cannot** be placed before a specific pattern (e.g., the value `404`). If a branch is unreachable, compilation fails.

```rust
type Id = u64 | string
const id: Id = 404

const display_name = switch (id) {
    404       => "Legacy Code",  // Specific value match first!
    is string => id.to_upper(),  // Type check including type narrowing to string
    is u64    => "ID-" ++ id,    // Type check including type narrowing to u64
    else      => "Unknown",      // Mandatory fallback branch
}

```

---

## 9. METAPROGRAMMING & MODULE SYSTEM

### 9.1 Module System & @import

Every PAZ file is an implicit module. Symbols must be exported using `pub`. The compiler builtin `@import` accepts a string path and behaves intelligently:

* **Standard Library:** `@import("std/submodule")`
* **External Packages:** `@import("logger")` (automatically searches in `paz_modules/`)
* **Relative Paths:** `@import("./models/user.paz")`
* **Absolute Paths (from Projectdir as root)** `@import("#/app/models/user.paz")`
* **Static Assets:** Detects file extensions. JSON is parsed at compile-time as a valid Shape; images or binaries are embedded as byte arrays.
* **FFI** `@import("./my_lib.so")` creates a FFI object ("std/ffi") to define c definitions and call functions from the library.  
* **Destructuring:** `const { Server, Response } = @import("std/http")`

### 9.2 Behavior: Passive Attributes ([...])

Inherit from the abstract base class `std/meta.Attribute`. They serve as purely decorative metadata ("sticky notes") for frameworks, do not alter the control flow on their own, and are read at runtime via the Reflection API (`std/reflect`).

* **Syntax Rule:** Attributes must stand **directly before** the declaration they are attached to.

```rust
class Route extends Attribute {
    pub fn __construct(pub path: string) {}
}

[Route("/api/v1")]
pub class ApiController {}

```

### 9.3 Behavior: Active Decorators (#[... ])

Inherit from the abstract base class `std/meta.Decorator`. They actively intercept the control flow, modifying or wrapping the target function (Higher-Order Function principle). They must implement the method `wrap(target: fn, ...args: any): any`.

```rust
class Logged extends Decorator {
    pub fn wrap(target: fn, ...args: any): any {
        print("Before function call")
        defer print("After function call")
        return target(...args)
    }
}

#[Logged]
fn execute_heavy_logic():void { ... }

```

### 9.4 System Interfaces: [Native]

A built-in compiler attribute. Marks functions that have no body but are instead bound directly to native symbols of the underlying runtime.

```rust
[Native("sys_socket_read")]
pub fn read_socket(handle: u64): ![]u8

```

---

## 10. ASYNCHRONY, CONCURRENCY & CONTEXT

PAZ features a highly performant, integrated event loop operating on lightweight green threads (**Fibers**).

### 10.1 spawn & await

* `spawn`: Starts an asynchronous task (fiber) in the background and returns a `Future<T>` object.
* `await`: Blocks the current task in a *non-blocking* way for the event loop until the result of the async task is ready.

### 10.2 The Shared-Nothing Model of Fibers

* Data passed to a newly spawned fiber is **strictly immutable (const Deep Readonly)** within that fiber's scope.
* This eliminates race conditions and data corruption on the heap. If data needs to be modified, the fiber must initially copy it into its own local `var`.

### 10.3 The Future Specification (std/async/future.paz)

The `Future` object adopts the familiar ergonomics of JavaScript Promises but is deeply integrated with PAZ's safety features.

#### The Cancellation Model (Cooperative Unwinding):

If `.cancel()` is called or a `.timeout()` expires, the runtime does not brutally kill the thread. Instead, it injects a cancellation error (`error.Cancelled` / `error.Timeout`) at the next asynchronous barrier. The fiber winds down in a controlled manner, guaranteeing that **all registered defer blocks are executed** (No resource leaks!).

```rust
// Excerpt from std/async/future.paz
pub class Future<T> {
    priv fiber_handle: u64
    priv timeout_ms: ?u64

    [Native("sys_future_init")]
    priv fn __construct(priv fiber_handle: u64) {}

    pub fn timeout(ms: u64): Future<T> {
        this.timeout_ms = ms
        this.register_native_timeout(ms)
        return this
    }

    [Native("sys_future_cancel")]
    pub fn cancel(): void

    pub fn then<R>(callback: fn(value: T): R): Future<R> {
        const next_handle = this.native_register_then(callback)
        return new Future<R>(next_handle)
    }

    pub fn catch(callback: fn(err: any): void): Future<T> {
        this.native_register_catch(callback)
        return this
    }

    pub fn finally(callback: fn(): void): Future<T> {
        this.native_register_finally(callback)
        return this
    }
    
    // Native FFI bridges omitted in this overview...
}

```

**Usage Example:**

```rust
const http = @import("std/http")

pub fn fetch() {
    const task = spawn fn() => http.get("https://api.nexus.dev/data")

    task.timeout(2000)
        .then(fn(res) => print("Success: {res.body}"))
        .catch(fn(err) => print("Error or Timeout: {err}"))
        .finally(fn() => print("Done."))
}

```

### 10.4 Context Preservation (std/async/context.paz)

Because fibers jump around asynchronously, the Context module solves the issue of passing request data (like request IDs or sessions) through the application without parameter boilerplate.

* **Immutability & Inheritance:** A Context object is immutable. Modifications create a child context via `.with()` (linked via a parent pointer).
* **Implicit Inheritance:** When `spawn` is called, the calling fiber automatically passes its current context down to the child fiber.
* **Type-Safe Reading:** Reading data uses a string key and generics `<T>`. If the stored type does not match `<T>` at runtime, the system returns a controlled Error Union (`error.TypeMismatch`).

```rust
// Excerpt from std/async/context.nx
pub class Context {
    priv parent: ?Context
    priv key: string
    priv value: any

    priv fn __construct(priv parent: ?Context, priv key: string, priv value: any) {}

    [Native("sys_ctx_current")]
    pub static fn current(): Context

    pub fn with(key: string, value: any): Context {
        return new Context(this, key, value)
    }

    pub fn get<T>(key: string): !?T {
        if (this.key == key) {
            if (this.value is T) {
                return this.value as T
            }
            return error.TypeMismatch
        }
        const p = this.parent orelse return null
        return p.get<T>(key)
    }
}

```

**Usage Example:**

```rust
const { Context } = @import("std/async/context")
const { Logger } = @import("std/log")

pub fn middleware_entry() {
    // Create context and bind it to the current fiber
    const ctx = Context.current().with("trace_id", "tx-999")
    Context.bind_to_current_fiber(ctx)

    spawn fn() {
        // The new fiber inherits the context automatically!
        execute_db_query()
    }
}

fn execute_db_query() {
    const ctx = Context.current()
    // Ultra-ergonomic unwrapping using try and orelse in a single line
    const trace = (try ctx.get<string>("trace_id")) orelse "SYSTEM"
    Logger.info("[{trace}] Query executed successfully.")
}

```
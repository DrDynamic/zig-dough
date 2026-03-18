# Constants

## Declaration
Constants are declared with the `const` keyword:
```alpha-script
const foo = "BAR"
```

## Mutation
Mutation of a constant is illegal:
```alpha-script
const foo = "BAR"
foo = "BAZ" // compiler error
```

## Prefere Const
Alpha Script forces you to use const whenever a variable is not mutated.
```alpha-script
var foo = "BAR" // compiler error: Variable is never modified

print(foo)
```

This behavior can be bypassed with the `@enforceVar(description:String)` builtin.
When used, a description, why ist should stay a variable is mendatory.
```alpha-script
@enforceVar("foo will be mutated, when refactoring is complete")
var foo = "BAR" // compiler error: Variable is never modified

print(foo)
```

# Variables
## Declaration
Constants are declared with the `var` keyword.
```alpha-script
var foo = "BAR"
foo = "BAZ"
```

## Late initialization
Variables can be late initialized.

```alpha-script
var foo:String
//...
foo = "BAZ"
```

Reading a not yet initialized variable is illegal.
```alpha-script
var foo

print(foo) // compiler error

foo = "BAZ"
```
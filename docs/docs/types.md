# Types 
Types are mendatory. The compiler needs to know the type of every declaration.

## Variables / Constants
Variables and Constants can get their type by explicitly declaring it.
```alpha-script
var foo:String;
```

Or by infering it from its initializing Value.
```alpha-script
var foo = "BAR"
```

One of those has to be present in the declaration.
```alpha-script
var foo // this is illegal
```

## Not nullable by default
Variables are not implicitly nullable.
```alpha-script
var a:String = ""
b = null // compiler error
```

The null type must explicitly added to the variable type.
```alpha-script
var a:String|Null = ""
b = null // correct
```

The typehint can be simplified with a nullable shothand.
```alpha-script
var a:?String = ""
b = null // correct
```

The nullable shorthand can not be used in type unions
```alpha-script
var a:?String|Int = ""
b = null // compiler error
```


## Type Unions
Declarations are not limited to one type.
Types can be combined in TypeUnions.
```alpha-script
var foo:Int|String = "BAR"
foo = 42
```

The type of the assignment target must match the type of the assignment source.
```alpha-script
const foo:Int|String = "BAR"
const foo_the_second = foo // correct
const foo_too:Int|String = foo // correct
const also_foo:Int|String|Bool = foo // correct

const not_foo:String = foo // compiler error
```

TypeUnions can not contain Errors or ErrorSets. (see ErrorUnions)
```alpha-script
error LookupError {
    NotFound
}

const foo:LookupError|String; // compiler error
```


## Type assureance
If you assure the Interpreter, that a symbol has a specific type, you can use it with that type.
This is possible by using `if`, `switch` or `@assert`.

### if expression
```alpha-script
const foo:Int|String = 42

if(typeOf(foo) == Int)
{
    // in here foo can be read as Int
    const bar:Int = foo // correct
}

// back in this scope, foo can only be read as Int|String
const bar:Int = foo // compiler error
```

### type switch
```alpha-script
const foo:Int|String = 42

switch(typeOf(foo))
{
    case Int => {
        // in here foo can be read as Int
        const bar:Int = foo
    },
    case String => {
        // in here foo can be read as String
        const bar:String = foo
    }
}

// back in this scope, foo can only be read as Int|String
const bar:Int = foo // compiler error
```

### assert
```alpha-script
const foo:Int|String = 42

{
    @assert(typeOf(foo) == Int)
    // in here foo can be read as Int
    const bar:Int = foo
}

// back in this scope, foo can only be read as Int|String
const bar:Int = foo // compiler error
```


### writing to assured type Variables
Writing to variables with an assured type is still possible as before.
But this extends the type again.

```alpha-script
var foo:Int|String|Null = 42

@assert(typeOf(foo) == Int)
// now foo can be read as Int

const bar:Int = foo

foo = "Bar" // correct
// now foo can be read as Int|String

foo = true // compiler error (declaration of foo did not include type Bool)
```

# Named types
Types can be named to avoid writing types like `Null|String|MyAwesomeClass` everywhere.
```alpha-script
type Number = Int|Float

const foo:Number // correct (foo has type Int|Float)

```


# Available Types
- Void
- Null
- Error
- anyerror
- any
- Bool
- Int
- Float
- String

# Typing Variables


```dough
var doughnut:String;

doughnut = 5; // this is an error
```


# Type inference

Types are infered at first assignment, when no type is specified.

```dough
var inferedType = 42; // this is Number

inferedType = false; // this is an compile error
```

The assignment doesn't have to be at assignment:
```dough
var inferedType; // this has no type yet

inferedType = 42; // now it is of type Number
inferedType = false; // this is an compile error
```

# Type Unions

Variables can have more than one type:

```dough
var multiType:String or Number = 42; // this is Number
multiType = "Bake it!"; // this is valid
multiType = false; // this is an compile error
```

# Nullables

Sometimes variables should have a Value or Null (i.e. if not set) 
As we've already seen, `Type Unions` can be used for this:
```dough
var result:String or Null = null;
result = "Yes!";
```

To make this common case easier to type and read, we have the `Nullable` syntax instead of writing a `Type Union`:
```dough
var result:?String = null;
result = "Yes!";
```

Both syntaxes do the same under the hood. 
However the Nullable syntax can only applied to single identifiers (not inline Type Unions):
```dough
var result:?String or Bool = null; // this is an compile error
// instead you need to write it as an Type Union:
var result:String or Bool or Null = null; // this is an compile error
```

# Named Types

Types can also be defined with a name and referenced later:
```dough
type BoolString = Bool or String;

var result:BoolString = false;
result = "empty";
```

Since `named types` have a single identifier, we can (and should) use the Nullable syntax, when the variable should be nullable:
```dough
type BoolString = Bool or String;

var result:?BoolString = false;
result = null;
```
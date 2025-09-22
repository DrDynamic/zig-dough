# Available Types
- Void
- Null
- Error
- Bool
- Number
- String

# Typing Variables

```dough
var doughnut:String = "";

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
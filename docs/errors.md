# Errors
There are no Exceptions in Dough. 
Errorhandling is realized, by passing errors through the code. (like in Zig)

This is more explicit and easier to see when and where errors can occure.

Errors should be resolved as soon as possible.

## ErrorSet

Errors are defined in ErrorSets. 

ErrorSets are very simular to Unions but have their own type.

```dough
error FileOpenError {
    AccessDenied,
    OutOfMemory,
    FileNotFound,
}
```

## Error
An Error is a single Value from a ErrorSet:

```dough
error FileOpenError {
    AccessDenied,
    OutOfMemory,
    FileNotFound,
}

var anError = FileOpenError.OutOfMemory; // anError is of type FileOpenError and has the Error FileOpenError.OutOfMemory as Value.
```

## ErrorUnions
Errors are Typically as return type of a function or method to indicate, that something went wrong.

To have a return value and olso comunicate an error, a ErrorUnion can be used.

ErrorUnions are defined with a `!` followed by a type or type union:

```dough
error DivisionError {
    DivisionByZero,
}

fn divide(a:Number, b:Number) DivisionError!String {
    if(a == 0) return DivisionError.DivisionByZero;

    return a / b;
}
```

When no ErrorSet is specified before the `!` the error type is infered to AnyError.

```dough
error DivisionError {
    DivisionByZero,
}

fn divide(a:Number, b:Number) !String {
    if(a == 0) return DivisionError.DivisionByZero;

    return a / b;
}
```

This is also valid:

```dough
error ConversionError {
    UnknownValue,
}

fn toValue(text:String) ConversionError!String or Bool or Number {
    if(text == "true") {
        return true;
    }else if(text == "false") {
        return false;
    }else if(text == "Hello") {
        return "World";
    }else if(text == "42") {
        return 42;
    }else {
        return ConversionError.UnknownValue;
    }
}
```


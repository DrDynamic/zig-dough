# Errors
Alpha-script doesn't use exceptions for error handling.
Instead, error values are used similar to Zig. 

This is more explicit and easier to see when and where errors can occure.

Errors should be resolved as soon as possible.

## Errors
Errors are identified by Name.

An Error can be created with the error Keyword or by referencing it in a ErrorSet.

```alpha-script
const my_error = error.SomeError // puts the error SomeError in the my_error constant
const also_my_error = MyErrorSet.SomeError // puts the error SomeError on the also_my_error constant
```

Since errors are identified by name, it doesn't matter how it is created. If the name is the same, the error is the same.
```alpha-script
const my_error = error.SomeError // puts the error SomeError in the my_error constant
const also_my_error = MyErrorSet.SomeError // puts the error SomeError on the also_my_error constant

print(error.SomeError == MyErrorSet.SomeError) // prints true
```

## ErrorSet
Errors can be gouped in ErrorSets. 

```alpha-script
error FileOpenError {
    AccessDenied,
    OutOfMemory,
    FileNotFound,
}
```

ErrorSets are special types. 
A Variable can contain an error from a ErrorSet.
```alpha-script
error FileOpenError {
    AccessDenied,
    OutOfMemory,
    FileNotFound,
}

const my_error:FileOpenError = FileOpenError.FileNotFound; // correct
```

ErrorSets can not be combined with types in a TypeUnion but in a special ErrorUnion
```alpha-script
error FileOpenError {
    AccessDenied,
    OutOfMemory,
    FileNotFound,
}

const my_error:FileOpenError|String = FileOpenError.FileNotFound; // compiler error
const my_error:FileOpenError!String = FileOpenError.FileNotFound; // correct
```

An error can not be accessed from an ErrorSet, that doesn't contain the error.
```alpha-script
error FileOpenError {
    AccessDenied,
    OutOfMemory,
    FileNotFound,
}

const my_error:FileOpenError = FileOpenError.MethodNotFound; // compiler error
```

ErrorSets can not be put into a named type.
An error can not be accessed from an ErrorSet, that doesn't contain the error.
```alpha-script
error FileOpenError {
    AccessDenied,
    OutOfMemory,
    FileNotFound,
}

type FileResultOrError = FileOpenError!String  // compiler error
```


## ErrorUnions
Errors are Typically as return type of a function or method to indicate, that something went wrong.

To have a return value and also comunicate an error, a ErrorUnion can be used.

ErrorUnions are defined with a `!` followed by a type or type union:

```alpha-script
error DivisionError {
    DivisionByZero,
}

/// this function can only return errors from the DivisionError ErrorSet or a Float
fn divide(a:Float, b:Float) DivisionError!Float {
    if(a == 0) return DivisionError.DivisionByZero;

    return a / b;
}
```

When no ErrorSet is specified before the `!` the error type is infered to AnyError.

```alpha-script
error DivisionError {
    DivisionByZero,
}

/// this function can return any error or a Float
fn divide(a:Float, b:Float) !Float {
    if(a == 0) return DivisionError.DivisionByZero;

    return a / b;
}
```

This is also valid:

```alpha-script
error ConversionError {
    UnknownValue,
}

fn toValue(text:String) ConversionError!String|Bool|Int|Float {
    if(text == "true") {
        return true;
    }else if(text == "false") {
        return false;
    }else if(text == "Hello") {
        return "World";
    }else if(text == "42") {
        return 42;
    }else {
        return error.UnknownValue;
    }
}
```


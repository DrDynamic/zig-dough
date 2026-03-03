# If Expression
The If expression is heavily inspired by Zig.
It supports three types in its condition:
- bool
- ?T
- !T

## Ternary
If expressions replace ternary expressions in favor of explicitness.

```as
const a = if(true) "Yes" else "No"
try assert(a == "yes")
```

## Boolean condition 
If exprassions behave the clasic way, when you give it a bool condition:

```as
const a = false

if(a) {
    print("a is true")
} else {
    print("a is false")
}
```

## Nunllable condition
If expressions can unwrap nullable values:
```as
var maybe_name: ?string = null;

if(maybe_name) |name| {
    // name has type string (lost the nullable)
    print(name)
}else {
    // we don't have a capture in else. (It would always be null)
    print("no name!")
}
```

## Error union condition
If can unwrap a error union:
```as
const maybe_result: !int = 42

if(maybe_result) |result| {
    // result has type int
} else |err| {
    // err has type error
}
```

## Captures are not optional
Conditions with Nullable or error union type always have their captures.
If they are not needed it can be marked as unused by using `_` as name.

```as
const maybe_result: !int = failableAction()
if(maybe_result) |result| {
    handleResult(result)
} else |_| {
    handleFailure()
}
```
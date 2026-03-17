
var maybe_a:!String = "lorem"

if(maybe_a) |a| {
    print(a) // exprect: lorem
} else |err|{
    print(err)
}

maybe_a = error.NotFound

if(maybe_a) |a| {
    print(a);
} else |err| {
    print(err); // exprect: NotFound
}
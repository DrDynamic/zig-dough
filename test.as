type OptionalString = ?string | float; // expect compile error: Error at '?': nullable shorthand '?' cannot be applied to type unions

var a:OptionalString = "a"; // expect compile error: Error at 'OptionalString': Undefined type

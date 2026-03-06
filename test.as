var a = "";
var b = 0;

var c; // expect if type can not be inferred, it must be set explici
c = a;
c = b; // expect compile error: Error at 'b': can not assign Number to String

print(c);
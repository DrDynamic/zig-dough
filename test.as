
var maybe_a:?String = null

if(maybe_a) |a| {
    print(a);
} else |a| { // expect compile error: Error at 'a': capture is pointless for Nullable condition (it is always null)
    print("a is null");
}

// regression
// var a = "A" + "B" + "C"
//////////////////////////////////////////////////////


// functions are hoisted
//sayHello("World");
//
//fn sayHello(name: string): void {
//    print("Hello " + name);
//}
//////////////////////////////////////////////////////

// non void functions must return a value
//function a() Void {
//    print("i don't need a return statement")
//}
//
//function b() String {
//    if(true) {
//        return "";
//    }
//    print("i do")
//}
//////////////////////////////////////////////////////


// can have multiple functions / calls
//function a() Void {
//    print("A")
//}
//
//function b() Void {
//    print("B")
//}
//
//a()
//b()
//////////////////////////////////////////////////////

// functions can have no parameters
//a()
//a()
//function a () Void {
//    print("Lorem")
//}
//a()
//////////////////////////////////////////////////////

// functions can be assigned to variables
//var a = function () Void {
//    print("Lorem")
//}
//a()
//////////////////////////////////////////////////////


// variables can have function type
//var a:():Void
//a = function()Void{print("A")}
//a()
//
//type listener = (event:String, data:Int): Void;
//type parameter_names_are_optional = (:String, :Int): Void;
//type parameters_are_optional = (): Void;
////type return_type_is_mandatory = (:String);
//type parameters_can_be_error_unions = (:!String):Void;
//type return_types_can_be_error_unions = ():!Void;
//
//////////////////////////////////////////////////////


// functions can be called directly 
//function () Void {
//    print("Lorem")
//}()
//////////////////////////////////////////////////////

// functions can have named parameters
//function printName(name: String) Void {
//    print(name)
//}
// printName(name: "John")
//////////////////////////////////////////////////////

// functions can have default values
//function printDefault(name: String="Doe") {
//    print(name)
//}
// printDefault()
// printDefault("John")
//////////////////////////////////////////////////////


// type Number = Int|Float
// 
// print(add(2, 2.5))
// 
// function sayHello(name:String) Void {
//     print("Hello " ++ name)
// }
// 
// function add(a:Number, b:Number) Number {
//     return a + b
// }
// 
// sayHello("World")

// var greeter = greeterFactory('Max')
// greeter()
// 
// function greeterFactory(name:String) Void {
//     return function() Void {
//         print("Hello " ++ name)
//     }
// }


// correct syntax:
//fn my_fn(param:?String): void {
//    print('Noop' ++ param)
//}
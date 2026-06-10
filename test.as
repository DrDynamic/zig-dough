// regression - arguments don't evaluate to the same register
//fn printThree(a:any, b:any, c:any): void {
//    print(a);
//    print(b);
//    print(c);
//}
//
//printThree("a","b","c")
//////////////////////////////////////////////////////

// regression
//fn noop(): void {}
//noop();
//(true)
//////////////////////////////////////////////////////

// regression - group is parsed as call
// noop();
// fn noop(): void {};
// (true)
//////////////////////////////////////////////////////


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

// can not assign void
// fn noop() void {}
// var a = noop();
//////////////////////////////////////////////////////

// returned value must match return type 
// fn getString() string {
//     return 42;
// }
// var a = noop();
//////////////////////////////////////////////////////

// can not return void when return type is set
// fn getString() string {
//     return;
// }
//////////////////////////////////////////////////////

// return value must be catched
//fn getString() string {
//    return "a";
//}
//getString()
//////////////////////////////////////////////////////

// errors must be catched
//fn getString() !void {
//    return;
//}
//getString()
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

var greeter = greeterFactory("Max")
greeter()
 
 fn greeterFactory(name:string): ():void {
    var suf = "!"
    return fn(): void {
        print("Hello " + name + suf)
    }
 }


// correct syntax:
//fn my_fn(param:?String): void {
//    print('Noop' ++ param)
//}
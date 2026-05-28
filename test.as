// functions are hoisted
//sayHello("World")
//
//function sayHello(name:String) String {
//    print("Hello " + name)
//}
//////////////////////////////////////////////////////

// can have multiple functions
function a() Void {
    print("A")
}

function b() Void {
    print("B")
}

a()
b()
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
//var a:()Void
//a= function(){print("A")}
//a()
//////////////////////////////////////////////////////



//function (name_:String) Void {
//    print("Lorem")
//}()
//
//function (name:String) Void {
//    print("Lorem")
//}()
//
//function () Void {
//    print("Lorem")
//}()

//function printName(name: String) {
//    print(name)
//}
// printName(name: "John")

//function printDefault(name: String="Doe") {
//    print(name)
//}
// printDefault()
// printDefault("John")


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
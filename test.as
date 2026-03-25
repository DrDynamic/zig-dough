type Number = Int|Float

print(add(2, 2.5))

function sayHello(name:String) Void {
    print("Hello " ++ name)
}

function add(a:Number, b:Number) Number {
    return a + b
}

sayHello("World")

// A dangling else binds to the right-most if.
if (false) print("bad"); else print("good");
//if (true) if (false) print("bad"); else print("good"); // expect: good
//if (false) if (true) print("bad"); else print("bad");
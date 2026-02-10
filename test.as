var nan = 0/0;

// NaN is not equal to self.
print(nan == nan); // expect: false
print("-----");
print(nan != nan); // expect: true
print(nan > 5); // expect: false
print(nan < 5); // expect: false
print(".....");
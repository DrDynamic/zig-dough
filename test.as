var nan = 0/0;

// NaN is not equal to self.
print(nan == nan); // expect: false
print("-----");
print(nan != nan); // expect: true
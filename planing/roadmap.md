Each milestone containes a list of features that need to be done, to reach the milestone.

A feature is done, when:
- it is implemented (can be used)
- it is documented 
- it has integration tests, to test the happy path and possible edge cases (that are thought about)  
- it is supported by the language server

# Alpha.1 - Cleanup and Functions (MVP)
- change repository name
- consistant keywords and syntax (some language features are not match the vision e.G. `function` keyword or concatination via `+`)
- datatypes consistant with vision
- X any type
- variables
- constants
- functions - MVP
  -  closures
  - hoisting
  - calls
- panic on int and float overflow / underflow 
- typesystem
- simple garbage collection
- simple math (+-*/)
- concatination (++)
- enforce const (with option to disable)
- error handling
  - bubble errors with try
  - resolve errors with catch
  - enforce error recogision / handling


# Alpha.2 - Iteration
- simple imports (only paz files)
- native iterators
- loops
- arrays
- objects

# Alpha.3 - oop (MVP)
- klasses
- inheritance


# Alpha.4 - Natives
- attributes
- decorators
- Native support

# Alpha.5 - More Datatypes
- byte (alias for u8?)
- make int an alias for i32
- i64, u64, u32
- null unwrapping with orelse
- compound assignment operators (+= -= *= /=) 
- wrapping opterators (+% -% *%)
- saturating operators (+| -| *|)
- bitwise operators (& | ^  ~)
- constants (MAX_INT / MIN_INT / MAX_FLOAT / MIN_FLOAT / ...). Maybe as static field of the datatype class

# later
- traits
- shapes
- std lib
- function upgrades 
  - call by reference
  - default values
  - named arguments
  - elipsis

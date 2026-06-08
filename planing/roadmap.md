Each milestone containes a list of features that need to be done, to reach the milestone.

A feature is done, when:
- it is implemented (can be used)
- it is documented 
- it has integration tests, to test the happy path and possible edge cases (that are thought about)  
- it is supported by the language server

# Alpha.1
- consistant keywords and syntax (some language features are not match the vision e.G. `function` keyword or concatination via `+`)
- datatypes consistant with vision
- any type
- variables
- constants
- functions
  - closures
  - hoisting
  - calls
  - call by reference
  - default values
  - named arguments
  - elipsis

- typesystem
- simple garbage collection
- simple math (+-*/)
- concatination (++)
- any type
- enforce const (with option to disable)


# Alpha.2
- simple imports (only paz files)
- native iterators
- loops
- arrays
- objects

# Alpha.3
- klasses
- inheritance
- attributes
- decorators
- Native support
- more datatypes
    - byte (alias for u8?)
    - i16 / u16
    - int (alias for i32 or i64?)
    - uint (alias for u32 or u64?)


# later
- traits
- shapes
- std lib
- compound assignment operators (+= -= *= /=) 
- bitwise operators (& | ^  ~)

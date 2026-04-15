# next
- vm stack
  - reset stack_top after call_return
  - initialize stack correctly (right amount of registers)
- max_registers
  - check correctness when using temporary register (like in 9+9*9)
  
# backlog
- string concat via ++
- enforce const (when identifier is never written)
- error when identifier is never read
- strict types (alias for an int, that can only be written by the same alias or a literal)
- type casts
- type assertions 
  - union types should be resolved by an assert or if, that asserts its Value type
  - could be implemented with a new property in Symbol (asserted_teype_id)
- @assert builtin
  - assert isType
  - assert hasValue (or isInitialized)
- @enforceVar("description") // tell the compiler to not enforce the variable to be const. A description why is mendatory
- block expressions (labeld breaks)

- defer
- xor
- loops (need iteratable interface)
- shapes (need classes or objects or arrays)
- functions / closures
- arrays
- objects
- classes
  - traits
  - superclasses (inheritance)
  - explicit shapes (interfaces)
  - magic methods (constructor / invoke / get / set / array access?)
- imports
- std library
- lsp
- debugger

- Compiler Settings
  - enforce const

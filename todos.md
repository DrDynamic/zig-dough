# next

# backlog
- use define assignment analysis to check for uninitialized symbols
- enforce const (when identifier is never written)
- error when identifier is never read
- strict types (alias for an int, that can only be written by the same alias or a literal)
- type casts
- type assertions 
  - union types should be resolved by an assert or if, that asserts its Value type
  - could be implemented with a new property in Symbol (asserted_teype_id)

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

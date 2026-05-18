# next
- closures
  - named parameters
  - default parameters
  - hoisting
- refactor OpCode.call 
  - replace ARGS_COUNT with REG_ARGS_START so the function doesn't need to be copied every time
- Register Allocator zur verwalltung von Registern eibführen 
  - allocate- und releaseRegister hierher verschieben
  - liste freigegebener register pflegen (für das register recycling und elegantere max_registers ermittling)
- minipass für discovery und lliveness einführen 
  - in jedem Block über unmittelbare children iterieren und symbole als nicht inittialisiert in die symboltabelle schreiben
  - last_read_node_id einführen und setzen
- architecture documentation
  - instruction size 32 bit (for cache locality)
  - request isolated state (Hybrid model for shared symbols / connections and background tasks for cron like execution)
- function / closure  hoisting


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
  - return Modules as first class citisens
  - Modules are Namespace Isolated
  - Modules work as singletons

- std library
- lsp
- debugger

- Compiler Settings
  - enforce const

- implement register Spilling, when registers are used up

# Optimizations
- liveness analysis (release registers prematurely, when they are read the last time)
- NaN Boxing
- Packed union for Instsructions
- Use ArenaAllocator 
  - should auto grow
  - environment config for min and max size

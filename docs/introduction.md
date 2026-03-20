# About
Alpha Script is a staticly typed language.
It is designed to write robust and explicit software.

The main purposes are Backend Software (FastCGI API) and scripting (execution from alpha script CLI)

## Influences
Alpha Script is heavily influence by:

### Zig
- Explicitnes
- Error handling

### Php
- OOP Features
- PSR

# Best Practices

## Errors
Errors should be resolved as soon as possible but as late as necessary.

## Casing
Types, Classes and Errors in PascalCase

Varables and Constants in snake_case

Functions and Methods in cammelCase

## Explicit over implicit

## Source Files
- Files must be in UTF8 without BOM.
- Files must use Unit LF (linefeed) lineending only.
- Files should end with an empty line (LF after the last not empty line)
- Lines should not be longer than 80 characters; lines longer than that should be split into multiple subsequent lines of no more than 80 characters each.
- Lines shoudl not contain trailing whitespaces
- Blank lines may be added to improve readability and to indicate related blocks of code
- There should not be more than one statement per line


## Modules
Modules should declare symbols (Classes, Functions, Constants, Variables, etc.) OR cause side-effects (not both)
The phrase "side effects" means execution of logic not directly related to declaring classes, functions, constants, etc.



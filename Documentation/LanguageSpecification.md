# SwiftDiagram Language Specification

This document describes the Milestone 2 language subset. Later milestones extend declarations without changing the meaning of valid Milestone 2 files.

## File Structure

```text
source-file          = [ version-directive ], [ diagram-directive ], { declaration | relationship } ;
version-directive    = "swiftDiagram", version-number ;
diagram-directive    = "diagram", string-literal ;
declaration          = declaration-kind, identifier, [ inheritance-clause ], "{", { member }, "}" ;
declaration-kind     = "struct" | "class" | "enum" | "protocol" ;
inheritance-clause   = ":", identifier, { ",", identifier } ;
member               = property | enum-case ;
property             = ( "let" | "var" ), identifier, ":", type-reference, [ accessor ] ;
accessor             = "{", "get", [ "set" ], "}" ;
enum-case            = "case", identifier ;
relationship         = identifier, relationship-kind, identifier,
                       [ "through", identifier ], [ "label", string-literal ] ;
relationship-kind    = "inherits" | "conforms" | "references" ;
type-reference       = [ type-modifier ], postfix-type | function-type ;
type-modifier        = "some" | "any" | "inout" ;
function-type        = [ "@escaping" ], tuple-type, "->", type-reference ;
postfix-type         = primary-type, { "?" } ;
primary-type         = qualified-name, [ generic-arguments ]
                     | "[", type-reference, "]"
                     | "[", type-reference, ":", type-reference, "]"
                     | tuple-type ;
qualified-name       = identifier, { ".", identifier } ;
generic-arguments    = "<", type-reference, { ",", type-reference }, ">" ;
tuple-type           = "(", [ tuple-element, { ",", tuple-element } ], ")" ;
tuple-element        = [ identifier, ":" ], type-reference ;
```

Type references preserve their structure in the semantic model. Supported forms include `User?`, `[User]`, `[String: [User]?]`, `Result<User, Error>`, `(primary: User, Int)`, `@escaping (User) -> Void`, `() -> (Int) -> User`, `any Service`, `some Service`, and `inout User`.

Type parsing is syntactic and does not perform compiler-level or module resolution. Unparseable type text is retained as `.unresolved(String)` and emits `SWD1028`; parsing then resumes at the next member boundary.

## Comments

Line comments and nested block comments are accepted:

```text
// A line comment
/* An outer comment /* nested comment */ */
```

Comments are retained as syntax trivia and discarded during semantic lowering.

## Relationship Resolution

Inheritance clauses are resolved after all declarations have been collected. Local classes and protocols determine whether an entry is `inherits` or `conforms`. Struct conformances are structurally guaranteed. An unresolved first entry on a class defaults to an assumed superclass and produces note `SWD2014`.

Explicit statements such as `Service conforms External` are authoritative. They replace the inheritance-clause classification for the same source and target.

## Unsupported Syntax

Enum associated values, methods, initializers, access control, declaration attributes, actors, extensions, and generic declarations are reserved for later milestones. Unsupported or malformed input produces source-located diagnostics and never intentionally traps.

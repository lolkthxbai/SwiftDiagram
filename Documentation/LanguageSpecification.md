# SwiftDiagram Language Specification

This document describes the Milestone 3 language subset. Later milestones extend declarations without changing the meaning of valid Milestone 3 files.

## File Structure

```text
source-file          = [ version-directive ], [ diagram-directive ], { declaration | relationship } ;
version-directive    = "swiftDiagram", version-number ;
diagram-directive    = "diagram", string-literal ;
declaration          = [ access-level ], declaration-kind, identifier,
                       [ inheritance-clause ], "{", { member }, "}" ;
declaration-kind     = "struct" | "class" | "enum" | "protocol" ;
access-level         = "private" | "fileprivate" | "internal" | "package" | "public" | "open" ;
inheritance-clause   = ":", identifier, { ",", identifier } ;
member               = property | method | initializer | enum-case ;
property             = [ access-level ], ( "let" | "var" ), identifier,
                       ":", type-reference, [ accessor ] ;
accessor             = "{", "get", [ "set" ], "}" ;
method               = [ access-level ], "func", identifier, parameter-clause,
                       { "async" | "throws" | "rethrows" },
                       [ "-", ">", type-reference ] ;
initializer          = [ access-level ], "init", [ "?" | "!" ], parameter-clause,
                       { "async" | "throws" | "rethrows" } ;
parameter-clause     = "(", [ parameter, { ",", parameter } ], ")" ;
parameter            = [ identifier, [ identifier ], ":" ], type-reference ;
enum-case            = "case", enum-case-element, { ",", enum-case-element } ;
enum-case-element    = identifier, [ parameter-clause ] ;
relationship         = identifier, relationship-kind, identifier,
                       [ "through", identifier ], [ "label", string-literal ] ;
relationship-kind    = "inherits" | "conforms" | "references" | "accepts" | "returns" ;
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

## Members And Access

Methods and initializers are signatures only; `.swd` does not accept implementation bodies. Parameters retain external and local names, including `_`, and use structured type references. Enum associated values support labeled, named, unlabeled, multiple, optional, and collection values.

Access levels are preserved on declarations and members. `open` is valid only for class declarations and members of classes; invalid uses emit diagnostics. Static and mutating method modifiers are reserved for Milestone 4, although renderers preserve static semantics already present in the shared model.

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

Static and mutating method modifiers, declaration attributes, actors, extensions, generic declarations, type aliases, and method bodies are reserved for later milestones. Unsupported or malformed input produces source-located diagnostics and never intentionally traps.

# SwiftDiagram Language Specification

This document describes the Milestone 1 language subset. Later milestones extend type references and declarations without changing the meaning of valid Milestone 1 files.

## File Structure

```text
source-file          = [ version-directive ], [ diagram-directive ], { declaration | relationship } ;
version-directive    = "swiftDiagram", version-number ;
diagram-directive    = "diagram", string-literal ;
declaration          = declaration-kind, identifier, [ inheritance-clause ], "{", { member }, "}" ;
declaration-kind     = "struct" | "class" | "enum" | "protocol" ;
inheritance-clause   = ":", identifier, { ",", identifier } ;
member               = property | enum-case ;
property             = ( "let" | "var" ), identifier, ":", identifier, [ accessor ] ;
accessor             = "{", "get", [ "set" ], "}" ;
enum-case            = "case", identifier ;
relationship         = identifier, relationship-kind, identifier,
                       [ "through", identifier ], [ "label", string-literal ] ;
relationship-kind    = "inherits" | "conforms" | "references" ;
```

Type and member names are identifiers. Milestone 1 type references are simple names such as `User` or `UUID`; optionals, collections, qualified names, and generics are rejected with a diagnostic.

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

Enum associated values, methods, initializers, access control, attributes, actors, extensions, generic declarations, and compound type references are reserved for later milestones. Unsupported or malformed input produces source-located diagnostics and never intentionally traps.

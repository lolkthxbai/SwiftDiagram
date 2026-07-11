# SwiftDiagram

SwiftDiagram is a Swift-native text language and command-line tool for architecture diagrams. Authored `.swd` files produce deterministic Mermaid or PlantUML class diagrams that can be reviewed alongside source code. Unlike source-to-UML converters, SwiftDiagram starts from an explicit architecture model; Swift source inspection is a separate, later workflow that will feed the same semantic model.

The current development baseline implements Milestone 3: member signatures and dual Mermaid/PlantUML rendering.

## Installation

SwiftDiagram requires macOS 13 or later and Swift 6.3.

```bash
git clone https://github.com/lolkthxbai/SwiftDiagram.git
cd SwiftDiagram
swift build -c release
```

The executable is available at `.build/release/swiftdiagram`. During development, run it through Swift Package Manager with `swift run swiftdiagram`.

## Basic Use

Create `Architecture.swd`:

```text
protocol Identifiable {
    var id: UUID { get }
}

struct User: Identifiable {
    let id: UUID
}
```

Validate and render it:

```bash
swift run swiftdiagram validate Architecture.swd
swift run swiftdiagram render Architecture.swd --output Architecture.mmd
swift run swiftdiagram render Architecture.swd --format plantuml --output Architecture.puml
```

Without `--output`, `render` writes the selected format to standard output. Mermaid is the default. See [`Examples/BasicTypes.swd`](Examples/BasicTypes.swd) for the core language and [`Examples/Members.swd`](Examples/Members.swd) for member signatures and access control.

## Current Language

The current parser supports access-controlled `struct`, `class`, `enum`, and `protocol` declarations; properties and protocol requirements; methods with parameters, effects, and return types; failable initializers; enum associated values; `inherits`, `conforms`, `references`, `accepts`, and `returns`; and line and nested block comments.

Property types support qualified names, optionals, arrays, dictionaries, generic arguments, tuples, function types including `@escaping`, `some`, `any`, and `inout`. Invalid type text is retained as unresolved syntax and reported with a source-located diagnostic.

Static and mutating method syntax, attributes, extensions, configuration, formatting, JSON interchange, and Swift source inspection belong to later milestones and are not implemented yet. Both renderers already honor static methods present in the semantic model so imported and programmatically constructed diagrams retain that meaning.

## Development

```bash
swift build
swift test
swift build -c release
```


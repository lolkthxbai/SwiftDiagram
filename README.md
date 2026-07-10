# SwiftDiagram

SwiftDiagram is a Swift-native text language and command-line tool for architecture diagrams. Authored `.swd` files produce deterministic Mermaid class diagrams that can be reviewed alongside source code. Unlike source-to-UML converters, SwiftDiagram starts from an explicit architecture model; Swift source inspection is a separate, later workflow that will feed the same semantic model.

The current development baseline implements Milestone 1: the core `.swd`-to-Mermaid vertical slice.

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
```

Without `--output`, `render` writes Mermaid to standard output. See [`Examples/BasicTypes.swd`](Examples/BasicTypes.swd) for declarations, enum cases, inheritance, conformance, references, comments, a title, and a language-version directive.

## Milestone 1 Language

The current parser supports `struct`, `class`, `enum`, and `protocol` declarations; `let` and `var` properties; protocol property requirements; enum cases without associated values; `inherits`, `conforms`, and `references`; line and nested block comments; and simple named type references.

Optionals, collections, generics, methods, access control, extensions, PlantUML, configuration, formatting, JSON interchange, and Swift source inspection belong to later milestones and are not implemented yet.

## Development

```bash
swift build
swift test
swift build -c release
```


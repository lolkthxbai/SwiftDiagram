# SwiftDiagram

SwiftDiagram is a Swift-native text language and command-line tool for architecture diagrams. Authored `.swd` files produce deterministic Mermaid or PlantUML class diagrams that can be reviewed alongside source code. Unlike source-to-UML converters, SwiftDiagram starts from an explicit architecture model; Swift source inspection is a separate, later workflow that will feed the same semantic model.

The current development baseline implements Milestone 5: deterministic multi-file rendering and CLI-driven filtering.

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
swift run swiftdiagram format Architecture.swd --check
swift run swiftdiagram render Architecture.swd --output Architecture.mmd
swift run swiftdiagram render Architecture.swd --format plantuml --output Architecture.puml
swift run swiftdiagram render Architecture.swd --extensions separate
swift run swiftdiagram render Diagrams/ --declaration-access public,open --member-access public
```

Without `--output`, `render` writes the selected format to standard output. Mermaid and merged extensions are the defaults. See [`Examples/BasicTypes.swd`](Examples/BasicTypes.swd) for the core language, [`Examples/Members.swd`](Examples/Members.swd) for member signatures and access control, and [`Examples/Extensions.swd`](Examples/Extensions.swd) for Milestone 4 syntax.

## Current Language

The current parser supports access-controlled `struct`, `class`, `enum`, and `protocol` declarations; extensions; attributed and computed properties; static and mutating methods; failable initializers; enum associated values; every relationship from `inherits` through `extends`; and line and nested block comments.

Property types support qualified names, optionals, arrays, dictionaries, generic arguments, tuples, function types including `@escaping`, `some`, `any`, and `inout`. Invalid type text is retained as unresolved syntax and reported with a source-located diagnostic.

Extensions remain distinct in the semantic model and can be rendered as merged, separate, or hidden without changing that model. `swiftdiagram format` uses syntax tokens and trivia rather than semantic lowering, preserving comments while producing canonical layout. Configuration, JSON interchange, and Swift source inspection belong to later milestones.

## Filtering

`render` accepts any combination of `.swd` files and directories. Directories are searched recursively, matched files are sorted before parsing, and renderer output is stable regardless of argument or filesystem order. Repeatable `--include-file` and `--exclude-file` globs support `*`, `**`, and `?`.

Declaration and member access levels are filtered independently with `--declaration-access` and `--member-access`. Element and relationship-target exclusions accept the same wildcard syntax. Filtering changes only the rendered presentation; the parsed semantic model remains intact.

## Development

```bash
swift build
swift test
swift build -c release
```


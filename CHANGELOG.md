# Changelog

## Unreleased

## 0.4.0 - 2026-07-11

- Added extensions, attributes, static and mutating methods, computed property signatures, and explicit `owns`, `contains`, and `extends` relationships.
- Added merged, separate, and hidden extension rendering for Mermaid and PlantUML without mutating the semantic model.
- Added syntax-layer canonical formatting, comment preservation, `format --check`, in-place formatting, and extension-mode golden fixtures.

## 0.3.1 - 2026-07-11

- Pinned GitHub Actions to macOS 26 so CI and release checks use the required Swift 6.3 toolchain.

## 0.3.0 - 2026-07-11

- Added access-controlled methods, initializers, enum associated values, and `accepts` and `returns` relationships.
- Added deterministic PlantUML output, dual-format member fixtures, Swift stereotypes, and static-member rendering.

## 0.2.0 - 2026-07-10

- Added structured parsing and Mermaid rendering for optionals, collections, generic arguments, tuples, function types, qualified names, existential and opaque types, and `inout`.
- Added source-located unresolved-type recovery and Milestone 2 golden fixtures.

## 0.1.0 - 2026-07-10

- Implemented the Milestone 1 `.swd` syntax, semantic lowering, local relationship resolver, validation, deterministic Mermaid rendering, and `render` and `validate` CLI commands.
- Added source-located diagnostics, Mermaid golden fixtures, a complete example, and end-to-end coverage.
- Initialized the SwiftDiagram package foundation for Milestone 0.

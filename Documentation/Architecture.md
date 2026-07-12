# Architecture

SwiftDiagram uses one directional pipeline:

```text
.swd source
    -> SwiftDiagramSyntaxParser
    -> SwiftDiagramSyntax
       -> SwiftDiagramFormatter
    -> SwiftDiagramParser
    -> SwiftDiagramModel
    -> SwiftDiagramValidation
    -> SwiftDiagramRendering
       -> SwiftDiagramMermaid
       -> SwiftDiagramPlantUML
```

`SwiftDiagramSyntaxParser` owns the handwritten lexer and recursive-descent parser. Its positioned tokens retain comments and whitespace as trivia, and its syntax diagnostics do not depend on the semantic model. Type references are parsed recursively so nested collections, generics, tuples, and function returns retain their structure before lowering.

`SwiftDiagramParser` lowers syntax nodes into `SwiftDiagramModel`, including structured member signatures, extensions, attributes, method modifiers, and every current `TypeReference` case. It builds a local symbol table after collecting all declarations, resolves inheritance and conformance clauses, and lets explicit relationship statements override clause classification. Extension declarations remain separate from type declarations throughout semantic processing.

`SwiftDiagramValidation` checks the resulting semantic model. Mermaid and PlantUML depend only on `SwiftDiagramModel` and the renderer-neutral contract in `SwiftDiagramRendering`; they never consume parser syntax directly. The PlantUML renderer generates source locally and does not invoke Java or contact a server. `SwiftDiagramCore` sorts and merges multiple parsed sources before one combined validation pass, while the CLI handles deterministic file discovery, options, diagnostics, and exit status.

Filtering is presentation-only. File filters select source inputs before parsing; access-level, element, method, extension, and relationship filters are applied by renderers to temporary views of the canonical model. Shared wildcard matching in `SwiftDiagramRendering` supports `*` within a path segment, `**` across segments, and `?` for one character. Neither renderer mutates the supplied `Diagram`.

Formatting is a separate syntax-layer concern. `SwiftDiagramFormatter` depends only on `SwiftDiagramSyntax` and `SwiftDiagramSyntaxParser`, not `SwiftDiagramModel` or semantic lowering. It formats positioned tokens and trivia so nested and trailing comments survive canonicalization. `format --check` compares the canonical bytes with the input bytes.

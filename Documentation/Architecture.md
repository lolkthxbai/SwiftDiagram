# Architecture

SwiftDiagram uses one directional pipeline:

```text
.swd source
    -> SwiftDiagramSyntaxParser
    -> SwiftDiagramSyntax
    -> SwiftDiagramParser
    -> SwiftDiagramModel
    -> SwiftDiagramValidation
    -> SwiftDiagramRendering
    -> SwiftDiagramMermaid
```

`SwiftDiagramSyntaxParser` owns the handwritten lexer and recursive-descent parser. Its positioned tokens retain comments and whitespace as trivia, and its syntax diagnostics do not depend on the semantic model.

`SwiftDiagramParser` lowers syntax nodes into `SwiftDiagramModel`. It builds a local symbol table after collecting all declarations, resolves inheritance and conformance clauses, and lets explicit relationship statements override clause classification.

`SwiftDiagramValidation` checks the resulting semantic model. Renderers depend only on `SwiftDiagramModel` and the renderer-neutral contract in `SwiftDiagramRendering`; they never consume parser syntax directly. `SwiftDiagramCore` coordinates the pipeline, and the CLI handles only file I/O, options, diagnostics, and exit status.

Formatting remains a separate syntax-layer concern. `SwiftDiagramFormatter` depends on `SwiftDiagramSyntax` and `SwiftDiagramSyntaxParser`, not semantic lowering, so future formatting can preserve comments without adding trivia to the semantic model.

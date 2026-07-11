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
       -> SwiftDiagramPlantUML
```

`SwiftDiagramSyntaxParser` owns the handwritten lexer and recursive-descent parser. Its positioned tokens retain comments and whitespace as trivia, and its syntax diagnostics do not depend on the semantic model. Type references are parsed recursively so nested collections, generics, tuples, and function returns retain their structure before lowering.

`SwiftDiagramParser` lowers syntax nodes into `SwiftDiagramModel`, including structured member signatures and every `TypeReference` case used by Milestone 3. It builds a local symbol table after collecting all declarations, resolves inheritance and conformance clauses, and lets explicit relationship statements override clause classification.

`SwiftDiagramValidation` checks the resulting semantic model. Mermaid and PlantUML depend only on `SwiftDiagramModel` and the renderer-neutral contract in `SwiftDiagramRendering`; they never consume parser syntax directly. The PlantUML renderer generates source locally and does not invoke Java or contact a server. `SwiftDiagramCore` coordinates the pipeline, and the CLI handles only file I/O, options, diagnostics, and exit status.

Formatting remains a separate syntax-layer concern. `SwiftDiagramFormatter` depends on `SwiftDiagramSyntax` and `SwiftDiagramSyntaxParser`, not semantic lowering, so future formatting can preserve comments without adding trivia to the semantic model.

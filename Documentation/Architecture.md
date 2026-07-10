# Architecture

Status: skeleton for Milestone 0.

SwiftDiagram separates syntax, semantic model, validation, rendering, configuration, SwiftSyntax inspection, and CLI layers.

The formatter depends on `SwiftDiagramSyntax` and `SwiftDiagramSyntaxParser`, not semantic lowering or `SwiftDiagramModel`.

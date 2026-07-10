import Foundation
import SwiftDiagramModel
import SwiftSyntax

public struct SwiftInspectionOptions: Equatable, Sendable {
    public var includePrivateDeclarations: Bool
    public var includeMethods: Bool
    public var inferRelationships: Bool

    public init(
        includePrivateDeclarations: Bool = false,
        includeMethods: Bool = true,
        inferRelationships: Bool = true
    ) {
        self.includePrivateDeclarations = includePrivateDeclarations
        self.includeMethods = includeMethods
        self.inferRelationships = inferRelationships
    }
}

public struct InspectionResult: Equatable, Sendable {
    public var diagram: Diagram
    public var diagnostics: [Diagnostic]

    public init(diagram: Diagram, diagnostics: [Diagnostic] = []) {
        self.diagram = diagram
        self.diagnostics = diagnostics
    }
}

public protocol SwiftSourceInspecting: Sendable {
    func inspect(
        paths: [URL],
        options: SwiftInspectionOptions
    ) throws -> InspectionResult
}

import SwiftDiagramModel

public protocol DiagramValidating: Sendable {
    func validate(_ diagram: Diagram) -> [Diagnostic]
}

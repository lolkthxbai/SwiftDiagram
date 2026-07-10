import SwiftDiagramModel

public struct ParseResult: Equatable, Sendable {
    public var diagram: Diagram?
    public var diagnostics: [Diagnostic]

    public init(diagram: Diagram?, diagnostics: [Diagnostic] = []) {
        self.diagram = diagram
        self.diagnostics = diagnostics
    }
}

public protocol DiagramParsing: Sendable {
    func parse(source: String, fileName: String?) -> ParseResult
}

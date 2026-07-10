import SwiftDiagramModel

public protocol DiagramRenderer: Sendable {
    var formatName: String { get }

    func render(
        _ diagram: Diagram,
        options: RenderOptions
    ) throws -> String
}

public struct RenderOptions: Equatable, Sendable, Codable {
    public var includeInferredRelationships: Bool
    public var includeMethods: Bool
    public var extensionDisplayMode: ExtensionDisplayMode

    public init(
        includeInferredRelationships: Bool = true,
        includeMethods: Bool = true,
        extensionDisplayMode: ExtensionDisplayMode = .merged
    ) {
        self.includeInferredRelationships = includeInferredRelationships
        self.includeMethods = includeMethods
        self.extensionDisplayMode = extensionDisplayMode
    }
}

public enum ExtensionDisplayMode: String, Equatable, Sendable, Codable {
    case separate
    case merged
    case hidden
}

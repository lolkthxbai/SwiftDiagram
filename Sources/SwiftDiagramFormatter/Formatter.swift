import SwiftDiagramSyntax
import SwiftDiagramSyntaxParser

public struct FormatResult: Equatable, Sendable {
    public var text: String
    public var changed: Bool

    public init(text: String, changed: Bool) {
        self.text = text
        self.changed = changed
    }
}

public protocol DiagramFormatting: Sendable {
    func format(sourceFile: SourceFileSyntax) -> FormatResult
}

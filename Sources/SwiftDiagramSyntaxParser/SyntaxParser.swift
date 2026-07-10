import SwiftDiagramSyntax

public struct SyntaxParseResult: Equatable, Sendable {
    public var sourceFile: SourceFileSyntax

    public init(sourceFile: SourceFileSyntax = SourceFileSyntax()) {
        self.sourceFile = sourceFile
    }
}

public protocol SyntaxParsing: Sendable {
    func parseSyntax(source: String, fileName: String?) -> SyntaxParseResult
}

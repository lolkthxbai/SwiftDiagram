public struct Token: Equatable, Sendable {
    public var kind: TokenKind
    public var text: String
    public var leadingTrivia: [TriviaPiece]
    public var trailingTrivia: [TriviaPiece]

    public init(
        kind: TokenKind,
        text: String,
        leadingTrivia: [TriviaPiece] = [],
        trailingTrivia: [TriviaPiece] = []
    ) {
        self.kind = kind
        self.text = text
        self.leadingTrivia = leadingTrivia
        self.trailingTrivia = trailingTrivia
    }
}

public enum TokenKind: Equatable, Sendable {
    case identifier
    case keyword(String)
    case punctuation(String)
    case stringLiteral
    case numberLiteral
    case endOfFile
    case unknown
}

public enum TriviaPiece: Equatable, Sendable {
    case lineComment(String)
    case blockComment(String)
    case spaces(Int)
    case tabs(Int)
    case newlines(Int)
}

public protocol SyntaxNode: Equatable, Sendable {}

public struct SourceFileSyntax: SyntaxNode {
    public var tokens: [Token]

    public init(tokens: [Token] = []) {
        self.tokens = tokens
    }
}

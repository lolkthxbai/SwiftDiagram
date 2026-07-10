public struct SyntaxPosition: Equatable, Sendable {
    public var line: Int
    public var column: Int
    public var offset: Int

    public init(line: Int, column: Int, offset: Int) {
        self.line = line
        self.column = column
        self.offset = offset
    }

    public static let start = SyntaxPosition(line: 1, column: 1, offset: 0)
}

public struct SyntaxRange: Equatable, Sendable {
    public var start: SyntaxPosition
    public var end: SyntaxPosition

    public init(start: SyntaxPosition, end: SyntaxPosition) {
        self.start = start
        self.end = end
    }

    public static let empty = SyntaxRange(start: .start, end: .start)
}

public enum SyntaxDiagnosticSeverity: String, Equatable, Sendable {
    case error
    case warning
    case note
}

public struct SyntaxDiagnostic: Equatable, Sendable {
    public var severity: SyntaxDiagnosticSeverity
    public var code: String
    public var message: String
    public var fileName: String?
    public var range: SyntaxRange

    public init(
        severity: SyntaxDiagnosticSeverity,
        code: String,
        message: String,
        fileName: String?,
        range: SyntaxRange
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.fileName = fileName
        self.range = range
    }
}

public struct Token: Equatable, Sendable {
    public var kind: TokenKind
    public var text: String
    public var leadingTrivia: [TriviaPiece]
    public var trailingTrivia: [TriviaPiece]
    public var range: SyntaxRange

    public init(
        kind: TokenKind,
        text: String,
        leadingTrivia: [TriviaPiece] = [],
        trailingTrivia: [TriviaPiece] = [],
        range: SyntaxRange = .empty
    ) {
        self.kind = kind
        self.text = text
        self.leadingTrivia = leadingTrivia
        self.trailingTrivia = trailingTrivia
        self.range = range
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

public protocol SyntaxNode: Equatable, Sendable {
    var range: SyntaxRange { get }
}

public struct NamedTypeSyntax: SyntaxNode {
    public var name: String
    public var range: SyntaxRange

    public init(name: String, range: SyntaxRange) {
        self.name = name
        self.range = range
    }
}

public struct VersionDirectiveSyntax: SyntaxNode {
    public var version: String
    public var range: SyntaxRange

    public init(version: String, range: SyntaxRange) {
        self.version = version
        self.range = range
    }
}

public struct DiagramDirectiveSyntax: SyntaxNode {
    public var title: String
    public var range: SyntaxRange

    public init(title: String, range: SyntaxRange) {
        self.title = title
        self.range = range
    }
}

public enum DeclarationKindSyntax: String, Equatable, Sendable {
    case `struct`
    case `class`
    case `enum`
    case `protocol`
}

public struct TypeDeclarationSyntax: SyntaxNode {
    public var kind: DeclarationKindSyntax
    public var name: NamedTypeSyntax
    public var inheritedTypes: [NamedTypeSyntax]
    public var members: [MemberSyntax]
    public var range: SyntaxRange

    public init(
        kind: DeclarationKindSyntax,
        name: NamedTypeSyntax,
        inheritedTypes: [NamedTypeSyntax] = [],
        members: [MemberSyntax] = [],
        range: SyntaxRange
    ) {
        self.kind = kind
        self.name = name
        self.inheritedTypes = inheritedTypes
        self.members = members
        self.range = range
    }
}

public enum PropertyMutabilitySyntax: String, Equatable, Sendable {
    case letProperty = "let"
    case varProperty = "var"
}

public enum PropertyAccessorSyntax: Equatable, Sendable {
    case get
    case getSet
}

public struct PropertyDeclarationSyntax: SyntaxNode {
    public var mutability: PropertyMutabilitySyntax
    public var name: String
    public var type: NamedTypeSyntax
    public var accessor: PropertyAccessorSyntax?
    public var range: SyntaxRange

    public init(
        mutability: PropertyMutabilitySyntax,
        name: String,
        type: NamedTypeSyntax,
        accessor: PropertyAccessorSyntax? = nil,
        range: SyntaxRange
    ) {
        self.mutability = mutability
        self.name = name
        self.type = type
        self.accessor = accessor
        self.range = range
    }
}

public struct EnumCaseDeclarationSyntax: SyntaxNode {
    public var name: String
    public var range: SyntaxRange

    public init(name: String, range: SyntaxRange) {
        self.name = name
        self.range = range
    }
}

public enum MemberSyntax: SyntaxNode {
    case property(PropertyDeclarationSyntax)
    case enumCase(EnumCaseDeclarationSyntax)

    public var range: SyntaxRange {
        switch self {
        case .property(let property):
            property.range
        case .enumCase(let enumCase):
            enumCase.range
        }
    }
}

public enum RelationshipKindSyntax: String, Equatable, Sendable {
    case inherits
    case conforms
    case references
}

public struct RelationshipSyntax: SyntaxNode {
    public var source: NamedTypeSyntax
    public var kind: RelationshipKindSyntax
    public var target: NamedTypeSyntax
    public var throughMember: String?
    public var label: String?
    public var range: SyntaxRange

    public init(
        source: NamedTypeSyntax,
        kind: RelationshipKindSyntax,
        target: NamedTypeSyntax,
        throughMember: String? = nil,
        label: String? = nil,
        range: SyntaxRange
    ) {
        self.source = source
        self.kind = kind
        self.target = target
        self.throughMember = throughMember
        self.label = label
        self.range = range
    }
}

public enum TopLevelSyntax: SyntaxNode {
    case declaration(TypeDeclarationSyntax)
    case relationship(RelationshipSyntax)

    public var range: SyntaxRange {
        switch self {
        case .declaration(let declaration):
            declaration.range
        case .relationship(let relationship):
            relationship.range
        }
    }
}

public struct SourceFileSyntax: SyntaxNode {
    public var tokens: [Token]
    public var versionDirective: VersionDirectiveSyntax?
    public var diagramDirective: DiagramDirectiveSyntax?
    public var statements: [TopLevelSyntax]
    public var range: SyntaxRange

    public init(
        tokens: [Token] = [],
        versionDirective: VersionDirectiveSyntax? = nil,
        diagramDirective: DiagramDirectiveSyntax? = nil,
        statements: [TopLevelSyntax] = [],
        range: SyntaxRange = .empty
    ) {
        self.tokens = tokens
        self.versionDirective = versionDirective
        self.diagramDirective = diagramDirective
        self.statements = statements
        self.range = range
    }
}

import SwiftDiagramSyntax

public struct SyntaxParseResult: Equatable, Sendable {
    public var sourceFile: SourceFileSyntax
    public var diagnostics: [SyntaxDiagnostic]

    public init(
        sourceFile: SourceFileSyntax = SourceFileSyntax(),
        diagnostics: [SyntaxDiagnostic] = []
    ) {
        self.sourceFile = sourceFile
        self.diagnostics = diagnostics
    }
}

public protocol SyntaxParsing: Sendable {
    func parseSyntax(source: String, fileName: String?) -> SyntaxParseResult
}

public struct DiagramSyntaxParser: SyntaxParsing, Sendable {
    public init() {}

    public func parseSyntax(source: String, fileName: String? = nil) -> SyntaxParseResult {
        var lexer = Lexer(source: source, fileName: fileName)
        let lexResult = lexer.lex()
        var parser = Parser(tokens: lexResult.tokens, fileName: fileName)
        let sourceFile = parser.parseSourceFile()
        return SyntaxParseResult(
            sourceFile: sourceFile,
            diagnostics: lexResult.diagnostics + parser.diagnostics
        )
    }
}

private struct Parser {
    let tokens: [Token]
    let fileName: String?
    var index = 0
    var diagnostics: [SyntaxDiagnostic] = []

    mutating func parseSourceFile() -> SourceFileSyntax {
        let start = current.range.start
        var versionDirective: VersionDirectiveSyntax?
        var diagramDirective: DiagramDirectiveSyntax?
        var statements: [TopLevelSyntax] = []

        if isKeyword("swiftDiagram") {
            versionDirective = parseVersionDirective()
        }
        if isKeyword("diagram") {
            diagramDirective = parseDiagramDirective()
        }

        while !isAtEnd {
            let startingIndex = index
            if let kind = declarationKind() {
                if let declaration = parseDeclaration(kind: kind) {
                    statements.append(.declaration(declaration))
                }
            } else if current.kind == .identifier {
                if let relationship = parseRelationship() {
                    statements.append(.relationship(relationship))
                }
            } else {
                diagnose(
                    code: "SWD1010",
                    message: "expected a type declaration or relationship statement",
                    at: current.range
                )
                recoverTopLevel()
            }

            if index == startingIndex {
                advance()
            }
        }

        let end = current.range.end
        return SourceFileSyntax(
            tokens: tokens,
            versionDirective: versionDirective,
            diagramDirective: diagramDirective,
            statements: statements,
            range: SyntaxRange(start: start, end: end)
        )
    }

    private mutating func parseVersionDirective() -> VersionDirectiveSyntax? {
        let start = advance().range.start
        guard current.kind == .numberLiteral else {
            diagnose(code: "SWD1011", message: "expected a language version after 'swiftDiagram'", at: current.range)
            return nil
        }
        let version = advance()
        return VersionDirectiveSyntax(
            version: version.text,
            range: SyntaxRange(start: start, end: version.range.end)
        )
    }

    private mutating func parseDiagramDirective() -> DiagramDirectiveSyntax? {
        let start = advance().range.start
        guard current.kind == .stringLiteral else {
            diagnose(code: "SWD1012", message: "expected a quoted title after 'diagram'", at: current.range)
            return nil
        }
        let title = advance()
        return DiagramDirectiveSyntax(
            title: decodedString(title.text),
            range: SyntaxRange(start: start, end: title.range.end)
        )
    }

    private mutating func parseDeclaration(kind: DeclarationKindSyntax) -> TypeDeclarationSyntax? {
        let start = advance().range.start
        guard let name = parseNamedType(message: "expected a type name") else {
            recoverTopLevel()
            return nil
        }

        var inheritedTypes: [NamedTypeSyntax] = []
        if consumePunctuation(":") != nil {
            if let inheritedType = parseNamedType(message: "expected an inherited type name") {
                inheritedTypes.append(inheritedType)
            }
            while consumePunctuation(",") != nil {
                if let inheritedType = parseNamedType(message: "expected an inherited type name after ','") {
                    inheritedTypes.append(inheritedType)
                }
            }
        }

        guard consumePunctuation("{") != nil else {
            diagnose(code: "SWD1013", message: "expected '{' to begin type declaration", at: current.range)
            recoverTopLevel()
            return nil
        }

        var members: [MemberSyntax] = []
        while !isAtEnd && !isPunctuation("}") {
            let startingIndex = index
            if isKeyword("let") || isKeyword("var") {
                if let property = parseProperty() {
                    members.append(.property(property))
                }
            } else if isKeyword("case") {
                if kind != .enum {
                    diagnose(code: "SWD1014", message: "enum cases are only valid inside enum declarations", at: current.range)
                }
                if let enumCase = parseEnumCase() {
                    members.append(.enumCase(enumCase))
                }
            } else {
                diagnose(code: "SWD1015", message: "expected a property or enum case", at: current.range)
                recoverMember()
            }

            if index == startingIndex {
                advance()
            }
        }

        let end: SyntaxPosition
        if let closeBrace = consumePunctuation("}") {
            end = closeBrace.range.end
        } else {
            diagnose(code: "SWD1016", message: "expected '}' to end type declaration", at: current.range)
            end = current.range.end
        }

        return TypeDeclarationSyntax(
            kind: kind,
            name: name,
            inheritedTypes: inheritedTypes,
            members: members,
            range: SyntaxRange(start: start, end: end)
        )
    }

    private mutating func parseProperty() -> PropertyDeclarationSyntax? {
        let mutabilityToken = advance()
        let mutability: PropertyMutabilitySyntax = mutabilityToken.text == "let" ? .letProperty : .varProperty

        guard current.kind == .identifier else {
            diagnose(code: "SWD1017", message: "expected a property name", at: current.range)
            recoverMember()
            return nil
        }
        let name = advance()

        guard consumePunctuation(":") != nil else {
            diagnose(code: "SWD1018", message: "expected ':' after property name", at: current.range)
            recoverMember()
            return nil
        }
        guard let type = parseNamedType(message: "expected a simple named property type") else {
            recoverMember()
            return nil
        }

        var accessor: PropertyAccessorSyntax?
        var end = type.range.end
        if let openBrace = consumePunctuation("{") {
            guard isKeyword("get") else {
                diagnose(code: "SWD1019", message: "expected 'get' in property accessor", at: current.range)
                recoverAccessor()
                return PropertyDeclarationSyntax(
                    mutability: mutability,
                    name: name.text,
                    type: type,
                    range: SyntaxRange(start: mutabilityToken.range.start, end: openBrace.range.end)
                )
            }
            advance()
            if isKeyword("set") {
                advance()
                accessor = .getSet
            } else {
                accessor = .get
            }
            if let closeBrace = consumePunctuation("}") {
                end = closeBrace.range.end
            } else {
                diagnose(code: "SWD1020", message: "expected '}' after property accessor", at: current.range)
                recoverAccessor()
            }
        }

        if isUnsupportedTypeContinuation(current) {
            diagnose(
                code: "SWD1021",
                message: "Milestone 1 supports simple named type references only",
                at: current.range
            )
            recoverMember()
        }

        return PropertyDeclarationSyntax(
            mutability: mutability,
            name: name.text,
            type: type,
            accessor: accessor,
            range: SyntaxRange(start: mutabilityToken.range.start, end: end)
        )
    }

    private mutating func parseEnumCase() -> EnumCaseDeclarationSyntax? {
        let start = advance().range.start
        guard current.kind == .identifier else {
            diagnose(code: "SWD1022", message: "expected an enum case name", at: current.range)
            recoverMember()
            return nil
        }
        let name = advance()
        if isPunctuation("(") {
            diagnose(
                code: "SWD1023",
                message: "enum associated values are not supported until Milestone 3",
                at: current.range
            )
            recoverMember()
        }
        return EnumCaseDeclarationSyntax(
            name: name.text,
            range: SyntaxRange(start: start, end: name.range.end)
        )
    }

    private mutating func parseRelationship() -> RelationshipSyntax? {
        guard let source = parseNamedType(message: "expected a relationship source") else { return nil }
        guard case .keyword(let relationshipText) = current.kind,
              let kind = RelationshipKindSyntax(rawValue: relationshipText) else {
            diagnose(
                code: "SWD1024",
                message: "expected 'inherits', 'conforms', or 'references' after relationship source",
                at: current.range
            )
            recoverTopLevel()
            return nil
        }
        advance()

        guard let target = parseNamedType(message: "expected a relationship target") else {
            recoverTopLevel()
            return nil
        }

        var throughMember: String?
        var label: String?
        var end = target.range.end
        if isKeyword("through") {
            advance()
            guard current.kind == .identifier else {
                diagnose(code: "SWD1025", message: "expected a member name after 'through'", at: current.range)
                recoverTopLevel()
                return nil
            }
            let through = advance()
            throughMember = through.text
            end = through.range.end
        }
        if isKeyword("label") {
            advance()
            guard current.kind == .stringLiteral else {
                diagnose(code: "SWD1026", message: "expected a quoted relationship label", at: current.range)
                recoverTopLevel()
                return nil
            }
            let labelToken = advance()
            label = decodedString(labelToken.text)
            end = labelToken.range.end
        }

        return RelationshipSyntax(
            source: source,
            kind: kind,
            target: target,
            throughMember: throughMember,
            label: label,
            range: SyntaxRange(start: source.range.start, end: end)
        )
    }

    private mutating func parseNamedType(message: String) -> NamedTypeSyntax? {
        guard current.kind == .identifier else {
            diagnose(code: "SWD1027", message: message, at: current.range)
            return nil
        }
        let token = advance()
        return NamedTypeSyntax(name: token.text, range: token.range)
    }

    private mutating func recoverMember() {
        let line = current.range.start.line
        while !isAtEnd && !isPunctuation("}") {
            if current.range.start.line > line || isKeyword("let") || isKeyword("var") || isKeyword("case") {
                return
            }
            advance()
        }
    }

    private mutating func recoverAccessor() {
        while !isAtEnd && !isPunctuation("}") {
            advance()
        }
        _ = consumePunctuation("}")
    }

    private mutating func recoverTopLevel() {
        let line = current.range.start.line
        while !isAtEnd {
            if current.range.start.line > line && (declarationKind() != nil || current.kind == .identifier) {
                return
            }
            advance()
        }
    }

    private func declarationKind() -> DeclarationKindSyntax? {
        guard case .keyword(let text) = current.kind else { return nil }
        return DeclarationKindSyntax(rawValue: text)
    }

    private func isUnsupportedTypeContinuation(_ token: Token) -> Bool {
        guard case .punctuation(let punctuation) = token.kind else { return false }
        return ["?", "[", "<", ".", "(", "@"].contains(punctuation)
    }

    private func isKeyword(_ keyword: String) -> Bool {
        current.kind == .keyword(keyword)
    }

    private func isPunctuation(_ punctuation: String) -> Bool {
        current.kind == .punctuation(punctuation)
    }

    @discardableResult
    private mutating func consumePunctuation(_ punctuation: String) -> Token? {
        guard isPunctuation(punctuation) else { return nil }
        return advance()
    }

    private var current: Token {
        tokens[min(index, tokens.count - 1)]
    }

    private var isAtEnd: Bool {
        current.kind == .endOfFile
    }

    @discardableResult
    private mutating func advance() -> Token {
        let token = current
        if !isAtEnd {
            index += 1
        }
        return token
    }

    private mutating func diagnose(code: String, message: String, at range: SyntaxRange) {
        diagnostics.append(
            SyntaxDiagnostic(
                severity: .error,
                code: code,
                message: message,
                fileName: fileName,
                range: range
            )
        )
    }
}

private func decodedString(_ text: String) -> String {
    guard text.first == "\"" else { return text }
    let contents = text.dropFirst().dropLast(text.last == "\"" ? 1 : 0)
    var result = ""
    var escaped = false
    for character in contents {
        if escaped {
            switch character {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            default:
                result.append("\\")
                result.append(character)
            }
            escaped = false
        } else if character == "\\" {
            escaped = true
        } else {
            result.append(character)
        }
    }
    if escaped {
        result.append("\\")
    }
    return result
}

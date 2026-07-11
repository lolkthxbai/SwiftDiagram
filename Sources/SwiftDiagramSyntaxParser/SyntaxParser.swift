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
        var parser = Parser(
            tokens: lexResult.tokens,
            sourceCharacters: Array(source),
            fileName: fileName
        )
        let sourceFile = parser.parseSourceFile()
        return SyntaxParseResult(
            sourceFile: sourceFile,
            diagnostics: lexResult.diagnostics + parser.diagnostics
        )
    }
}

private struct Parser {
    let tokens: [Token]
    let sourceCharacters: [Character]
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
            if let prefix = declarationPrefix() {
                if let declaration = parseDeclaration(prefix: prefix) {
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

    private mutating func parseDeclaration(prefix: DeclarationPrefix) -> TypeDeclarationSyntax? {
        let start = current.range.start
        if prefix.accessLevel != nil {
            advance()
        }
        let kind = prefix.kind
        advance()
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
            let memberStart = current.range.start
            let accessLevel = consumeAccessLevel()
            if isKeyword("let") || isKeyword("var") {
                if let property = parseProperty(accessLevel: accessLevel, start: memberStart) {
                    members.append(.property(property))
                }
            } else if isKeyword("func") {
                if let method = parseMethod(accessLevel: accessLevel, start: memberStart) {
                    members.append(.method(method))
                }
            } else if isKeyword("init") {
                if let initializer = parseInitializer(accessLevel: accessLevel, start: memberStart) {
                    members.append(.initializer(initializer))
                }
            } else if isKeyword("case") {
                if accessLevel != nil {
                    diagnose(
                        code: "SWD1029",
                        message: "enum cases cannot have access modifiers",
                        at: SyntaxRange(start: memberStart, end: current.range.start)
                    )
                }
                if kind != .enum {
                    diagnose(code: "SWD1014", message: "enum cases are only valid inside enum declarations", at: current.range)
                }
                members.append(contentsOf: parseEnumCases().map(MemberSyntax.enumCase))
            } else {
                diagnose(code: "SWD1015", message: "expected a property, method, initializer, or enum case", at: current.range)
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
            accessLevel: prefix.accessLevel,
            inheritedTypes: inheritedTypes,
            members: members,
            range: SyntaxRange(start: start, end: end)
        )
    }

    private mutating func parseProperty(
        accessLevel: AccessLevelSyntax?,
        start: SyntaxPosition
    ) -> PropertyDeclarationSyntax? {
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
        let typeStartIndex = index
        var type: TypeReferenceSyntax
        do {
            type = try parseTypeReference()
            if !isTypeTerminator(after: type) {
                throw TypeParseFailure(
                    message: "unexpected token '\(current.text)' in type reference",
                    range: current.range
                )
            }
        } catch let failure as TypeParseFailure {
            diagnose(code: "SWD1028", message: failure.message, at: failure.range)
            index = typeStartIndex
            type = consumeUnresolvedType()
        } catch {
            diagnose(code: "SWD1028", message: "invalid type reference", at: current.range)
            index = typeStartIndex
            type = consumeUnresolvedType()
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
                    accessLevel: accessLevel,
                    range: SyntaxRange(start: start, end: openBrace.range.end)
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

        return PropertyDeclarationSyntax(
            mutability: mutability,
            name: name.text,
            type: type,
            accessLevel: accessLevel,
            accessor: accessor,
            range: SyntaxRange(start: start, end: end)
        )
    }

    private mutating func parseMethod(
        accessLevel: AccessLevelSyntax?,
        start: SyntaxPosition
    ) -> MethodDeclarationSyntax? {
        advance()
        guard current.kind == .identifier else {
            diagnose(code: "SWD1030", message: "expected a method name after 'func'", at: current.range)
            recoverMember()
            return nil
        }
        let name = advance()

        do {
            let clause = try parseParameterClause(allowUnlabeled: false)
            let effects = parseEffectSpecifiers()
            var returnType: TypeReferenceSyntax?
            var end = effects.end ?? clause.end
            if isPunctuation("-") && peekToken.kind == .punctuation(">") {
                advance()
                advance()
                returnType = try parseTypeReference()
                end = returnType?.range.end ?? end
            }
            return MethodDeclarationSyntax(
                name: name.text,
                parameters: clause.parameters,
                returnType: returnType,
                accessLevel: accessLevel,
                isAsync: effects.isAsync,
                throwsKind: effects.throwsKind,
                range: SyntaxRange(start: start, end: end)
            )
        } catch let failure as TypeParseFailure {
            diagnose(code: "SWD1031", message: failure.message, at: failure.range)
            recoverMember()
            return nil
        } catch {
            diagnose(code: "SWD1031", message: "invalid method signature", at: current.range)
            recoverMember()
            return nil
        }
    }

    private mutating func parseInitializer(
        accessLevel: AccessLevelSyntax?,
        start: SyntaxPosition
    ) -> InitializerDeclarationSyntax? {
        advance()
        let failableKind: InitializerFailabilitySyntax
        if consumePunctuation("?") != nil {
            failableKind = .optional
        } else if consumePunctuation("!") != nil {
            failableKind = .implicitlyUnwrapped
        } else {
            failableKind = .none
        }

        do {
            let clause = try parseParameterClause(allowUnlabeled: false)
            let effects = parseEffectSpecifiers()
            return InitializerDeclarationSyntax(
                parameters: clause.parameters,
                accessLevel: accessLevel,
                failableKind: failableKind,
                isAsync: effects.isAsync,
                throwsKind: effects.throwsKind,
                range: SyntaxRange(start: start, end: effects.end ?? clause.end)
            )
        } catch let failure as TypeParseFailure {
            diagnose(code: "SWD1032", message: failure.message, at: failure.range)
            recoverMember()
            return nil
        } catch {
            diagnose(code: "SWD1032", message: "invalid initializer signature", at: current.range)
            recoverMember()
            return nil
        }
    }

    private mutating func parseParameterClause(
        allowUnlabeled: Bool
    ) throws -> (parameters: [ParameterSyntax], end: SyntaxPosition) {
        guard consumePunctuation("(") != nil else {
            throw TypeParseFailure(message: "expected '(' to begin parameter list", range: current.range)
        }
        if let close = consumePunctuation(")") {
            return ([], close.range.end)
        }

        var parameters: [ParameterSyntax] = []
        while true {
            let start = current.range.start
            var externalName: String?
            var localName: String?

            if current.kind == .identifier && peekToken.kind == .punctuation(":") {
                externalName = advance().text
                advance()
            } else if current.kind == .identifier,
                      peekToken.kind == .identifier,
                      token(at: index + 2).kind == .punctuation(":") {
                externalName = advance().text
                localName = advance().text
                advance()
            } else if !allowUnlabeled {
                throw TypeParseFailure(message: "expected a parameter name and ':'", range: current.range)
            }

            let type = try parseTypeReference()
            guard isPunctuation(",") || isPunctuation(")") else {
                throw TypeParseFailure(message: "expected ',' or ')' after parameter", range: current.range)
            }
            parameters.append(
                ParameterSyntax(
                    externalName: externalName,
                    localName: localName,
                    type: type,
                    range: SyntaxRange(start: start, end: type.range.end)
                )
            )
            if consumePunctuation(",") == nil {
                break
            }
        }

        guard let close = consumePunctuation(")") else {
            throw TypeParseFailure(message: "expected ')' to end parameter list", range: current.range)
        }
        return (parameters, close.range.end)
    }

    private mutating func parseEffectSpecifiers() -> (
        isAsync: Bool,
        throwsKind: ThrowsKindSyntax,
        end: SyntaxPosition?
    ) {
        var isAsync = false
        var throwsKind = ThrowsKindSyntax.none
        var end: SyntaxPosition?
        while isKeyword("async") || isKeyword("throws") || isKeyword("rethrows") {
            let effect = advance()
            end = effect.range.end
            if effect.text == "async" {
                if isAsync {
                    diagnose(code: "SWD1033", message: "duplicate 'async' effect", at: effect.range)
                }
                isAsync = true
            } else {
                if throwsKind != .none {
                    diagnose(code: "SWD1033", message: "duplicate throwing effect", at: effect.range)
                }
                throwsKind = effect.text == "throws" ? .throws : .rethrows
            }
        }
        return (isAsync, throwsKind, end)
    }

    private mutating func parseTypeReference() throws -> TypeReferenceSyntax {
        let start = current.range.start
        var isEscaping = false
        if consumePunctuation("@") != nil {
            guard current.text == "escaping" else {
                throw TypeParseFailure(
                    message: "only '@escaping' is supported on type references",
                    range: current.range
                )
            }
            advance()
            isEscaping = true
        }

        var modifiers: [String] = []
        while isKeyword("some") || isKeyword("any") || isKeyword("inout") {
            modifiers.append(advance().text)
        }

        var type = try parsePrimaryType()
        let followsArrow = isPunctuation("-") && peekToken.kind == .punctuation(">")
        if !followsArrow,
           case .tuple(let elements, _) = type,
           elements.count == 1,
           elements[0].label == nil {
            type = elements[0].type
        }
        while let question = consumePunctuation("?") {
            type = .optional(
                type,
                range: SyntaxRange(start: type.range.start, end: question.range.end)
            )
        }

        if isPunctuation("-") && peekToken.kind == .punctuation(">") {
            guard case .tuple(let elements, _) = type else {
                throw TypeParseFailure(
                    message: "function type parameters must be enclosed in parentheses",
                    range: type.range
                )
            }
            advance()
            advance()
            let returnType = try parseTypeReference()
            type = .function(
                parameters: elements.map(\.type),
                returnType: returnType,
                isEscaping: isEscaping,
                range: SyntaxRange(start: start, end: returnType.range.end)
            )
            isEscaping = false
        }

        if isEscaping {
            throw TypeParseFailure(
                message: "'@escaping' requires a function type",
                range: SyntaxRange(start: start, end: type.range.end)
            )
        }

        for modifier in modifiers.reversed() {
            let range = SyntaxRange(start: start, end: type.range.end)
            switch modifier {
            case "some": type = .opaque(type, range: range)
            case "any": type = .existential(type, range: range)
            case "inout": type = .inoutType(type, range: range)
            default: break
            }
        }
        return type
    }

    private mutating func parsePrimaryType() throws -> TypeReferenceSyntax {
        if isPunctuation("[") {
            return try parseCollectionType()
        }
        if isPunctuation("(") {
            return try parseTupleType()
        }
        return try parseNamedTypeReference()
    }

    private mutating func parseNamedTypeReference() throws -> TypeReferenceSyntax {
        guard current.kind == .identifier else {
            throw TypeParseFailure(message: "expected a type reference", range: current.range)
        }
        let start = current.range.start
        var components = [advance().text]
        var end = tokens[index - 1].range.end

        while consumePunctuation(".") != nil {
            guard current.kind == .identifier else {
                throw TypeParseFailure(
                    message: "expected a type name after '.'",
                    range: current.range
                )
            }
            let component = advance()
            components.append(component.text)
            end = component.range.end
        }

        var genericArguments: [TypeReferenceSyntax] = []
        if consumePunctuation("<") != nil {
            guard !isPunctuation(">") else {
                throw TypeParseFailure(
                    message: "generic argument list cannot be empty",
                    range: current.range
                )
            }
            genericArguments.append(try parseTypeReference())
            while consumePunctuation(",") != nil {
                genericArguments.append(try parseTypeReference())
            }
            guard let close = consumePunctuation(">") else {
                throw TypeParseFailure(
                    message: "expected '>' to end generic arguments",
                    range: current.range
                )
            }
            end = close.range.end
        }

        return .named(
            name: components.joined(separator: "."),
            genericArguments: genericArguments,
            range: SyntaxRange(start: start, end: end)
        )
    }

    private mutating func parseCollectionType() throws -> TypeReferenceSyntax {
        let start = advance().range.start
        let first = try parseTypeReference()
        if consumePunctuation(":") != nil {
            let value = try parseTypeReference()
            guard let close = consumePunctuation("]") else {
                throw TypeParseFailure(
                    message: "expected ']' to end dictionary type",
                    range: current.range
                )
            }
            return .dictionary(
                key: first,
                value: value,
                range: SyntaxRange(start: start, end: close.range.end)
            )
        }
        guard let close = consumePunctuation("]") else {
            throw TypeParseFailure(
                message: "expected ']' to end array type",
                range: current.range
            )
        }
        return .array(first, range: SyntaxRange(start: start, end: close.range.end))
    }

    private mutating func parseTupleType() throws -> TypeReferenceSyntax {
        let start = advance().range.start
        var elements: [TupleTypeElementSyntax] = []
        if let close = consumePunctuation(")") {
            return .tuple([], range: SyntaxRange(start: start, end: close.range.end))
        }

        while true {
            let elementStart = current.range.start
            var label: String?
            if current.kind == .identifier && peekToken.kind == .punctuation(":") {
                label = advance().text
                advance()
            }
            let elementType = try parseTypeReference()
            elements.append(
                TupleTypeElementSyntax(
                    label: label,
                    type: elementType,
                    range: SyntaxRange(start: elementStart, end: elementType.range.end)
                )
            )
            if consumePunctuation(",") == nil {
                break
            }
        }

        guard let close = consumePunctuation(")") else {
            throw TypeParseFailure(
                message: "expected ')' to end tuple type",
                range: current.range
            )
        }
        return .tuple(elements, range: SyntaxRange(start: start, end: close.range.end))
    }

    private func isTypeTerminator(after type: TypeReferenceSyntax) -> Bool {
        if isAtEnd || isPunctuation("{") || isPunctuation("}") {
            return true
        }
        return current.range.start.line > type.range.end.line && isMemberStart
    }

    private mutating func consumeUnresolvedType() -> TypeReferenceSyntax {
        let startToken = current
        let startIndex = index
        let startLine = current.range.start.line
        var end = current.range.start

        while !isAtEnd && !isPunctuation("{") && !isPunctuation("}") {
            if index > startIndex,
               current.range.start.line > startLine,
               isMemberStart {
                break
            }
            end = advance().range.end
        }

        let lower = min(startToken.range.start.offset, sourceCharacters.count)
        let upper = min(max(end.offset, lower), sourceCharacters.count)
        let text = String(sourceCharacters[lower..<upper])
        return .unresolved(
            text,
            range: SyntaxRange(start: startToken.range.start, end: end)
        )
    }

    private mutating func parseEnumCases() -> [EnumCaseDeclarationSyntax] {
        advance()
        var cases: [EnumCaseDeclarationSyntax] = []

        while true {
            guard current.kind == .identifier else {
                diagnose(code: "SWD1022", message: "expected an enum case name", at: current.range)
                recoverMember()
                return cases
            }
            let name = advance()
            var associatedValues: [ParameterSyntax] = []
            var end = name.range.end
            if isPunctuation("(") {
                do {
                    let clause = try parseParameterClause(allowUnlabeled: true)
                    associatedValues = clause.parameters
                    end = clause.end
                } catch let failure as TypeParseFailure {
                    diagnose(code: "SWD1023", message: failure.message, at: failure.range)
                    recoverMember()
                    return cases
                } catch {
                    diagnose(code: "SWD1023", message: "invalid associated value list", at: current.range)
                    recoverMember()
                    return cases
                }
            }
            cases.append(
                EnumCaseDeclarationSyntax(
                    name: name.text,
                    associatedValues: associatedValues,
                    range: SyntaxRange(start: name.range.start, end: end)
                )
            )
            if consumePunctuation(",") == nil {
                return cases
            }
        }
    }

    private mutating func parseRelationship() -> RelationshipSyntax? {
        guard let source = parseNamedType(message: "expected a relationship source") else { return nil }
        guard case .keyword(let relationshipText) = current.kind,
              let kind = RelationshipKindSyntax(rawValue: relationshipText) else {
            diagnose(
                code: "SWD1024",
                message: "expected a supported relationship kind after relationship source",
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
        while !isAtEnd && !isPunctuation("}") {
            if isMemberStart {
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
            if current.range.start.line > line && (declarationPrefix() != nil || current.kind == .identifier) {
                return
            }
            advance()
        }
    }

    private func declarationKind() -> DeclarationKindSyntax? {
        guard case .keyword(let text) = current.kind else { return nil }
        return DeclarationKindSyntax(rawValue: text)
    }

    private func declarationPrefix() -> DeclarationPrefix? {
        if let kind = declarationKind() {
            return DeclarationPrefix(accessLevel: nil, kind: kind)
        }
        guard let accessLevel = AccessLevelSyntax(rawValue: current.text),
              case .keyword(let text) = peekToken.kind,
              let kind = DeclarationKindSyntax(rawValue: text) else {
            return nil
        }
        return DeclarationPrefix(accessLevel: accessLevel, kind: kind)
    }

    private mutating func consumeAccessLevel() -> AccessLevelSyntax? {
        guard let accessLevel = AccessLevelSyntax(rawValue: current.text) else { return nil }
        advance()
        return accessLevel
    }

    private var isMemberStart: Bool {
        AccessLevelSyntax(rawValue: current.text) != nil ||
            isKeyword("let") || isKeyword("var") || isKeyword("func") ||
            isKeyword("init") || isKeyword("case")
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

    private func token(at tokenIndex: Int) -> Token {
        tokens[min(tokenIndex, tokens.count - 1)]
    }

    private var peekToken: Token {
        tokens[min(index + 1, tokens.count - 1)]
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

private struct DeclarationPrefix {
    var accessLevel: AccessLevelSyntax?
    var kind: DeclarationKindSyntax
}

private struct TypeParseFailure: Error {
    var message: String
    var range: SyntaxRange
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

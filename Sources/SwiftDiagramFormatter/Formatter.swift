import SwiftDiagramSyntax
import SwiftDiagramSyntaxParser

public struct FormatResult: Equatable, Sendable {
    public var text: String
    public var changed: Bool
    public var diagnostics: [SyntaxDiagnostic]

    public init(
        text: String,
        changed: Bool,
        diagnostics: [SyntaxDiagnostic] = []
    ) {
        self.text = text
        self.changed = changed
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
}

public protocol DiagramFormatting: Sendable {
    func format(sourceFile: SourceFileSyntax) -> FormatResult
}

public struct SwiftDiagramFormatter: DiagramFormatting, Sendable {
    private let parser: any SyntaxParsing

    public init(parser: any SyntaxParsing = DiagramSyntaxParser()) {
        self.parser = parser
    }

    public func format(source: String, fileName: String? = nil) -> FormatResult {
        let parseResult = parser.parseSyntax(source: source, fileName: fileName)
        guard !parseResult.diagnostics.contains(where: { $0.severity == .error }) else {
            return FormatResult(text: source, changed: false, diagnostics: parseResult.diagnostics)
        }
        var result = format(sourceFile: parseResult.sourceFile)
        result.changed = result.text != source
        result.diagnostics = parseResult.diagnostics
        return result
    }

    public func format(sourceFile: SourceFileSyntax) -> FormatResult {
        let original = reconstructedSource(from: sourceFile.tokens)
        var writer = CanonicalWriter(sourceFile: sourceFile)
        let text = writer.write()
        return FormatResult(text: text, changed: text != original)
    }
}

private enum TopLevelKind {
    case declaration
    case relationship
}

private struct CanonicalWriter {
    let sourceFile: SourceFileSyntax
    private var output = ""
    private var indentation = 0
    private var previousToken: Token?
    private var previousTopLevelKind: TopLevelKind?

    private var topLevelKinds: [Int: TopLevelKind] {
        Dictionary(uniqueKeysWithValues: sourceFile.statements.map { statement in
            switch statement {
            case .declaration, .extension:
                return (statement.range.start.offset, .declaration)
            case .relationship:
                return (statement.range.start.offset, .relationship)
            }
        })
    }

    private var memberStarts: Set<Int> {
        var starts = Set(sourceFile.statements.flatMap { statement -> [Int] in
            switch statement {
            case .declaration(let declaration):
                return declaration.members.compactMap(memberStart)
            case .extension(let declaration):
                return declaration.members.compactMap(memberStart)
            case .relationship:
                return []
            }
        })
        starts.formUnion(
            sourceFile.tokens.compactMap { token in
                token.kind == .keyword("case") ? token.range.start.offset : nil
            }
        )
        return starts
    }

    private func memberStart(_ member: MemberSyntax) -> Int? {
        guard case .enumCase = member else { return member.range.start.offset }
        return nil
    }

    private var attributeEnds: Set<Int> {
        Set(sourceFile.statements.flatMap { statement -> [Int] in
            let members: [MemberSyntax]
            switch statement {
            case .declaration(let declaration): members = declaration.members
            case .extension(let declaration): members = declaration.members
            case .relationship: members = []
            }
            return members.flatMap { member -> [Int] in
                switch member {
                case .property(let property): return property.attributes.map { $0.range.end.offset }
                case .method(let method): return method.attributes.map { $0.range.end.offset }
                case .initializer(let initializer): return initializer.attributes.map { $0.range.end.offset }
                case .enumCase: return []
                }
            }
        })
    }

    init(sourceFile: SourceFileSyntax) {
        self.sourceFile = sourceFile
    }

    mutating func write() -> String {
        let topLevels = topLevelKinds
        let members = memberStarts
        let attributes = attributeEnds
        let tokens = sourceFile.tokens.filter { $0.kind != .endOfFile }
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            applyBoundary(for: token, topLevels: topLevels, memberStarts: members)
            emitLeadingTrivia(token.leadingTrivia)

            if token.kind == .punctuation("{"), isAccessorStart(tokens: tokens, index: index) {
                index = emitAccessor(tokens: tokens, index: index)
                previousToken = tokens[index - 1]
                continue
            }
            if token.kind == .punctuation("-"),
               index + 1 < tokens.count,
               tokens[index + 1].kind == .punctuation(">") {
                trimTrailingSpaces()
                if !isAtLineStart { output += " " }
                output += "-> "
                previousToken = tokens[index + 1]
                emitTrailingTrivia(tokens[index + 1].trailingTrivia)
                index += 2
                continue
            }

            emit(token)
            emitTrailingTrivia(token.trailingTrivia)
            if attributes.contains(token.range.end.offset) {
                ensureNewlines(1)
            }
            previousToken = token
            index += 1
        }

        trimTrailingWhitespace()
        output += "\n"
        return output
    }

    private mutating func applyBoundary(
        for token: Token,
        topLevels: [Int: TopLevelKind],
        memberStarts: Set<Int>
    ) {
        if token.range.start.offset == sourceFile.versionDirective?.range.start.offset ||
            token.range.start.offset == sourceFile.diagramDirective?.range.start.offset {
            if !output.isEmpty { ensureNewlines(1) }
            return
        }
        if let kind = topLevels[token.range.start.offset] {
            if !output.isEmpty {
                let newlines = kind == .relationship && previousTopLevelKind == .relationship ? 1 : 2
                ensureNewlines(newlines)
            }
            previousTopLevelKind = kind
        } else if memberStarts.contains(token.range.start.offset) {
            ensureNewlines(1)
        }
    }

    private mutating func emit(_ token: Token) {
        switch token.kind {
        case .punctuation("{"):
            trimTrailingSpaces()
            if !isAtLineStart { output += " " }
            output += "{"
            indentation += 1
            ensureNewlines(1)
        case .punctuation("}"):
            indentation = max(0, indentation - 1)
            ensureNewlines(1)
            emitIndentationIfNeeded()
            output += "}"
        case .punctuation(":"), .punctuation(","):
            trimTrailingSpaces()
            output += token.text + " "
        case .punctuation("."), .punctuation("?"), .punctuation("!"):
            trimTrailingSpaces()
            output += token.text
        case .punctuation(")"), .punctuation("]"), .punctuation(">"):
            trimTrailingSpaces()
            output += token.text
        case .punctuation("("), .punctuation("["), .punctuation("<"), .punctuation("@"):
            emitIndentationIfNeeded()
            output += token.text
        default:
            emitIndentationIfNeeded()
            if needsSpace(before: token) { output += " " }
            output += token.text
        }
    }

    private func needsSpace(before token: Token) -> Bool {
        guard !output.isEmpty, !isAtLineStart, output.last != " ", let previousToken else { return false }
        switch previousToken.kind {
        case .punctuation("@"), .punctuation("("), .punctuation("["),
             .punctuation("<"), .punctuation("."):
            return false
        default:
            break
        }
        switch token.kind {
        case .punctuation:
            return false
        default:
            return true
        }
    }

    private func isAccessorStart(tokens: [Token], index: Int) -> Bool {
        index + 2 < tokens.count && tokens[index + 1].kind == .keyword("get") &&
            (tokens[index + 2].kind == .punctuation("}") ||
                (index + 3 < tokens.count && tokens[index + 2].kind == .keyword("set") &&
                    tokens[index + 3].kind == .punctuation("}")))
    }

    private mutating func emitAccessor(tokens: [Token], index: Int) -> Int {
        trimTrailingSpaces()
        output += " { get"
        var next = index + 2
        if tokens[next].kind == .keyword("set") {
            output += " set"
            next += 1
        }
        output += " }"
        emitTrailingTrivia(tokens[next].trailingTrivia)
        return next + 1
    }

    private mutating func emitLeadingTrivia(_ trivia: [TriviaPiece]) {
        for piece in trivia {
            switch piece {
            case .lineComment(let text):
                if !isAtLineStart { ensureNewlines(1) }
                emitIndentationIfNeeded()
                output += text
                ensureNewlines(1)
            case .blockComment(let text):
                if !isAtLineStart { output += " " }
                emitIndentationIfNeeded()
                output += text + " "
            case .newlines:
                if outputContainsTrailingComment { ensureNewlines(1) }
            case .spaces, .tabs:
                break
            }
        }
    }

    private mutating func emitTrailingTrivia(_ trivia: [TriviaPiece]) {
        for piece in trivia {
            switch piece {
            case .lineComment(let text):
                trimTrailingSpaces()
                if isAtLineStart {
                    emitIndentationIfNeeded()
                } else {
                    output += " "
                }
                output += text
                ensureNewlines(1)
            case .blockComment(let text):
                trimTrailingSpaces()
                if isAtLineStart {
                    emitIndentationIfNeeded()
                } else {
                    output += " "
                }
                output += text + " "
            case .spaces, .tabs, .newlines:
                break
            }
        }
    }

    private var outputContainsTrailingComment: Bool {
        guard let line = output.split(separator: "\n", omittingEmptySubsequences: false).last else { return false }
        return line.contains("//") || line.contains("*/")
    }

    private var isAtLineStart: Bool {
        output.isEmpty || output.last == "\n"
    }

    private mutating func emitIndentationIfNeeded() {
        if isAtLineStart {
            output += String(repeating: " ", count: indentation * 4)
        }
    }

    private mutating func ensureNewlines(_ count: Int) {
        trimTrailingSpaces()
        var existing = 0
        for character in output.reversed() {
            guard character == "\n" else { break }
            existing += 1
        }
        if existing < count {
            output += String(repeating: "\n", count: count - existing)
        }
    }

    private mutating func trimTrailingSpaces() {
        while output.last == " " || output.last == "\t" {
            output.removeLast()
        }
    }

    private mutating func trimTrailingWhitespace() {
        while output.last?.isWhitespace == true {
            output.removeLast()
        }
    }
}

private func reconstructedSource(from tokens: [Token]) -> String {
    tokens.reduce(into: "") { result, token in
        result += text(of: token.leadingTrivia)
        if token.kind != .endOfFile {
            result += token.text
            result += text(of: token.trailingTrivia)
        }
    }
}

private func text(of trivia: [TriviaPiece]) -> String {
    trivia.reduce(into: "") { result, piece in
        switch piece {
        case .lineComment(let text), .blockComment(let text): result += text
        case .spaces(let count): result += String(repeating: " ", count: count)
        case .tabs(let count): result += String(repeating: "\t", count: count)
        case .newlines(let count): result += String(repeating: "\n", count: count)
        }
    }
}

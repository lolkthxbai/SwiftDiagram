import SwiftDiagramSyntax

struct LexResult {
    var tokens: [Token]
    var diagnostics: [SyntaxDiagnostic]
}

struct Lexer {
    private static let keywords: Set<String> = [
        "accepts", "any", "async", "case", "class", "conforms", "diagram", "enum",
        "fileprivate", "func", "get", "inherits", "init", "inout", "internal", "label",
        "let", "open", "package", "private", "protocol", "public", "references",
        "rethrows", "returns", "set", "some", "struct", "swiftDiagram", "through",
        "throws", "var"
    ]

    private let characters: [Character]
    private let fileName: String?
    private var index = 0
    private var position = SyntaxPosition.start
    private var diagnostics: [SyntaxDiagnostic] = []

    init(source: String, fileName: String?) {
        characters = Array(source)
        self.fileName = fileName
    }

    mutating func lex() -> LexResult {
        var tokens: [Token] = []
        var leadingTrivia = scanLeadingTrivia()

        while !isAtEnd {
            var token = scanToken(leadingTrivia: leadingTrivia)
            token.trailingTrivia = scanTrailingTrivia()
            tokens.append(token)
            leadingTrivia = scanLeadingTrivia()
        }

        tokens.append(
            Token(
                kind: .endOfFile,
                text: "",
                leadingTrivia: leadingTrivia,
                range: SyntaxRange(start: position, end: position)
            )
        )
        return LexResult(tokens: tokens, diagnostics: diagnostics)
    }

    private var isAtEnd: Bool {
        index >= characters.count
    }

    private var current: Character? {
        isAtEnd ? nil : characters[index]
    }

    private func peek(_ distance: Int = 1) -> Character? {
        let target = index + distance
        return target < characters.count ? characters[target] : nil
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard !isAtEnd else { return nil }
        let character = characters[index]
        index += 1
        position.offset += 1
        if character == "\n" {
            position.line += 1
            position.column = 1
        } else {
            position.column += 1
        }
        return character
    }

    private mutating func scanToken(leadingTrivia: [TriviaPiece]) -> Token {
        let start = position
        guard let character = current else {
            return Token(kind: .endOfFile, text: "", leadingTrivia: leadingTrivia, range: .empty)
        }

        if isIdentifierHead(character) {
            let text = scanIdentifier()
            let kind: TokenKind = Self.keywords.contains(text) ? .keyword(text) : .identifier
            return Token(
                kind: kind,
                text: text,
                leadingTrivia: leadingTrivia,
                range: SyntaxRange(start: start, end: position)
            )
        }

        if character.isNumber {
            let text = scanNumber()
            return Token(
                kind: .numberLiteral,
                text: text,
                leadingTrivia: leadingTrivia,
                range: SyntaxRange(start: start, end: position)
            )
        }

        if character == "\"" {
            let text = scanString(start: start)
            return Token(
                kind: .stringLiteral,
                text: text,
                leadingTrivia: leadingTrivia,
                range: SyntaxRange(start: start, end: position)
            )
        }

        if "{}:,().[]?<>-@!".contains(character) {
            advance()
            return Token(
                kind: .punctuation(String(character)),
                text: String(character),
                leadingTrivia: leadingTrivia,
                range: SyntaxRange(start: start, end: position)
            )
        }

        advance()
        let range = SyntaxRange(start: start, end: position)
        diagnostics.append(
            SyntaxDiagnostic(
                severity: .error,
                code: "SWD1002",
                message: "unexpected character '\(character)'",
                fileName: fileName,
                range: range
            )
        )
        return Token(
            kind: .unknown,
            text: String(character),
            leadingTrivia: leadingTrivia,
            range: range
        )
    }

    private mutating func scanIdentifier() -> String {
        var text = ""
        while let character = current, isIdentifierContinue(character) {
            text.append(advance()!)
        }
        return text
    }

    private mutating func scanNumber() -> String {
        var text = ""
        while let character = current, character.isNumber {
            text.append(advance()!)
        }
        if current == ".", let next = peek(), next.isNumber {
            text.append(advance()!)
            while let character = current, character.isNumber {
                text.append(advance()!)
            }
        }
        return text
    }

    private mutating func scanString(start: SyntaxPosition) -> String {
        var text = ""
        text.append(advance()!)
        var escaped = false

        while let character = current {
            if character == "\n" && !escaped {
                break
            }
            text.append(advance()!)
            if character == "\"" && !escaped {
                return text
            }
            if character == "\\" && !escaped {
                escaped = true
            } else {
                escaped = false
            }
        }

        diagnostics.append(
            SyntaxDiagnostic(
                severity: .error,
                code: "SWD1001",
                message: "unterminated string literal",
                fileName: fileName,
                range: SyntaxRange(start: start, end: position)
            )
        )
        return text
    }

    private mutating func scanLeadingTrivia() -> [TriviaPiece] {
        var trivia: [TriviaPiece] = []
        while !isAtEnd {
            if current == " " {
                trivia.append(.spaces(scanRepeated(" ")))
            } else if current == "\t" {
                trivia.append(.tabs(scanRepeated("\t")))
            } else if current == "\n" {
                trivia.append(.newlines(scanRepeated("\n")))
            } else if current == "\r" {
                advance()
            } else if current == "/", peek() == "/" {
                trivia.append(.lineComment(scanLineComment()))
            } else if current == "/", peek() == "*" {
                trivia.append(.blockComment(scanBlockComment()))
            } else {
                break
            }
        }
        return trivia
    }

    private mutating func scanTrailingTrivia() -> [TriviaPiece] {
        var trivia: [TriviaPiece] = []
        while !isAtEnd {
            if current == " " {
                trivia.append(.spaces(scanRepeated(" ")))
            } else if current == "\t" {
                trivia.append(.tabs(scanRepeated("\t")))
            } else if current == "/", peek() == "/" {
                trivia.append(.lineComment(scanLineComment()))
                break
            } else if current == "/", peek() == "*" {
                trivia.append(.blockComment(scanBlockComment()))
            } else {
                break
            }
        }
        return trivia
    }

    private mutating func scanRepeated(_ character: Character) -> Int {
        var count = 0
        while current == character {
            advance()
            count += 1
        }
        return count
    }

    private mutating func scanLineComment() -> String {
        var text = ""
        while let character = current, character != "\n" {
            text.append(advance()!)
        }
        return text
    }

    private mutating func scanBlockComment() -> String {
        let start = position
        var text = ""
        var depth = 0

        while !isAtEnd {
            if current == "/", peek() == "*" {
                depth += 1
                text.append(advance()!)
                text.append(advance()!)
            } else if current == "*", peek() == "/" {
                depth -= 1
                text.append(advance()!)
                text.append(advance()!)
                if depth == 0 {
                    return text
                }
            } else {
                text.append(advance()!)
            }
        }

        diagnostics.append(
            SyntaxDiagnostic(
                severity: .error,
                code: "SWD1003",
                message: "unterminated block comment",
                fileName: fileName,
                range: SyntaxRange(start: start, end: position)
            )
        )
        return text
    }

    private func isIdentifierHead(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private func isIdentifierContinue(_ character: Character) -> Bool {
        isIdentifierHead(character) || character.isNumber
    }
}

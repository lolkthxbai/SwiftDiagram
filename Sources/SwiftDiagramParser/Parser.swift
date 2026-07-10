import SwiftDiagramModel
import SwiftDiagramSyntax
import SwiftDiagramSyntaxParser

public struct ParseResult: Equatable, Sendable {
    public var diagram: Diagram?
    public var diagnostics: [Diagnostic]

    public init(diagram: Diagram?, diagnostics: [Diagnostic] = []) {
        self.diagram = diagram
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
}

public protocol DiagramParsing: Sendable {
    func parse(source: String, fileName: String?) -> ParseResult
}

public struct SwiftDiagramParser: DiagramParsing, Sendable {
    private let syntaxParser: any SyntaxParsing

    public init(syntaxParser: any SyntaxParsing = DiagramSyntaxParser()) {
        self.syntaxParser = syntaxParser
    }

    public func parse(source: String, fileName: String? = nil) -> ParseResult {
        let syntaxResult = syntaxParser.parseSyntax(source: source, fileName: fileName)
        var diagnostics = syntaxResult.diagnostics.map(Diagnostic.init)
        let sourceFile = syntaxResult.sourceFile

        let metadata = lowerMetadata(sourceFile, fileName: fileName, diagnostics: &diagnostics)
        let declarationSyntax = sourceFile.statements.compactMap { statement -> TypeDeclarationSyntax? in
            guard case .declaration(let declaration) = statement else { return nil }
            return declaration
        }
        var declarations = declarationSyntax.map(lowerDeclaration)
        let symbols = makeSymbolTable(declarations)
        var clauseRelationships: [Relationship] = []
        let explicitOverridePairs = Set(
            sourceFile.statements.compactMap { statement -> String? in
                guard case .relationship(let relationship) = statement,
                      relationship.kind == .inherits || relationship.kind == .conforms else {
                    return nil
                }
                return relationshipPair(
                    source: QualifiedName(relationship.source.name),
                    target: QualifiedName(relationship.target.name)
                )
            }
        )

        for (declarationIndex, syntax) in declarationSyntax.enumerated() {
            for (position, inheritedType) in syntax.inheritedTypes.enumerated() {
                let pair = relationshipPair(
                    source: declarations[declarationIndex].name,
                    target: QualifiedName(inheritedType.name)
                )
                if explicitOverridePairs.contains(pair) {
                    continue
                }
                let resolution = resolve(
                    sourceKind: declarations[declarationIndex].kind,
                    sourceName: declarations[declarationIndex].name,
                    target: inheritedType,
                    position: position,
                    symbols: symbols,
                    fileName: fileName
                )
                diagnostics.append(contentsOf: resolution.diagnostics)
                guard let relationship = resolution.relationship else { continue }
                clauseRelationships.append(relationship)
                apply(relationship, to: &declarations[declarationIndex])
            }
        }

        var explicitRelationships: [Relationship] = []
        for statement in sourceFile.statements {
            guard case .relationship(let syntax) = statement else { continue }
            let relationship = lowerRelationship(syntax)
            if relationship.kind == .inherits || relationship.kind == .conforms {
                clauseRelationships.removeAll {
                    $0.source == relationship.source &&
                    $0.target == relationship.target &&
                    ($0.kind == .inherits || $0.kind == .conforms)
                }
                if let declarationIndex = declarations.firstIndex(where: { $0.name == relationship.source }) {
                    removeRelationshipTarget(relationship.target, from: &declarations[declarationIndex])
                    apply(relationship, to: &declarations[declarationIndex])
                }
            }
            explicitRelationships.append(relationship)
        }

        return ParseResult(
            diagram: Diagram(
                metadata: metadata,
                declarations: declarations,
                relationships: clauseRelationships + explicitRelationships
            ),
            diagnostics: diagnostics
        )
    }
}

private struct ClauseResolution {
    var relationship: Relationship?
    var diagnostics: [Diagnostic]
}

private func lowerMetadata(
    _ sourceFile: SourceFileSyntax,
    fileName: String?,
    diagnostics: inout [Diagnostic]
) -> DiagramMetadata {
    var version = SemanticVersion.v1_0
    if let directive = sourceFile.versionDirective {
        let components = directive.version.split(separator: ".").compactMap { Int($0) }
        if components.count == 2 || components.count == 3 {
            version = SemanticVersion(
                major: components[0],
                minor: components[1],
                patch: components.count == 3 ? components[2] : 0
            )
        } else {
            diagnostics.append(
                Diagnostic(
                    severity: .error,
                    code: "SWD5001",
                    message: "invalid language version '\(directive.version)'",
                    fileName: fileName,
                    range: SourceRange(directive.range)
                )
            )
        }
    }
    return DiagramMetadata(
        languageVersion: version,
        title: sourceFile.diagramDirective?.title
    )
}

private func lowerDeclaration(_ syntax: TypeDeclarationSyntax) -> TypeDeclaration {
    TypeDeclaration(
        kind: TypeKind(syntax.kind),
        name: QualifiedName(syntax.name.name),
        members: syntax.members.map(lowerMember),
        sourceLocation: SourceRange(syntax.range)
    )
}

private func lowerMember(_ syntax: MemberSyntax) -> Member {
    switch syntax {
    case .property(let property):
        return .property(
            PropertyDeclaration(
                name: property.name,
                type: .named(QualifiedName(property.type.name), genericArguments: []),
                mutability: property.mutability == .letProperty ? .constant : .variable,
                accessor: property.accessor.map(PropertyAccessor.init),
                sourceLocation: SourceRange(property.range)
            )
        )
    case .enumCase(let enumCase):
        return .enumCase(
            EnumCaseDeclaration(
                name: enumCase.name,
                sourceLocation: SourceRange(enumCase.range)
            )
        )
    }
}

private func lowerRelationship(_ syntax: RelationshipSyntax) -> Relationship {
    Relationship(
        source: QualifiedName(syntax.source.name),
        target: QualifiedName(syntax.target.name),
        kind: RelationshipKind(syntax.kind),
        label: syntax.label,
        throughMember: syntax.throughMember,
        origin: .explicit,
        classification: .resolved,
        sourceLocation: SourceRange(syntax.range)
    )
}

private func makeSymbolTable(_ declarations: [TypeDeclaration]) -> [QualifiedName: TypeKind] {
    var symbols: [QualifiedName: TypeKind] = [:]
    for declaration in declarations where symbols[declaration.name] == nil {
        symbols[declaration.name] = declaration.kind
    }
    return symbols
}

private func resolve(
    sourceKind: TypeKind,
    sourceName: QualifiedName,
    target: NamedTypeSyntax,
    position: Int,
    symbols: [QualifiedName: TypeKind],
    fileName: String?
) -> ClauseResolution {
    let targetName = QualifiedName(target.name)
    let targetKind = symbols[targetName]
    let range = SourceRange(target.range)

    func relationship(
        _ kind: RelationshipKind,
        classification: RelationshipClassification = .resolved
    ) -> Relationship {
        Relationship(
            source: sourceName,
            target: targetName,
            kind: kind,
            origin: .explicit,
            classification: classification,
            sourceLocation: range
        )
    }

    func diagnostic(
        _ severity: DiagnosticSeverity,
        _ code: DiagnosticCode,
        _ message: String
    ) -> Diagnostic {
        Diagnostic(
            severity: severity,
            code: code,
            message: message,
            fileName: fileName,
            range: range
        )
    }

    if [.struct, .enum, .actor].contains(sourceKind), targetKind == .class {
        return ClauseResolution(
            relationship: nil,
            diagnostics: [
                diagnostic(
                    .error,
                    "SWD2010",
                    "\(sourceKind.rawValue) '\(sourceName)' cannot inherit class '\(targetName)'"
                )
            ]
        )
    }

    if sourceKind == .enum && position == 0 && targetKind != .protocol {
        return ClauseResolution(
            relationship: nil,
            diagnostics: [
                diagnostic(
                    .note,
                    "SWD2011",
                    "enum raw-value type '\(targetName)' is outside the Milestone 1 language subset"
                )
            ]
        )
    }

    if sourceKind == .struct || sourceKind == .enum || sourceKind == .actor {
        return ClauseResolution(relationship: relationship(.conforms), diagnostics: [])
    }

    if sourceKind == .protocol {
        if targetKind == .class {
            return ClauseResolution(
                relationship: nil,
                diagnostics: [
                    diagnostic(
                        .note,
                        "SWD2012",
                        "class-bound protocol constraints are outside the Milestone 1 language subset"
                    )
                ]
            )
        }
        return ClauseResolution(relationship: relationship(.conforms), diagnostics: [])
    }

    if sourceKind == .class && position >= 1 {
        if targetKind == .class {
            return ClauseResolution(
                relationship: nil,
                diagnostics: [
                    diagnostic(
                        .error,
                        "SWD2013",
                        "superclass '\(targetName)' must be the first inheritance entry"
                    )
                ]
            )
        }
        return ClauseResolution(relationship: relationship(.conforms), diagnostics: [])
    }

    if sourceKind == .class && position == 0 {
        if targetKind == .protocol {
            return ClauseResolution(relationship: relationship(.conforms), diagnostics: [])
        }
        if targetKind == .class {
            return ClauseResolution(relationship: relationship(.inherits), diagnostics: [])
        }
        if targetKind == nil {
            return ClauseResolution(
                relationship: relationship(.inherits, classification: .assumed),
                diagnostics: [
                    diagnostic(
                        .note,
                        "SWD2014",
                        "unresolved supertype '\(targetName)' assumed to be a superclass; add an explicit relationship to override"
                    )
                ]
            )
        }
        return ClauseResolution(relationship: relationship(.conforms), diagnostics: [])
    }

    return ClauseResolution(relationship: nil, diagnostics: [])
}

private func apply(_ relationship: Relationship, to declaration: inout TypeDeclaration) {
    let type = TypeReference.named(relationship.target, genericArguments: [])
    switch relationship.kind {
    case .inherits:
        if !declaration.inheritedTypes.contains(type) {
            declaration.inheritedTypes.append(type)
        }
    case .conforms:
        if !declaration.conformances.contains(type) {
            declaration.conformances.append(type)
        }
    default:
        break
    }
}

private func removeRelationshipTarget(_ target: QualifiedName, from declaration: inout TypeDeclaration) {
    let type = TypeReference.named(target, genericArguments: [])
    declaration.inheritedTypes.removeAll { $0 == type }
    declaration.conformances.removeAll { $0 == type }
}

private func relationshipPair(source: QualifiedName, target: QualifiedName) -> String {
    "\(source.description)->\(target.description)"
}

private extension TypeKind {
    init(_ syntax: DeclarationKindSyntax) {
        switch syntax {
        case .struct: self = .struct
        case .class: self = .class
        case .enum: self = .enum
        case .protocol: self = .protocol
        }
    }
}

private extension PropertyAccessor {
    init(_ syntax: PropertyAccessorSyntax) {
        switch syntax {
        case .get: self = .get
        case .getSet: self = .getSet
        }
    }
}

private extension RelationshipKind {
    init(_ syntax: RelationshipKindSyntax) {
        switch syntax {
        case .inherits: self = .inherits
        case .conforms: self = .conforms
        case .references: self = .references
        }
    }
}

private extension SourceRange {
    init(_ syntax: SyntaxRange) {
        self.init(
            start: SourcePosition(syntax.start),
            end: SourcePosition(syntax.end)
        )
    }
}

private extension SourcePosition {
    init(_ syntax: SyntaxPosition) {
        self.init(line: syntax.line, column: syntax.column, offset: syntax.offset)
    }
}

private extension Diagnostic {
    init(_ syntax: SyntaxDiagnostic) {
        self.init(
            severity: DiagnosticSeverity(syntax.severity),
            code: DiagnosticCode(rawValue: syntax.code),
            message: syntax.message,
            fileName: syntax.fileName,
            range: SourceRange(syntax.range)
        )
    }
}

private extension DiagnosticSeverity {
    init(_ syntax: SyntaxDiagnosticSeverity) {
        switch syntax {
        case .error: self = .error
        case .warning: self = .warning
        case .note: self = .note
        }
    }
}

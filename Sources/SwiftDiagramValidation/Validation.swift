import SwiftDiagramModel

public protocol DiagramValidating: Sendable {
    func validate(_ diagram: Diagram) -> [Diagnostic]
}

public struct SwiftDiagramValidator: DiagramValidating, Sendable {
    public init() {}

    public func validate(_ diagram: Diagram) -> [Diagnostic] {
        validate(diagram, fileName: nil)
    }

    public func validate(_ diagram: Diagram, fileName: String?) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let declarationsByName = Dictionary(grouping: diagram.declarations, by: \TypeDeclaration.name)
        let knownKinds = declarationsByName.compactMapValues(\.first?.kind)

        validateDeclarations(
            diagram.declarations,
            fileName: fileName,
            diagnostics: &diagnostics
        )
        validateRelationships(
            diagram.relationships,
            declarationsByName: declarationsByName,
            knownKinds: knownKinds,
            fileName: fileName,
            diagnostics: &diagnostics
        )

        return diagnostics.sorted(by: diagnosticOrder)
    }
}

private func validateDeclarations(
    _ declarations: [TypeDeclaration],
    fileName: String?,
    diagnostics: inout [Diagnostic]
) {
    var seenDeclarations: Set<QualifiedName> = []
    for declaration in declarations {
        if !seenDeclarations.insert(declaration.name).inserted {
            diagnostics.append(
                makeDiagnostic(
                    .error,
                    "SWD2001",
                    "duplicate type declaration '\(declaration.name)'",
                    fileName,
                    declaration.sourceLocation
                )
            )
        }

        if declaration.accessLevel == .open && declaration.kind != .class {
            diagnostics.append(
                makeDiagnostic(
                    .error,
                    "SWD2016",
                    "open access is only valid on class declarations",
                    fileName,
                    declaration.sourceLocation
                )
            )
        }

        var seenMembers: Set<String> = []
        for member in declaration.members {
            if memberAccessLevel(member) == .open && declaration.kind != .class {
                diagnostics.append(
                    makeDiagnostic(
                        .error,
                        "SWD2017",
                        "open members are only valid in class declarations",
                        fileName,
                        memberSourceLocation(member)
                    )
                )
            }
            guard let identity = memberIdentity(member) else { continue }
            if !seenMembers.insert(identity).inserted {
                diagnostics.append(
                    makeDiagnostic(
                        .error,
                        "SWD2002",
                        "duplicate member '\(memberDisplayName(member))' in '\(declaration.name)'",
                        fileName,
                        memberSourceLocation(member)
                    )
                )
            }
        }
    }
}

private func validateRelationships(
    _ relationships: [Relationship],
    declarationsByName: [QualifiedName: [TypeDeclaration]],
    knownKinds: [QualifiedName: TypeKind],
    fileName: String?,
    diagnostics: inout [Diagnostic]
) {
    var seenRelationships: Set<String> = []
    var relationshipKindsByPair: [String: RelationshipKind] = [:]

    for relationship in relationships {
        guard let sourceDeclaration = declarationsByName[relationship.source]?.first else {
            diagnostics.append(
                makeDiagnostic(
                    .error,
                    "SWD2003",
                    "unknown relationship source '\(relationship.source)'",
                    fileName,
                    relationship.sourceLocation
                )
            )
            continue
        }

        if (relationship.kind == .references || relationship.kind == .accepts || relationship.kind == .returns) &&
            declarationsByName[relationship.target] == nil {
            diagnostics.append(
                makeDiagnostic(
                    .error,
                    "SWD2004",
                    "unknown relationship target '\(relationship.target)'",
                    fileName,
                    relationship.sourceLocation
                )
            )
        }

        validateRelationshipDirection(
            relationship,
            sourceKind: sourceDeclaration.kind,
            targetKind: knownKinds[relationship.target],
            fileName: fileName,
            diagnostics: &diagnostics
        )

        if let throughMember = relationship.throughMember {
            guard let member = sourceDeclaration.members.first(where: { memberDisplayName($0) == throughMember }) else {
                diagnostics.append(
                    makeDiagnostic(
                        .error,
                        "SWD2005",
                        "relationship member '\(throughMember)' does not exist on '\(relationship.source)'",
                        fileName,
                        relationship.sourceLocation
                    )
                )
                continue
            }
            if memberReferencedType(member) != relationship.target {
                diagnostics.append(
                    makeDiagnostic(
                        .error,
                        "SWD2006",
                        "relationship member '\(throughMember)' does not reference '\(relationship.target)'",
                        fileName,
                        relationship.sourceLocation
                    )
                )
            }
        }

        let identity = relationshipIdentity(relationship)
        if !seenRelationships.insert(identity).inserted {
            diagnostics.append(
                makeDiagnostic(
                    .error,
                    "SWD2007",
                    "duplicate explicit relationship from '\(relationship.source)' to '\(relationship.target)'",
                    fileName,
                    relationship.sourceLocation
                )
            )
        }

        if relationship.kind == .inherits || relationship.kind == .conforms {
            let pair = "\(relationship.source)->\(relationship.target)"
            if let existingKind = relationshipKindsByPair[pair], existingKind != relationship.kind {
                diagnostics.append(
                    makeDiagnostic(
                        .error,
                        "SWD2008",
                        "conflicting explicit relationships from '\(relationship.source)' to '\(relationship.target)'",
                        fileName,
                        relationship.sourceLocation
                    )
                )
            } else {
                relationshipKindsByPair[pair] = relationship.kind
            }
        }
    }
}

private func validateRelationshipDirection(
    _ relationship: Relationship,
    sourceKind: TypeKind,
    targetKind: TypeKind?,
    fileName: String?,
    diagnostics: inout [Diagnostic]
) {
    if relationship.kind == .inherits && sourceKind != .class {
        diagnostics.append(
            makeDiagnostic(
                .error,
                "SWD2010",
                "\(sourceKind.rawValue) '\(relationship.source)' cannot inherit a class",
                fileName,
                relationship.sourceLocation
            )
        )
    }

    if relationship.kind == .conforms,
       let targetKind,
       targetKind != .protocol {
        diagnostics.append(
            makeDiagnostic(
                .error,
                "SWD2015",
                "conformance target '\(relationship.target)' is not a protocol",
                fileName,
                relationship.sourceLocation
            )
        )
    }
}

private func memberIdentity(_ member: Member) -> String? {
    switch member {
    case .property(let property):
        return "property:\(property.name)"
    case .enumCase(let enumCase):
        return "case:\(enumCase.name)"
    case .method(let method):
        return "method:\(method.name):\(parameterIdentity(method.parameters))"
    case .initializer(let initializer):
        return "init:\(parameterIdentity(initializer.parameters))"
    case .typeAlias(let typeAlias):
        return "typealias:\(typeAlias.name)"
    }
}

private func memberAccessLevel(_ member: Member) -> AccessLevel? {
    switch member {
    case .property(let property): return property.accessLevel
    case .method(let method): return method.accessLevel
    case .initializer(let initializer): return initializer.accessLevel
    case .typeAlias(let typeAlias): return typeAlias.accessLevel
    case .enumCase: return nil
    }
}

private func parameterIdentity(_ parameters: [Parameter]) -> String {
    parameters.map { parameter in
        "\(parameter.externalName ?? ""):\(typeIdentity(parameter.type))"
    }.joined(separator: ",")
}

private func typeIdentity(_ type: TypeReference) -> String {
    switch type {
    case .named(let name, let arguments):
        return "\(name)<\(arguments.map(typeIdentity).joined(separator: ","))>"
    case .optional(let wrapped):
        return "\(typeIdentity(wrapped))?"
    case .array(let element):
        return "[\(typeIdentity(element))]"
    case .dictionary(let key, let value):
        return "[\(typeIdentity(key)):\(typeIdentity(value))]"
    case .tuple(let elements):
        return "(\(elements.map { "\($0.label ?? ""):\(typeIdentity($0.type))" }.joined(separator: ",")))"
    case .function(let function):
        return "(\(function.parameters.map(typeIdentity).joined(separator: ",")))->\(typeIdentity(function.returnType))"
    case .existential(let base):
        return "any \(typeIdentity(base))"
    case .opaque(let base):
        return "some \(typeIdentity(base))"
    case .attributed(let attributes, let base):
        return "\(attributes.map(\.name).joined(separator: ",")) \(typeIdentity(base))"
    case .inoutType(let base):
        return "inout \(typeIdentity(base))"
    case .unresolved(let text):
        return "unresolved:\(text)"
    }
}

private func memberDisplayName(_ member: Member) -> String {
    switch member {
    case .property(let property):
        property.name
    case .enumCase(let enumCase):
        enumCase.name
    case .method(let method):
        method.name
    case .initializer:
        "init"
    case .typeAlias(let typeAlias):
        typeAlias.name
    }
}

private func memberSourceLocation(_ member: Member) -> SourceRange? {
    switch member {
    case .property(let property):
        property.sourceLocation
    case .enumCase(let enumCase):
        enumCase.sourceLocation
    case .method(let method):
        method.sourceLocation
    case .initializer(let initializer):
        initializer.sourceLocation
    case .typeAlias(let typeAlias):
        typeAlias.sourceLocation
    }
}

private func memberReferencedType(_ member: Member) -> QualifiedName? {
    guard case .property(let property) = member,
          case .named(let name, let genericArguments) = property.type,
          genericArguments.isEmpty else {
        return nil
    }
    return name
}

private func relationshipIdentity(_ relationship: Relationship) -> String {
    [
        relationship.source.description,
        relationship.kind.rawValue,
        relationship.target.description,
        relationship.throughMember ?? "",
        relationship.label ?? ""
    ].joined(separator: "|")
}

private func makeDiagnostic(
    _ severity: DiagnosticSeverity,
    _ code: DiagnosticCode,
    _ message: String,
    _ fileName: String?,
    _ range: SourceRange?
) -> Diagnostic {
    Diagnostic(
        severity: severity,
        code: code,
        message: message,
        fileName: fileName,
        range: range
    )
}

private func diagnosticOrder(_ lhs: Diagnostic, _ rhs: Diagnostic) -> Bool {
    let lhsOffset = lhs.range?.start.offset ?? Int.max
    let rhsOffset = rhs.range?.start.offset ?? Int.max
    if lhsOffset != rhsOffset {
        return lhsOffset < rhsOffset
    }
    return lhs.code.rawValue < rhs.code.rawValue
}

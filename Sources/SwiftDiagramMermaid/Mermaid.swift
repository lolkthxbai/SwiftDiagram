import Foundation
import SwiftDiagramModel
import SwiftDiagramRendering

public struct MermaidRenderer: DiagramRenderer, Sendable {
    public let formatName = "mermaid"

    public init() {}

    public func render(
        _ diagram: Diagram,
        options: RenderOptions = RenderOptions()
    ) throws -> String {
        let declarations = filteredDeclarations(diagram.declarations, options: options)
        let relationships = filteredRelationships(diagram.relationships, options: options)
        let names = MermaidNameTable(
            names: declarations.map(\.name) + relationships.flatMap { [$0.source, $0.target] }
        )
        var lines = ["classDiagram"]

        if let orientation = options.orientation {
            lines.append("    direction \(orientation.mermaidValue)")
        }

        for declaration in declarations {
            lines.append(contentsOf: renderDeclaration(declaration, names: names, options: options))
        }
        for relationship in relationships {
            lines.append(renderRelationship(relationship, names: names))
        }

        return lines.joined(separator: "\n") + "\n"
    }
}

private func filteredDeclarations(
    _ declarations: [TypeDeclaration],
    options: RenderOptions
) -> [TypeDeclaration] {
    var result = declarations.filter { declaration in
        if options.excludedElements.contains(declaration.name.description) {
            return false
        }
        guard let accessLevels = options.declarationAccessLevels else { return true }
        return declaration.accessLevel.map(accessLevels.contains) ?? accessLevels.contains(.internal)
    }
    if options.sortDeclarations {
        result.sort { $0.name.description < $1.name.description }
    }
    return result
}

private func filteredRelationships(
    _ relationships: [Relationship],
    options: RenderOptions
) -> [Relationship] {
    relationships
        .filter {
            (options.includeInferredRelationships || $0.origin != .inferred) &&
            !options.excludedElements.contains($0.source.description) &&
            !options.excludedRelationshipTargets.contains($0.target.description)
        }
        .sorted {
            let lhs = ($0.source.description, $0.target.description, $0.kind.rawValue, $0.throughMember ?? "")
            let rhs = ($1.source.description, $1.target.description, $1.kind.rawValue, $1.throughMember ?? "")
            return lhs < rhs
        }
}

private func renderDeclaration(
    _ declaration: TypeDeclaration,
    names: MermaidNameTable,
    options: RenderOptions
) -> [String] {
    var lines = ["    class \(names[declaration.name]) {"]
    lines.append("        <<\(declaration.kind.rawValue)>>")
    if let accessLevel = declaration.accessLevel {
        lines.append("        <<\(accessLevel.rawValue)>>")
    }

    for member in declaration.members {
        guard shouldRender(member, options: options) else { continue }
        switch member {
        case .property(let property):
            lines.append(
                "        \(accessSymbol(property.accessLevel))\(renderType(property.type)) \(mermaidText(property.name))"
            )
        case .enumCase(let enumCase):
            lines.append("        \(renderEnumCase(enumCase))")
        case .method(let method) where options.includeMethods:
            lines.append("        \(renderMethod(method))")
        case .initializer(let initializer) where options.includeMethods:
            lines.append("        \(renderInitializer(initializer))")
        case .typeAlias(let typeAlias):
            lines.append("        \(renderType(typeAlias.assignedType)) \(mermaidText(typeAlias.name))")
        default:
            break
        }
    }

    lines.append("    }")
    return lines
}

private func shouldRender(_ member: Member, options: RenderOptions) -> Bool {
    let accessLevel: AccessLevel?
    switch member {
    case .property(let property): accessLevel = property.accessLevel
    case .method(let method): accessLevel = method.accessLevel
    case .initializer(let initializer): accessLevel = initializer.accessLevel
    case .typeAlias(let typeAlias): accessLevel = typeAlias.accessLevel
    case .enumCase: accessLevel = nil
    }

    if !options.includePrivateMembers && (accessLevel == .private || accessLevel == .fileprivate) {
        return false
    }
    guard let filters = options.memberAccessLevels else { return true }
    return accessLevel.map(filters.contains) ?? filters.contains(.internal)
}

private func renderRelationship(_ relationship: Relationship, names: MermaidNameTable) -> String {
    let source = names[relationship.source]
    let target = names[relationship.target]
    let connector: String
    switch relationship.kind {
    case .inherits: connector = "--|>"
    case .conforms: connector = "..|>"
    case .references: connector = "-->"
    case .owns: connector = "*--"
    case .contains: connector = "o--"
    case .extends: connector = "..>"
    case .accepts, .returns: connector = "..>"
    }

    let defaultLabel: String?
    switch relationship.kind {
    case .accepts: defaultLabel = "accepts"
    case .returns: defaultLabel = "returns"
    default: defaultLabel = nil
    }
    let label = relationship.label ?? relationship.throughMember ?? defaultLabel
    if let label, !label.isEmpty {
        return "    \(source) \(connector) \(target) : \(mermaidText(label))"
    }
    return "    \(source) \(connector) \(target)"
}

private func renderEnumCase(_ enumCase: EnumCaseDeclaration) -> String {
    let name = mermaidText(enumCase.name)
    guard !enumCase.associatedValues.isEmpty else { return name }
    return "\(name)(\(enumCase.associatedValues.map(renderParameter).joined(separator: ", ")))"
}

private func renderMethod(_ method: MethodDeclaration) -> String {
    var result = "\(accessSymbol(method.accessLevel))\(mermaidText(method.name))"
    result += "(\(method.parameters.map(renderParameter).joined(separator: ", ")))"
    if method.isAsync {
        result += " async"
    }
    if method.throwsKind != .none {
        result += " \(method.throwsKind.rawValue)"
    }
    if let returnType = method.returnType {
        result += " \(renderType(returnType))"
    }
    if method.isStatic {
        result += "$"
    }
    return result
}

private func renderInitializer(_ initializer: InitializerDeclaration) -> String {
    var result = "\(accessSymbol(initializer.accessLevel))init\(failabilitySuffix(initializer.failableKind))"
    result += "(\(initializer.parameters.map(renderParameter).joined(separator: ", ")))"
    if initializer.isAsync {
        result += " async"
    }
    if initializer.throwsKind != .none {
        result += " \(initializer.throwsKind.rawValue)"
    }
    return result
}

private func renderParameter(_ parameter: Parameter) -> String {
    let names = [parameter.externalName, parameter.localName].compactMap { $0 }
    let prefix = names.isEmpty ? "" : "\(names.map(mermaidText).joined(separator: " ")): "
    return "\(prefix)\(renderType(parameter.type))"
}

private func accessSymbol(_ accessLevel: AccessLevel?) -> String {
    switch accessLevel {
    case .public, .open: "+"
    case .private, .fileprivate: "-"
    case .internal, .package: "~"
    case nil: ""
    }
}

private func failabilitySuffix(_ kind: InitializerFailability) -> String {
    switch kind {
    case .none: ""
    case .optional: "?"
    case .implicitlyUnwrapped: "!"
    }
}

private func renderType(_ type: TypeReference) -> String {
    switch type {
    case .named(let name, let arguments):
        guard !arguments.isEmpty else { return mermaidText(name.description) }
        return "\(mermaidText(name.description))~\(arguments.map(renderType).joined(separator: ", "))~"
    case .optional(let wrapped):
        return "\(renderType(wrapped))?"
    case .array(let element):
        return "[\(renderType(element))]"
    case .dictionary(let key, let value):
        return "[\(renderType(key)): \(renderType(value))]"
    case .tuple(let elements):
        let contents = elements.map { element in
            if let label = element.label {
                return "\(mermaidText(label)): \(renderType(element.type))"
            }
            return renderType(element.type)
        }
        return "(\(contents.joined(separator: ", ")))"
    case .function(let function):
        let prefix = function.isEscaping ? "@escaping " : ""
        let parameters = function.parameters.map(renderType).joined(separator: ", ")
        return "\(prefix)(\(parameters)) -> \(renderType(function.returnType))"
    case .existential(let base):
        return "any \(renderType(base))"
    case .opaque(let base):
        return "some \(renderType(base))"
    case .attributed(let attributes, let base):
        let prefix = attributes.map { "@\(mermaidText($0.name))" }.joined(separator: " ")
        return prefix.isEmpty ? renderType(base) : "\(prefix) \(renderType(base))"
    case .inoutType(let base):
        return "inout \(renderType(base))"
    case .unresolved(let text):
        return mermaidText(text)
    }
}

private func mermaidText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: ":", with: "&#58;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

private struct MermaidNameTable {
    private var aliases: [QualifiedName: String] = [:]

    init(names: [QualifiedName]) {
        var used: Set<String> = []
        for name in Set(names).sorted(by: { $0.description < $1.description }) {
            let base = sanitizedIdentifier(name.description)
            var candidate = base
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(base)_\(suffix)"
                suffix += 1
            }
            used.insert(candidate)
            aliases[name] = candidate
        }
    }

    subscript(_ name: QualifiedName) -> String {
        aliases[name] ?? sanitizedIdentifier(name.description)
    }
}

private func sanitizedIdentifier(_ text: String) -> String {
    var result = text.map { character -> Character in
        character.isLetter || character.isNumber || character == "_" ? character : "_"
    }
    if result.isEmpty {
        return "type"
    }
    if result[0].isNumber {
        result.insert("_", at: 0)
    }
    return String(result)
}

private extension DiagramOrientation {
    var mermaidValue: String {
        switch self {
        case .topToBottom: "TB"
        case .bottomToTop: "BT"
        case .leftToRight: "LR"
        case .rightToLeft: "RL"
        }
    }
}

import Foundation
import SwiftDiagramModel
import SwiftDiagramRendering

public struct PlantUMLRenderer: DiagramRenderer, Sendable {
    public let formatName = "plantuml"

    public init() {}

    public func render(
        _ diagram: Diagram,
        options: RenderOptions = RenderOptions()
    ) throws -> String {
        let declarations = filteredDeclarations(diagram.declarations, options: options)
        let relationships = filteredRelationships(diagram.relationships, options: options)
        let names = PlantUMLNameTable(
            names: declarations.map(\.name) + relationships.flatMap { [$0.source, $0.target] }
        )
        var lines = ["@startuml", "hide empty members"]

        for declaration in declarations {
            lines.append(contentsOf: renderDeclaration(declaration, names: names, options: options))
        }
        for relationship in relationships {
            lines.append(renderRelationship(relationship, names: names))
        }
        lines.append("@enduml")
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
    names: PlantUMLNameTable,
    options: RenderOptions
) -> [String] {
    let keyword: String
    switch declaration.kind {
    case .enum: keyword = "enum"
    case .protocol: keyword = "interface"
    default: keyword = "class"
    }
    var stereotypes = [declaration.kind.rawValue]
    if let accessLevel = declaration.accessLevel {
        stereotypes.append(accessLevel.rawValue)
    }
    let stereotypeText = stereotypes.map { "<<\($0)>>" }.joined(separator: " ")
    var lines = [
        "\(keyword) \(plantQuoted(declaration.name.description)) as \(names[declaration.name]) \(stereotypeText) {"
    ]

    for member in declaration.members where shouldRender(member, options: options) {
        switch member {
        case .property(let property):
            lines.append("    \(accessSymbol(property.accessLevel))\(plantText(property.name)) : \(renderType(property.type))")
        case .method(let method) where options.includeMethods:
            lines.append("    \(renderMethod(method))")
        case .initializer(let initializer) where options.includeMethods:
            lines.append("    \(renderInitializer(initializer))")
        case .enumCase(let enumCase):
            lines.append("    \(renderEnumCase(enumCase))")
        case .typeAlias(let typeAlias):
            lines.append("    \(accessSymbol(typeAlias.accessLevel))\(plantText(typeAlias.name)) : \(renderType(typeAlias.assignedType))")
        default:
            break
        }
    }
    lines.append("}")
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

private func renderMethod(_ method: MethodDeclaration) -> String {
    var result = method.isStatic ? "{static} " : ""
    result += "\(accessSymbol(method.accessLevel))\(plantText(method.name))"
    result += "(\(method.parameters.map(renderParameter).joined(separator: ", ")))"
    if method.isAsync {
        result += " async"
    }
    if method.throwsKind != .none {
        result += " \(method.throwsKind.rawValue)"
    }
    if let returnType = method.returnType {
        result += " : \(renderType(returnType))"
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

private func renderEnumCase(_ enumCase: EnumCaseDeclaration) -> String {
    let name = plantText(enumCase.name)
    guard !enumCase.associatedValues.isEmpty else { return name }
    return "\(name)(\(enumCase.associatedValues.map(renderParameter).joined(separator: ", ")))"
}

private func renderParameter(_ parameter: Parameter) -> String {
    let names = [parameter.externalName, parameter.localName].compactMap { $0 }
    let prefix = names.isEmpty ? "" : "\(names.map(plantText).joined(separator: " ")): "
    return "\(prefix)\(renderType(parameter.type))"
}

private func renderRelationship(_ relationship: Relationship, names: PlantUMLNameTable) -> String {
    let source = names[relationship.source]
    let target = names[relationship.target]
    let line: String
    switch relationship.kind {
    case .inherits: line = "\(target) <|-- \(source)"
    case .conforms: line = "\(target) <|.. \(source)"
    case .references: line = "\(source) --> \(target)"
    case .owns: line = "\(source) *-- \(target)"
    case .contains: line = "\(source) o-- \(target)"
    case .accepts, .returns: line = "\(source) ..> \(target)"
    case .extends: line = "\(target) <.. \(source)"
    }
    let defaultLabel: String?
    switch relationship.kind {
    case .accepts: defaultLabel = "accepts"
    case .returns: defaultLabel = "returns"
    default: defaultLabel = nil
    }
    guard let label = relationship.label ?? relationship.throughMember ?? defaultLabel,
          !label.isEmpty else {
        return line
    }
    return "\(line) : \(plantText(label))"
}

private func renderType(_ type: TypeReference) -> String {
    switch type {
    case .named(let name, let arguments):
        guard !arguments.isEmpty else { return plantText(name.description) }
        return "\(plantText(name.description))<\(arguments.map(renderType).joined(separator: ", "))>"
    case .optional(let wrapped): return "\(renderType(wrapped))?"
    case .array(let element): return "[\(renderType(element))]"
    case .dictionary(let key, let value): return "[\(renderType(key)): \(renderType(value))]"
    case .tuple(let elements):
        let contents = elements.map { element in
            let prefix = element.label.map { "\(plantText($0)): " } ?? ""
            return "\(prefix)\(renderType(element.type))"
        }.joined(separator: ", ")
        return "(\(contents))"
    case .function(let function):
        let prefix = function.isEscaping ? "@escaping " : ""
        return "\(prefix)(\(function.parameters.map(renderType).joined(separator: ", "))) -> \(renderType(function.returnType))"
    case .existential(let base): return "any \(renderType(base))"
    case .opaque(let base): return "some \(renderType(base))"
    case .attributed(let attributes, let base):
        let prefix = attributes.map { "@\(plantText($0.name))" }.joined(separator: " ")
        return prefix.isEmpty ? renderType(base) : "\(prefix) \(renderType(base))"
    case .inoutType(let base): return "inout \(renderType(base))"
    case .unresolved(let text): return plantText(text)
    }
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

private func plantText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private func plantQuoted(_ text: String) -> String {
    "\"\(plantText(text))\""
}

private struct PlantUMLNameTable {
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

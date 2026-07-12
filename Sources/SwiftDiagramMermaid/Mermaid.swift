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
        let presentation = extensionPresentation(diagram, options: options)
        let localDeclarationNames = Set(presentation.declarations.map(\.name))
        let declarations = filteredDeclarations(presentation.declarations, options: options)
        let visibleDeclarationNames = Set(declarations.map(\.name))
        let separateExtensions = filteredExtensions(
            presentation.separate,
            localDeclarationNames: localDeclarationNames,
            visibleDeclarationNames: visibleDeclarationNames,
            options: options
        )
        let relationships = filteredRelationships(
            diagram.relationships + presentation.relationships,
            localDeclarationNames: localDeclarationNames,
            visibleDeclarationNames: visibleDeclarationNames,
            options: options
        )
        let names = MermaidNameTable(
            names: declarations.map(\.name) + relationships.flatMap { [$0.source, $0.target] } +
                separateExtensions.flatMap { [$0.alias, $0.target] + $0.conformances }
        )
        var lines = ["classDiagram"]

        if let orientation = options.orientation {
            lines.append("    direction \(orientation.mermaidValue)")
        }

        for declaration in declarations {
            lines.append(contentsOf: renderDeclaration(declaration, names: names, options: options))
        }
        for declaration in separateExtensions {
            lines.append(contentsOf: renderExtension(declaration, names: names, options: options))
        }
        for relationship in relationships {
            lines.append(renderRelationship(relationship, names: names))
        }

        return lines.joined(separator: "\n") + "\n"
    }
}

private struct MermaidExtensionPresentation {
    var declarations: [TypeDeclaration]
    var relationships: [Relationship]
    var separate: [PresentedExtension]
}

private struct PresentedExtension {
    var alias: QualifiedName
    var target: QualifiedName
    var displayType: TypeReference
    var conformances: [QualifiedName]
    var members: [Member]
}

private func extensionPresentation(_ diagram: Diagram, options: RenderOptions) -> MermaidExtensionPresentation {
    guard options.extensionDisplayMode != .hidden else {
        return MermaidExtensionPresentation(declarations: diagram.declarations, relationships: [], separate: [])
    }
    var declarations = diagram.declarations
    var relationships: [Relationship] = []
    var separate: [PresentedExtension] = []

    for (index, declaration) in diagram.extensions.enumerated() {
        guard case .named(let target, _) = declaration.extendedType,
              !GlobPatternMatcher.matchesAny(target.description, patterns: options.excludedElements) else { continue }
        let conformances = declaration.conformances.compactMap(namedType)
        if options.extensionDisplayMode == .merged,
           let declarationIndex = declarations.firstIndex(where: { $0.name == target }) {
            declarations[declarationIndex].members.append(contentsOf: declaration.members)
            relationships.append(contentsOf: conformances.map {
                Relationship(source: target, target: $0, kind: .conforms, origin: .explicit)
            })
        } else {
            separate.append(
                PresentedExtension(
                    alias: QualifiedName("__extension_\(index)_\(target.description)"),
                    target: target,
                    displayType: declaration.extendedType,
                    conformances: conformances,
                    members: declaration.members
                )
            )
        }
    }
    return MermaidExtensionPresentation(declarations: declarations, relationships: relationships, separate: separate)
}

private func namedType(_ type: TypeReference) -> QualifiedName? {
    guard case .named(let name, _) = type else { return nil }
    return name
}

private func filteredDeclarations(
    _ declarations: [TypeDeclaration],
    options: RenderOptions
) -> [TypeDeclaration] {
    var result = declarations.filter { declaration in
        if GlobPatternMatcher.matchesAny(declaration.name.description, patterns: options.excludedElements) {
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
    localDeclarationNames: Set<QualifiedName>,
    visibleDeclarationNames: Set<QualifiedName>,
    options: RenderOptions
) -> [Relationship] {
    relationships
        .filter { relationship in
            (options.includeInferredRelationships || relationship.origin != .inferred) &&
            visibleDeclarationNames.contains(relationship.source) &&
            (!localDeclarationNames.contains(relationship.target) || visibleDeclarationNames.contains(relationship.target)) &&
            !GlobPatternMatcher.matchesAny(relationship.source.description, patterns: options.excludedElements) &&
            !GlobPatternMatcher.matchesAny(relationship.target.description, patterns: options.excludedElements) &&
            !GlobPatternMatcher.matchesAny(
                relationship.target.description,
                patterns: options.excludedRelationshipTargets
            )
        }
        .sorted {
            let lhs = ($0.source.description, $0.target.description, $0.kind.rawValue, $0.throughMember ?? "")
            let rhs = ($1.source.description, $1.target.description, $1.kind.rawValue, $1.throughMember ?? "")
            return lhs < rhs
        }
}

private func filteredExtensions(
    _ extensions: [PresentedExtension],
    localDeclarationNames: Set<QualifiedName>,
    visibleDeclarationNames: Set<QualifiedName>,
    options: RenderOptions
) -> [PresentedExtension] {
    extensions.compactMap { declaration in
        if localDeclarationNames.contains(declaration.target) &&
            !visibleDeclarationNames.contains(declaration.target) {
            return nil
        }
        var result = declaration
        result.conformances = result.conformances.filter { conformance in
            (!localDeclarationNames.contains(conformance) || visibleDeclarationNames.contains(conformance)) &&
                !GlobPatternMatcher.matchesAny(conformance.description, patterns: options.excludedElements) &&
                !GlobPatternMatcher.matchesAny(
                    conformance.description,
                    patterns: options.excludedRelationshipTargets
                )
        }
        return result
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

private func renderExtension(
    _ declaration: PresentedExtension,
    names: MermaidNameTable,
    options: RenderOptions
) -> [String] {
    var lines = ["    class \(names[declaration.alias])[\"extension \(mermaidText(renderType(declaration.displayType)))\"] {"]
    lines.append("        <<extension>>")
    for member in declaration.members where shouldRender(member, options: options) {
        switch member {
        case .property(let property):
            lines.append("        \(accessSymbol(property.accessLevel))\(renderType(property.type)) \(mermaidText(property.name))")
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
    lines.append("    \(names[declaration.alias]) ..> \(names[declaration.target]) : extends")
    for conformance in declaration.conformances {
        lines.append("    \(names[declaration.alias]) ..|> \(names[conformance])")
    }
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

    if let filters = options.memberAccessLevels {
        return accessLevel.map(filters.contains) ?? filters.contains(.internal)
    }
    return options.includePrivateMembers || (accessLevel != .private && accessLevel != .fileprivate)
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
    var result = method.isMutating ? "mutating " : ""
    result += "\(accessSymbol(method.accessLevel))\(mermaidText(method.name))"
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

public struct Diagram: Equatable, Sendable, Codable {
    public var metadata: DiagramMetadata
    public var declarations: [TypeDeclaration]
    public var extensions: [ExtensionDeclaration]
    public var relationships: [Relationship]

    public init(
        metadata: DiagramMetadata = DiagramMetadata(),
        declarations: [TypeDeclaration] = [],
        extensions: [ExtensionDeclaration] = [],
        relationships: [Relationship] = []
    ) {
        self.metadata = metadata
        self.declarations = declarations
        self.extensions = extensions
        self.relationships = relationships
    }
}

public struct DiagramMetadata: Equatable, Sendable, Codable {
    public var languageVersion: SemanticVersion
    public var title: String?

    public init(
        languageVersion: SemanticVersion = .v1_0,
        title: String? = nil
    ) {
        self.languageVersion = languageVersion
        self.title = title
    }
}

public struct SemanticVersion: Equatable, Comparable, Sendable, Codable {
    public static let v1_0 = SemanticVersion(major: 1, minor: 0, patch: 0)

    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }

        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }

        return lhs.patch < rhs.patch
    }
}

public enum TypeKind: String, Equatable, Sendable, Codable {
    case `struct`
    case `class`
    case `enum`
    case `protocol`
    case actor
}

public struct TypeDeclaration: Equatable, Sendable, Codable {
    public var kind: TypeKind
    public var name: QualifiedName
    public var accessLevel: AccessLevel?
    public var genericParameters: [GenericParameter]
    public var conformances: [TypeReference]
    public var inheritedTypes: [TypeReference]
    public var members: [Member]
    public var sourceLocation: SourceRange?

    public init(
        kind: TypeKind,
        name: QualifiedName,
        accessLevel: AccessLevel? = nil,
        genericParameters: [GenericParameter] = [],
        conformances: [TypeReference] = [],
        inheritedTypes: [TypeReference] = [],
        members: [Member] = [],
        sourceLocation: SourceRange? = nil
    ) {
        self.kind = kind
        self.name = name
        self.accessLevel = accessLevel
        self.genericParameters = genericParameters
        self.conformances = conformances
        self.inheritedTypes = inheritedTypes
        self.members = members
        self.sourceLocation = sourceLocation
    }
}

public enum Member: Equatable, Sendable, Codable {
    case property(PropertyDeclaration)
    case method(MethodDeclaration)
    case enumCase(EnumCaseDeclaration)
    case initializer(InitializerDeclaration)
    case typeAlias(TypeAliasDeclaration)
}

public struct PropertyDeclaration: Equatable, Sendable, Codable {
    public var name: String
    public var type: TypeReference
    public var mutability: Mutability
    public var accessLevel: AccessLevel?
    public var accessor: PropertyAccessor?
    public var attributes: [Attribute]
    public var isolation: Isolation?
    public var sourceLocation: SourceRange?

    public init(
        name: String,
        type: TypeReference,
        mutability: Mutability,
        accessLevel: AccessLevel? = nil,
        accessor: PropertyAccessor? = nil,
        attributes: [Attribute] = [],
        isolation: Isolation? = nil,
        sourceLocation: SourceRange? = nil
    ) {
        self.name = name
        self.type = type
        self.mutability = mutability
        self.accessLevel = accessLevel
        self.accessor = accessor
        self.attributes = attributes
        self.isolation = isolation
        self.sourceLocation = sourceLocation
    }
}

public struct MethodDeclaration: Equatable, Sendable, Codable {
    public var name: String
    public var parameters: [Parameter]
    public var returnType: TypeReference?
    public var accessLevel: AccessLevel?
    public var isStatic: Bool
    public var isMutating: Bool
    public var isAsync: Bool
    public var throwsKind: ThrowsKind
    public var genericParameters: [GenericParameter]
    public var genericRequirements: [GenericRequirement]
    public var isolation: Isolation?
    public var sourceLocation: SourceRange?

    public init(
        name: String,
        parameters: [Parameter] = [],
        returnType: TypeReference? = nil,
        accessLevel: AccessLevel? = nil,
        isStatic: Bool = false,
        isMutating: Bool = false,
        isAsync: Bool = false,
        throwsKind: ThrowsKind = .none,
        genericParameters: [GenericParameter] = [],
        genericRequirements: [GenericRequirement] = [],
        isolation: Isolation? = nil,
        sourceLocation: SourceRange? = nil
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.accessLevel = accessLevel
        self.isStatic = isStatic
        self.isMutating = isMutating
        self.isAsync = isAsync
        self.throwsKind = throwsKind
        self.genericParameters = genericParameters
        self.genericRequirements = genericRequirements
        self.isolation = isolation
        self.sourceLocation = sourceLocation
    }
}

public struct EnumCaseDeclaration: Equatable, Sendable, Codable {
    public var name: String
    public var associatedValues: [Parameter]
    public var sourceLocation: SourceRange?

    public init(
        name: String,
        associatedValues: [Parameter] = [],
        sourceLocation: SourceRange? = nil
    ) {
        self.name = name
        self.associatedValues = associatedValues
        self.sourceLocation = sourceLocation
    }
}

public struct InitializerDeclaration: Equatable, Sendable, Codable {
    public var parameters: [Parameter]
    public var accessLevel: AccessLevel?
    public var failableKind: InitializerFailability
    public var isAsync: Bool
    public var throwsKind: ThrowsKind
    public var sourceLocation: SourceRange?

    public init(
        parameters: [Parameter] = [],
        accessLevel: AccessLevel? = nil,
        failableKind: InitializerFailability = .none,
        isAsync: Bool = false,
        throwsKind: ThrowsKind = .none,
        sourceLocation: SourceRange? = nil
    ) {
        self.parameters = parameters
        self.accessLevel = accessLevel
        self.failableKind = failableKind
        self.isAsync = isAsync
        self.throwsKind = throwsKind
        self.sourceLocation = sourceLocation
    }
}

public struct TypeAliasDeclaration: Equatable, Sendable, Codable {
    public var name: String
    public var assignedType: TypeReference
    public var accessLevel: AccessLevel?
    public var sourceLocation: SourceRange?

    public init(
        name: String,
        assignedType: TypeReference,
        accessLevel: AccessLevel? = nil,
        sourceLocation: SourceRange? = nil
    ) {
        self.name = name
        self.assignedType = assignedType
        self.accessLevel = accessLevel
        self.sourceLocation = sourceLocation
    }
}

public struct ExtensionDeclaration: Equatable, Sendable, Codable {
    public var extendedType: TypeReference
    public var conformances: [TypeReference]
    public var genericRequirements: [GenericRequirement]
    public var members: [Member]
    public var sourceLocation: SourceRange?

    public init(
        extendedType: TypeReference,
        conformances: [TypeReference] = [],
        genericRequirements: [GenericRequirement] = [],
        members: [Member] = [],
        sourceLocation: SourceRange? = nil
    ) {
        self.extendedType = extendedType
        self.conformances = conformances
        self.genericRequirements = genericRequirements
        self.members = members
        self.sourceLocation = sourceLocation
    }
}

public struct Relationship: Equatable, Sendable, Codable {
    public var source: QualifiedName
    public var target: QualifiedName
    public var kind: RelationshipKind
    public var label: String?
    public var throughMember: String?
    public var origin: RelationshipOrigin
    public var classification: RelationshipClassification
    public var sourceLocation: SourceRange?

    public init(
        source: QualifiedName,
        target: QualifiedName,
        kind: RelationshipKind,
        label: String? = nil,
        throughMember: String? = nil,
        origin: RelationshipOrigin,
        classification: RelationshipClassification = .resolved,
        sourceLocation: SourceRange? = nil
    ) {
        self.source = source
        self.target = target
        self.kind = kind
        self.label = label
        self.throughMember = throughMember
        self.origin = origin
        self.classification = classification
        self.sourceLocation = sourceLocation
    }
}

public enum RelationshipKind: String, Equatable, Sendable, Codable {
    case inherits
    case conforms
    case references
    case owns
    case contains
    case accepts
    case returns
    case extends
}

public enum RelationshipOrigin: String, Equatable, Sendable, Codable {
    case explicit
    case inferred
    case imported
}

public enum RelationshipClassification: String, Equatable, Sendable, Codable {
    case resolved
    case assumed
    case unresolved
}

public enum AccessLevel: String, Equatable, Sendable, Codable {
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
    case open
}

public enum Mutability: String, Equatable, Sendable, Codable {
    case constant = "let"
    case variable = "var"
}

public enum PropertyAccessor: String, Equatable, Sendable, Codable {
    case get
    case getSet
}

public enum InitializerFailability: String, Equatable, Sendable, Codable {
    case none
    case optional
    case implicitlyUnwrapped
}

public enum ThrowsKind: String, Equatable, Sendable, Codable {
    case none
    case `throws`
    case `rethrows`
}

public struct QualifiedName: Equatable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    public init(_ text: String) {
        self.components = text
            .split(separator: ".")
            .map(String.init)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String {
        components.joined(separator: ".")
    }
}

public indirect enum TypeReference: Equatable, Sendable, Codable {
    case named(QualifiedName, genericArguments: [TypeReference])
    case optional(TypeReference)
    case array(TypeReference)
    case dictionary(key: TypeReference, value: TypeReference)
    case tuple([TupleElement])
    case function(FunctionType)
    case existential(TypeReference)
    case opaque(TypeReference)
    case attributed(attributes: [Attribute], base: TypeReference)
    case inoutType(TypeReference)
    case unresolved(String)
}

public struct TupleElement: Equatable, Sendable, Codable {
    public var label: String?
    public var type: TypeReference

    public init(label: String? = nil, type: TypeReference) {
        self.label = label
        self.type = type
    }
}

public struct FunctionType: Equatable, Sendable, Codable {
    public var parameters: [TypeReference]
    public var returnType: TypeReference
    public var isEscaping: Bool

    public init(
        parameters: [TypeReference],
        returnType: TypeReference,
        isEscaping: Bool = false
    ) {
        self.parameters = parameters
        self.returnType = returnType
        self.isEscaping = isEscaping
    }
}

public struct Parameter: Equatable, Sendable, Codable {
    public var externalName: String?
    public var localName: String?
    public var type: TypeReference
    public var defaultValue: String?
    public var sourceLocation: SourceRange?

    public init(
        externalName: String? = nil,
        localName: String? = nil,
        type: TypeReference,
        defaultValue: String? = nil,
        sourceLocation: SourceRange? = nil
    ) {
        self.externalName = externalName
        self.localName = localName
        self.type = type
        self.defaultValue = defaultValue
        self.sourceLocation = sourceLocation
    }
}

public struct GenericParameter: Equatable, Sendable, Codable {
    public var name: String
    public var inheritedType: TypeReference?

    public init(name: String, inheritedType: TypeReference? = nil) {
        self.name = name
        self.inheritedType = inheritedType
    }
}

public enum GenericRequirement: Equatable, Sendable, Codable {
    case conforms(parameter: TypeReference, to: TypeReference)
    case sameType(left: TypeReference, right: TypeReference)
}

public struct Attribute: Equatable, Sendable, Codable {
    public var name: String
    public var argumentText: String?

    public init(name: String, argumentText: String? = nil) {
        self.name = name
        self.argumentText = argumentText
    }
}

public enum Isolation: Equatable, Sendable, Codable {
    case globalActor(QualifiedName)
    case nonisolated
}

public struct SourcePosition: Equatable, Sendable, Codable {
    public var line: Int
    public var column: Int
    public var offset: Int

    public init(line: Int, column: Int, offset: Int) {
        self.line = line
        self.column = column
        self.offset = offset
    }
}

public struct SourceRange: Equatable, Sendable, Codable {
    public var start: SourcePosition
    public var end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }
}

public struct Diagnostic: Equatable, Sendable, Codable {
    public var severity: DiagnosticSeverity
    public var code: DiagnosticCode
    public var message: String
    public var fileName: String?
    public var range: SourceRange?
    public var notes: [DiagnosticNote]
    public var fixIts: [FixIt]

    public init(
        severity: DiagnosticSeverity,
        code: DiagnosticCode,
        message: String,
        fileName: String? = nil,
        range: SourceRange? = nil,
        notes: [DiagnosticNote] = [],
        fixIts: [FixIt] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.fileName = fileName
        self.range = range
        self.notes = notes
        self.fixIts = fixIts
    }
}

public enum DiagnosticSeverity: String, Equatable, Sendable, Codable {
    case error
    case warning
    case note
}

public struct DiagnosticCode: Equatable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public struct DiagnosticNote: Equatable, Sendable, Codable {
    public var message: String
    public var range: SourceRange?

    public init(message: String, range: SourceRange? = nil) {
        self.message = message
        self.range = range
    }
}

public struct FixIt: Equatable, Sendable, Codable {
    public var message: String
    public var range: SourceRange
    public var replacement: String

    public init(message: String, range: SourceRange, replacement: String) {
        self.message = message
        self.range = range
        self.replacement = replacement
    }
}

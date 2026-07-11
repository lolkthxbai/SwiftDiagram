import XCTest
import SwiftDiagramModel
@testable import SwiftDiagramParser

final class ParserTests: XCTestCase {
    func testLowersDeclarationsMembersAndRelationships() {
        let source = """
        protocol Identifiable {
            var id: UUID { get }
        }
        class Person {}
        class Employee: Person, Identifiable {
            let id: UUID
        }
        enum Role {
            case engineer
        }
        Employee references Role
        """

        let result = SwiftDiagramParser().parse(source: source, fileName: "Model.swd")

        XCTAssertFalse(result.hasErrors)
        XCTAssertEqual(result.diagram?.declarations.count, 4)
        XCTAssertEqual(
            result.diagram?.relationships.map(\.kind),
            [.inherits, .conforms, .references]
        )
        XCTAssertEqual(
            result.diagram?.relationships.map(\.classification),
            [.resolved, .resolved, .resolved]
        )
    }

    func testUnresolvedFirstClassEntryDefaultsToAssumedSuperclass() {
        let result = SwiftDiagramParser().parse(
            source: "class Screen: UIViewController {}",
            fileName: "Screen.swd"
        )

        XCTAssertEqual(result.diagram?.relationships.first?.kind, .inherits)
        XCTAssertEqual(result.diagram?.relationships.first?.classification, .assumed)
        let diagnostic = result.diagnostics.first { $0.code.rawValue == "SWD2014" }
        XCTAssertEqual(diagnostic?.severity, .note)
        XCTAssertEqual(diagnostic?.range?.start.column, 15)
    }

    func testExplicitRelationshipOverridesAssumedClause() {
        let source = """
        class Service: External {}
        Service conforms External
        """
        let result = SwiftDiagramParser().parse(source: source, fileName: nil)

        XCTAssertEqual(result.diagram?.relationships.count, 1)
        XCTAssertEqual(result.diagram?.relationships.first?.kind, .conforms)
        XCTAssertEqual(result.diagram?.relationships.first?.classification, .resolved)
        XCTAssertFalse(result.diagnostics.contains { $0.code.rawValue == "SWD2014" })
        XCTAssertEqual(result.diagram?.declarations.first?.conformances.count, 1)
        XCTAssertTrue(result.diagram?.declarations.first?.inheritedTypes.isEmpty == true)
    }

    func testInvalidInheritanceProducesLocatedDiagnostic() {
        let source = """
        class Base {}
        struct Value: Base {}
        """
        let result = SwiftDiagramParser().parse(source: source, fileName: "Invalid.swd")

        let diagnostic = result.diagnostics.first { $0.code.rawValue == "SWD2010" }
        XCTAssertEqual(diagnostic?.severity, .error)
        XCTAssertEqual(diagnostic?.fileName, "Invalid.swd")
        XCTAssertEqual(diagnostic?.range?.start.line, 2)
        XCTAssertEqual(diagnostic?.range?.start.column, 15)
    }

    func testResolverClassifiesStructEnumAndLaterClassEntries() {
        let source = """
        protocol LocalProtocol {}
        class Base {}
        struct Payload: ExternalProtocol {}
        enum State: LocalProtocol {}
        class Child: Base, ExternalProtocol {}
        """
        let result = SwiftDiagramParser().parse(source: source, fileName: nil)

        XCTAssertFalse(result.hasErrors)
        XCTAssertEqual(
            result.diagram?.relationships.map(\.kind),
            [.conforms, .conforms, .inherits, .conforms]
        )
        XCTAssertEqual(
            result.diagram?.relationships.map(\.classification),
            [.resolved, .resolved, .resolved, .resolved]
        )
    }

    func testLowersEveryMilestoneTwoTypeReferenceForm() throws {
        let source = """
        struct Types {
            let optional: User?
            let array: [User]
            let dictionary: [String: [User]?]
            let generic: Result<User, Error>
            let tuple: (primary: User, Int)
            let callback: @escaping (User) -> Void
            let existential: any Service
            let opaque: some Service
            let input: inout User
            let qualified: Foundation.URL
        }
        """

        let result = SwiftDiagramParser().parse(source: source, fileName: "Types.swd")

        XCTAssertFalse(result.hasErrors, result.diagnostics.map(\.message).joined(separator: "\n"))
        let properties: [PropertyDeclaration] = try XCTUnwrap(
            result.diagram?.declarations.first?.members.compactMap { member -> PropertyDeclaration? in
            guard case .property(let property) = member else { return nil }
            return property
            }
        )
        XCTAssertEqual(properties[0].type, .optional(.named("User", genericArguments: [])))
        XCTAssertEqual(properties[1].type, .array(.named("User", genericArguments: [])))
        XCTAssertEqual(
            properties[2].type,
            .dictionary(
                key: .named("String", genericArguments: []),
                value: .optional(.array(.named("User", genericArguments: [])))
            )
        )
        XCTAssertEqual(
            properties[3].type,
            .named(
                "Result",
                genericArguments: [
                    .named("User", genericArguments: []),
                    .named("Error", genericArguments: [])
                ]
            )
        )
        XCTAssertEqual(
            properties[4].type,
            .tuple([
                TupleElement(label: "primary", type: .named("User", genericArguments: [])),
                TupleElement(type: .named("Int", genericArguments: []))
            ])
        )
        XCTAssertEqual(
            properties[5].type,
            .function(
                FunctionType(
                    parameters: [.named("User", genericArguments: [])],
                    returnType: .named("Void", genericArguments: []),
                    isEscaping: true
                )
            )
        )
        XCTAssertEqual(properties[6].type, .existential(.named("Service", genericArguments: [])))
        XCTAssertEqual(properties[7].type, .opaque(.named("Service", genericArguments: [])))
        XCTAssertEqual(properties[8].type, .inoutType(.named("User", genericArguments: [])))
        XCTAssertEqual(properties[9].type, .named("Foundation.URL", genericArguments: []))
    }

    func testParsesFunctionReturningFunction() throws {
        let result = SwiftDiagramParser().parse(
            source: "struct Factory { let make: () -> (Int) -> User }",
            fileName: nil
        )

        XCTAssertFalse(result.hasErrors)
        let declaration = try XCTUnwrap(result.diagram?.declarations.first)
        guard case .property(let property) = declaration.members.first,
              case .function(let outer) = property.type,
              case .function(let inner) = outer.returnType else {
            return XCTFail("Expected a nested function type")
        }
        XCTAssertTrue(outer.parameters.isEmpty)
        XCTAssertEqual(inner.parameters, [.named("Int", genericArguments: [])])
        XCTAssertEqual(inner.returnType, .named("User", genericArguments: []))
    }

    func testSingleParenthesizedTypeActsAsGrouping() throws {
        let result = SwiftDiagramParser().parse(
            source: "struct Value { let item: (User)? }",
            fileName: nil
        )

        let declaration = try XCTUnwrap(result.diagram?.declarations.first)
        guard case .property(let property) = declaration.members.first else {
            return XCTFail("Expected a property")
        }
        XCTAssertEqual(property.type, .optional(.named("User", genericArguments: [])))
    }

    func testMalformedTypeBecomesUnresolvedAndParsingContinues() throws {
        let source = """
        struct Broken {
            let value: Result<User,>
            let recovered: String
        }
        """

        let result = SwiftDiagramParser().parse(source: source, fileName: "Broken.swd")

        let diagnostic = try XCTUnwrap(result.diagnostics.first { $0.code.rawValue == "SWD1028" })
        XCTAssertEqual(diagnostic.range?.start.line, 2)
        XCTAssertEqual(diagnostic.fileName, "Broken.swd")
        let declaration = try XCTUnwrap(result.diagram?.declarations.first)
        guard case .property(let unresolved) = declaration.members[0],
              case .unresolved(let text) = unresolved.type,
              case .property(let recovered) = declaration.members[1] else {
            return XCTFail("Expected unresolved and recovered properties")
        }
        XCTAssertEqual(text, "Result<User,>")
        XCTAssertEqual(recovered.type, .named("String", genericArguments: []))
    }

    func testLowersMilestoneThreeMembersAccessAndRelationships() throws {
        let source = """
        public protocol Service {
            public var id: UUID { get }
            public func fetch(_ value: User, named name: String) async throws -> User?
        }
        open class Repository {
            public init?(rawValue: String)
        }
        public enum State {
            case idle, loaded(items: [User]), pair(String, Int)
        }
        struct User {}
        Repository accepts User
        Repository returns User
        """

        let result = SwiftDiagramParser().parse(source: source, fileName: "Members.swd")

        XCTAssertFalse(result.hasErrors, result.diagnostics.map(\.message).joined(separator: "\n"))
        let service = try XCTUnwrap(result.diagram?.declarations[0])
        XCTAssertEqual(service.accessLevel, .public)
        guard case .property(let property) = service.members[0],
              case .method(let method) = service.members[1] else {
            return XCTFail("Expected a property and method")
        }
        XCTAssertEqual(property.accessLevel, .public)
        XCTAssertEqual(method.parameters[0].externalName, "_")
        XCTAssertEqual(method.parameters[0].localName, "value")
        XCTAssertEqual(method.parameters[1].externalName, "named")
        XCTAssertEqual(method.parameters[1].localName, "name")
        XCTAssertTrue(method.isAsync)
        XCTAssertEqual(method.throwsKind, .throws)
        XCTAssertEqual(method.returnType, .optional(.named("User", genericArguments: [])))

        let repository = try XCTUnwrap(result.diagram?.declarations[1])
        XCTAssertEqual(repository.accessLevel, .open)
        guard case .initializer(let initializer) = repository.members.first else {
            return XCTFail("Expected an initializer")
        }
        XCTAssertEqual(initializer.failableKind, .optional)

        let state = try XCTUnwrap(result.diagram?.declarations[2])
        XCTAssertEqual(state.members.count, 3)
        guard case .enumCase(let loaded) = state.members[1] else {
            return XCTFail("Expected an associated-value case")
        }
        XCTAssertEqual(loaded.associatedValues.first?.externalName, "items")
        XCTAssertEqual(loaded.associatedValues.first?.type, .array(.named("User", genericArguments: [])))
        XCTAssertEqual(result.diagram?.relationships.map(\.kind), [.accepts, .returns])
    }
}

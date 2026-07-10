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
}

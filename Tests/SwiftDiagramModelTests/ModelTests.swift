import XCTest
@testable import SwiftDiagramModel

final class ModelTests: XCTestCase {
    func testDiagramConstruction() {
        let user = TypeDeclaration(
            kind: .struct,
            name: "User",
            accessLevel: .public,
            members: [
                .property(
                    PropertyDeclaration(
                        name: "id",
                        type: .named("UUID", genericArguments: []),
                        mutability: .constant
                    )
                )
            ]
        )

        let relationship = Relationship(
            source: "User",
            target: "Identifiable",
            kind: .conforms,
            origin: .explicit,
            classification: .resolved
        )

        let diagram = Diagram(
            metadata: DiagramMetadata(title: "User Model"),
            declarations: [user],
            relationships: [relationship]
        )

        XCTAssertEqual(diagram.metadata.languageVersion, .v1_0)
        XCTAssertEqual(diagram.declarations.first?.name.description, "User")
        XCTAssertEqual(diagram.relationships.first?.classification, .resolved)
    }

    func testCodableRoundTrip() throws {
        let diagram = Diagram(
            metadata: DiagramMetadata(title: "Round Trip"),
            declarations: [
                TypeDeclaration(
                    kind: .enum,
                    name: "LoadingState",
                    members: [
                        .enumCase(EnumCaseDeclaration(name: "idle"))
                    ]
                )
            ],
            relationships: [
                Relationship(
                    source: "ViewModel",
                    target: "LoadingState",
                    kind: .references,
                    throughMember: "state",
                    origin: .inferred,
                    classification: .resolved
                )
            ]
        )

        let data = try JSONEncoder().encode(diagram)
        let decoded = try JSONDecoder().decode(Diagram.self, from: data)

        XCTAssertEqual(decoded, diagram)
    }
}

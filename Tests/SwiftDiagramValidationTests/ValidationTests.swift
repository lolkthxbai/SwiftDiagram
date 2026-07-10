import XCTest
import SwiftDiagramModel
@testable import SwiftDiagramValidation

final class ValidationTests: XCTestCase {
    private let location = SourceRange(
        start: SourcePosition(line: 3, column: 1, offset: 20),
        end: SourcePosition(line: 3, column: 20, offset: 39)
    )

    func testReportsDuplicateDeclarationsAndMembers() {
        let property = Member.property(
            PropertyDeclaration(
                name: "id",
                type: .named("UUID", genericArguments: []),
                mutability: .constant,
                sourceLocation: location
            )
        )
        let diagram = Diagram(declarations: [
            TypeDeclaration(kind: .struct, name: "User", members: [property, property], sourceLocation: location),
            TypeDeclaration(kind: .struct, name: "User", sourceLocation: location)
        ])

        let diagnostics = SwiftDiagramValidator().validate(diagram, fileName: "Duplicates.swd")

        XCTAssertEqual(Set(diagnostics.map(\.code.rawValue)), ["SWD2001", "SWD2002"])
        XCTAssertTrue(diagnostics.allSatisfy { $0.fileName == "Duplicates.swd" && $0.range == location })
    }

    func testReportsUnknownReferenceTarget() {
        let diagram = Diagram(
            declarations: [TypeDeclaration(kind: .struct, name: "User")],
            relationships: [
                Relationship(
                    source: "User",
                    target: "Position",
                    kind: .references,
                    origin: .explicit,
                    sourceLocation: location
                )
            ]
        )

        let diagnostics = SwiftDiagramValidator().validate(diagram, fileName: "Unknown.swd")

        XCTAssertEqual(diagnostics.map(\.code.rawValue), ["SWD2004"])
        XCTAssertEqual(diagnostics.first?.range, location)
    }

    func testReportsMissingAndMismatchedThroughMembers() {
        let user = TypeDeclaration(
            kind: .struct,
            name: "User",
            members: [
                .property(
                    PropertyDeclaration(
                        name: "role",
                        type: .named("Role", genericArguments: []),
                        mutability: .variable
                    )
                )
            ]
        )
        let diagram = Diagram(
            declarations: [
                user,
                TypeDeclaration(kind: .enum, name: "Role"),
                TypeDeclaration(kind: .struct, name: "Team")
            ],
            relationships: [
                Relationship(
                    source: "User",
                    target: "Role",
                    kind: .references,
                    throughMember: "missing",
                    origin: .explicit,
                    sourceLocation: location
                ),
                Relationship(
                    source: "User",
                    target: "Team",
                    kind: .references,
                    throughMember: "role",
                    origin: .explicit,
                    sourceLocation: location
                )
            ]
        )

        let diagnostics = SwiftDiagramValidator().validate(diagram)

        XCTAssertEqual(Set(diagnostics.map(\.code.rawValue)), ["SWD2005", "SWD2006"])
    }

    func testReportsDuplicateConflictingAndInvalidRelationshipDirections() {
        let declarations = [
            TypeDeclaration(kind: .class, name: "Base"),
            TypeDeclaration(kind: .class, name: "Child"),
            TypeDeclaration(kind: .struct, name: "Value")
        ]
        let relationships = [
            Relationship(source: "Child", target: "Base", kind: .inherits, origin: .explicit),
            Relationship(source: "Child", target: "Base", kind: .inherits, origin: .explicit),
            Relationship(source: "Child", target: "Base", kind: .conforms, origin: .explicit),
            Relationship(source: "Value", target: "Base", kind: .inherits, origin: .explicit)
        ]

        let diagnostics = SwiftDiagramValidator().validate(
            Diagram(declarations: declarations, relationships: relationships)
        )
        let codes = Set(diagnostics.map(\.code.rawValue))

        XCTAssertTrue(codes.isSuperset(of: ["SWD2007", "SWD2008", "SWD2010", "SWD2015"]))
    }
}

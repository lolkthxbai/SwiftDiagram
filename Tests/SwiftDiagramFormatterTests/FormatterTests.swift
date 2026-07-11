import XCTest
import SwiftDiagramFormatter

final class FormatterTests: XCTestCase {
    func testCanonicalFormattingPreservesCommentsAndIsIdempotent() {
        let source = """
        swiftDiagram   1.0
        diagram  "Milestone 4"
        /* outer
         /* nested */
        */
        struct User{@MainActor
        var name:String{get set} // trailing
        static func make( )->User}
        extension User:Codable{mutating func rename(to name:String)}
        User owns User through name
        """
        let expected = """
        swiftDiagram 1.0
        diagram "Milestone 4"

        /* outer
         /* nested */
        */
        struct User {
            @MainActor
            var name: String { get set } // trailing
            static func make() -> User
        }

        extension User: Codable {
            mutating func rename(to name: String)
        }

        User owns User through name
        """ + "\n"
        let formatter = SwiftDiagramFormatter()

        let first = formatter.format(source: source, fileName: "Messy.swd")
        let second = formatter.format(source: expected, fileName: "Canonical.swd")

        XCTAssertFalse(first.hasErrors, first.diagnostics.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(first.text, expected)
        XCTAssertTrue(first.changed)
        XCTAssertEqual(second.text, expected)
        XCTAssertFalse(second.changed)
    }

    func testInvalidSyntaxIsNotRewritten() {
        let source = "struct User { let id UUID }"

        let result = SwiftDiagramFormatter().format(source: source, fileName: "Invalid.swd")

        XCTAssertTrue(result.hasErrors)
        XCTAssertEqual(result.text, source)
        XCTAssertFalse(result.changed)
    }

    func testBlockCommentBetweenBraceAndMemberKeepsMemberIndentation() {
        let source = "struct User { /* member note */ let id: UUID }"

        let result = SwiftDiagramFormatter().format(source: source)

        XCTAssertEqual(
            result.text,
            "struct User {\n    /* member note */\n    let id: UUID\n}\n"
        )
    }
}

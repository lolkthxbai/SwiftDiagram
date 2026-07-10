import XCTest
import SwiftDiagramSyntax
@testable import SwiftDiagramSyntaxParser

final class SyntaxParserTests: XCTestCase {
    func testParsesMilestoneOneSyntaxAndPreservesComments() {
        let source = """
        // heading
        struct User { // declaration
            let id: UUID
        }
        """

        let result = DiagramSyntaxParser().parseSyntax(source: source, fileName: "User.swd")

        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.sourceFile.statements.count, 1)
        guard case .declaration(let declaration) = result.sourceFile.statements[0] else {
            return XCTFail("Expected a declaration")
        }
        XCTAssertEqual(declaration.kind, .struct)
        XCTAssertEqual(declaration.name.name, "User")
        XCTAssertEqual(declaration.members.count, 1)

        let structToken = result.sourceFile.tokens.first { $0.text == "struct" }
        XCTAssertEqual(structToken?.range.start.line, 2)
        XCTAssertTrue(structToken?.leadingTrivia.contains(.lineComment("// heading")) == true)
        let openBrace = result.sourceFile.tokens.first { $0.text == "{" }
        XCTAssertTrue(openBrace?.trailingTrivia.contains(.lineComment("// declaration")) == true)
    }

    func testNestedBlockCommentsRemainTrivia() {
        let source = "/* outer /* inner */ end */\nstruct User {}"
        let result = DiagramSyntaxParser().parseSyntax(source: source, fileName: nil)

        XCTAssertTrue(result.diagnostics.isEmpty)
        let structToken = result.sourceFile.tokens.first { $0.text == "struct" }
        XCTAssertTrue(
            structToken?.leadingTrivia.contains(.blockComment("/* outer /* inner */ end */")) == true
        )
    }

    func testRecoversAfterMalformedMemberAndRelationship() {
        let source = """
        struct Broken {
            let : UUID
            var name: String
        }
        Broken references
        """
        let result = DiagramSyntaxParser().parseSyntax(source: source, fileName: "Broken.swd")

        XCTAssertGreaterThanOrEqual(result.diagnostics.count, 2)
        XCTAssertTrue(result.diagnostics.allSatisfy { $0.range.start.line > 0 && $0.range.start.column > 0 })
        guard case .declaration(let declaration) = result.sourceFile.statements.first else {
            return XCTFail("Expected recovered declaration")
        }
        guard case .property(let property) = declaration.members.first else {
            return XCTFail("Expected recovered property")
        }
        XCTAssertEqual(property.name, "name")
    }

    func testReportsUnterminatedStringAtItsSourceRange() {
        let result = DiagramSyntaxParser().parseSyntax(
            source: "diagram \"Unfinished\nstruct User {}",
            fileName: "Broken.swd"
        )

        let diagnostic = result.diagnostics.first { $0.code == "SWD1001" }
        XCTAssertEqual(diagnostic?.fileName, "Broken.swd")
        XCTAssertEqual(diagnostic?.range.start.line, 1)
        XCTAssertEqual(diagnostic?.range.start.column, 9)
    }

    func testRejectsCompoundTypeReferencesInMilestoneOne() {
        let result = DiagramSyntaxParser().parseSyntax(
            source: "struct User { var manager: Employee? }",
            fileName: "User.swd"
        )

        let diagnostic = result.diagnostics.first { $0.code == "SWD1021" }
        XCTAssertEqual(diagnostic?.range.start.column, 36)
    }
}

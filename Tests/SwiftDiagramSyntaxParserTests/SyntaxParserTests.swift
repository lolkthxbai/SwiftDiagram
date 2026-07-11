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

    func testParsesCompoundTypeReferenceSyntax() {
        let result = DiagramSyntaxParser().parseSyntax(
            source: "struct User { var manager: [String: Employee?] }",
            fileName: "User.swd"
        )

        XCTAssertTrue(result.diagnostics.isEmpty)
        guard case .declaration(let declaration) = result.sourceFile.statements.first,
              case .property(let property) = declaration.members.first,
              case .dictionary(let key, let value, _) = property.type,
              case .named(let keyName, [], _) = key,
              case .optional(let wrapped, _) = value,
              case .named(let valueName, [], _) = wrapped else {
            return XCTFail("Expected a dictionary with an optional value")
        }
        XCTAssertEqual(keyName, "String")
        XCTAssertEqual(valueName, "Employee")
    }

    func testRecoversFromMalformedMethodAtNextMember() {
        let source = """
        struct Broken {
            func load(id UUID)
            var recovered: String
        }
        """

        let result = DiagramSyntaxParser().parseSyntax(source: source, fileName: "Broken.swd")

        XCTAssertTrue(result.diagnostics.contains { $0.code == "SWD1031" })
        guard case .declaration(let declaration) = result.sourceFile.statements.first,
              case .property(let property) = declaration.members.first else {
            return XCTFail("Expected parser recovery at the property")
        }
        XCTAssertEqual(property.name, "recovered")
    }

    func testParsesMilestoneFourExtensionsAttributesAndMethodModifiers() {
        let source = """
        struct User {
            @MainActor
            var name: String { get set }
            @Factory("preview")
            static func make() -> User
            mutating func rename(to name: String)
        }
        extension User: Codable {
            var displayName: String { get }
        }
        User owns Profile through profile
        Team contains User through users
        User extends Profile
        """

        let result = DiagramSyntaxParser().parseSyntax(source: source, fileName: "Milestone4.swd")

        XCTAssertTrue(result.diagnostics.isEmpty, result.diagnostics.map(\.message).joined(separator: "\n"))
        guard case .declaration(let user) = result.sourceFile.statements[0],
              case .property(let property) = user.members[0],
              case .method(let factory) = user.members[1],
              case .method(let rename) = user.members[2],
              case .extension(let userExtension) = result.sourceFile.statements[1],
              case .relationship(let owns) = result.sourceFile.statements[2],
              case .relationship(let contains) = result.sourceFile.statements[3],
              case .relationship(let extends) = result.sourceFile.statements[4] else {
            return XCTFail("Expected Milestone 4 syntax nodes")
        }
        XCTAssertEqual(property.attributes.map(\.name), ["MainActor"])
        XCTAssertEqual(property.accessor, .getSet)
        XCTAssertEqual(factory.attributes.first?.argumentText, "\"preview\"")
        XCTAssertTrue(factory.isStatic)
        XCTAssertTrue(rename.isMutating)
        XCTAssertEqual(userExtension.members.count, 1)
        XCTAssertEqual(owns.kind, .owns)
        XCTAssertEqual(contains.kind, .contains)
        XCTAssertEqual(extends.kind, .extends)
    }
}

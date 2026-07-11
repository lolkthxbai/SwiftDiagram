import Foundation
import XCTest
import SwiftDiagramCore
import SwiftDiagramMermaid
import SwiftDiagramModel
import SwiftDiagramRendering

final class MermaidTests: XCTestCase {
    func testBasicFixtureMatchesGoldenOutput() throws {
        let fixtureDirectory = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/Basics", isDirectory: true)
        let source = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("input.swd"),
            encoding: .utf8
        )
        let expected = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("expected.mmd"),
            encoding: .utf8
        )

        let result = SwiftDiagramService().render(source: source, fileName: "input.swd")

        XCTAssertFalse(result.hasErrors, result.diagnostics.map(DiagnosticFormatter.format).joined(separator: "\n"))
        XCTAssertEqual(result.output, expected)
    }

    func testOutputIsDeterministicAcrossRuns() {
        let source = """
        enum Zed { case last }
        struct Alpha { let value: Zed }
        Alpha references Zed through value
        """
        let service = SwiftDiagramService()

        let first = service.render(source: source).output
        let second = service.render(source: source).output

        XCTAssertEqual(first, second)
        XCTAssertTrue(first?.contains("class Alpha") == true)
    }

    func testTypeReferencesFixtureMatchesGoldenOutput() throws {
        let fixtureDirectory = repositoryRoot
            .appendingPathComponent("Tests/Fixtures/TypeReferences", isDirectory: true)
        let source = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("input.swd"),
            encoding: .utf8
        )
        let expected = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("expected.mmd"),
            encoding: .utf8
        )

        let result = SwiftDiagramService().render(source: source, fileName: "input.swd")

        XCTAssertFalse(result.hasErrors, result.diagnostics.map(DiagnosticFormatter.format).joined(separator: "\n"))
        XCTAssertEqual(result.output, expected)
    }

    func testStaticMethodUsesMermaidStaticClassifier() throws {
        let diagram = Diagram(
            declarations: [
                TypeDeclaration(
                    kind: .struct,
                    name: "Factory",
                    members: [
                        .method(
                            MethodDeclaration(
                                name: "make",
                                returnType: .named("Factory", genericArguments: []),
                                accessLevel: .public,
                                isStatic: true
                            )
                        )
                    ]
                )
            ]
        )

        let output = try MermaidRenderer().render(diagram, options: RenderOptions())

        XCTAssertTrue(output.contains("+make() Factory$"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
